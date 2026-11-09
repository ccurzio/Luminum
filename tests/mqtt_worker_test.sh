#!/usr/bin/env bash
# MQTT worker (server side) integration test (protocol 4, 9): runs the real
# Luminum::MQTT::worker (a forked Perl process) against a scratch Mosquitto
# broker and a scratch MySQL CLIENTS database, with the Rust client as the
# endpoint. Verifies end to end:
#   - ACL file generation from the DB (regen_acl: OS values + group names)
#   - password_file maintenance (on_register adds, on_deactivate removes)
#   - check-in on the per-UID status topic updates CLIENTS.STATUS
#   - an outbox command (PENDING) is published by the worker, verified by the
#     client, and marked ACKED on the client's response
#   - an OS-targeted command is published to the lowercased OS topic and acked
#   - a group-targeted command is delivered to the group topic and acked
#   - a query round trip: the config row (sensor definitions) and the query
#     row are published in ID order, both are ACKED (the answer by data.qid),
#     and the per-sensor result is stored in QUERYRESULTS
#   - an unanswered query is marked TIMEDOUT at its deadline (not republished)
#   - the offline LWT on client death flips STATUS.CSTATE to OFFLINE
#
# Unlike tests/mqtt_client_test.sh (which stands in for the server with
# mosquitto_pub), this test exercises the actual worker: it signs commands
# with the server key, publishes them from the DB outbox, and correlates the
# client's responses back to the outbox rows.
#
# Usage: bash tests/mqtt_worker_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
CLIENT_BIN="$REPO/client/linux/target/debug/LuminumClient"
[ -x "$CLIENT_BIN" ] || { echo "SKIP - client binary not built at $CLIENT_BIN"; exit 0; }
[ -x "$(command -v openssl)" ]        || { echo "SKIP - openssl not available"; exit 0; }
[ -x "$(command -v mosquitto)" ]      || { echo "SKIP - mosquitto not available"; exit 0; }
[ -x "$(command -v mosquitto_passwd)" ] || { echo "SKIP - mosquitto_passwd not available"; exit 0; }
[ -x "$(command -v mysql)" ]          || { echo "SKIP - mysql client not available"; exit 0; }
[ -S /tmp/mysqld.sock ]               || { echo "SKIP - MariaDB not running at /tmp/mysqld.sock"; exit 0; }
# Luminum::MQTT + Luminum::Protocol live in the repo; the broker's non-core
# modules (Crypt::Perl::Ed25519, Net::MQTT::Simple, IO::Socket::SSL, DBD::mysql)
# come from the ambient PERL5LIB.
PERL_LIBS="$REPO/server/lib${PERL5LIB:+:$PERL5LIB}"
PERL5LIB="$PERL_LIBS" perl -e \
    'use Crypt::Perl::Ed25519::PrivateKey; use Crypt::Perl::Ed25519::PublicKey;
     use DBI; use DBD::mysql; use Net::MQTT::Simple::SSL; use Luminum::MQTT;' 2>/dev/null \
    || { echo "SKIP - Perl dependencies for the MQTT worker are missing"; exit 0; }

PORT=18884
SID=1
UID_TEST=42
CLIENT_SECRET="testsecret123"
SERVER_USER="luminum-server"
SERVER_SECRET="serversecret123"
GROUP="testgrp"
DBSOCK=/tmp/mysqld.sock
DBNAME="LUMWORKERTEST_$$"

SCRATCH="$HOME/.lumworker-mqtt-test.$$"
CERTDIR="$SCRATCH/certs"
HOME_TEST="$SCRATCH/home"
FAILURES=0
MOSQ_PID=""; CLIENT_PID=""; WORKER_PID=""

check() {
    local name="$1" ok="$2" detail="${3:-}"
    if [ "$ok" -eq 0 ]; then
        echo "ok   - $name"
    else
        FAILURES=$((FAILURES + 1))
        echo "FAIL - $name${detail:+ ($detail)}"
    fi
}

cleanup() {
    [ -n "$CLIENT_PID" ] && kill -9 "$CLIENT_PID" 2>/dev/null
    [ -n "$WORKER_PID" ] && kill "$WORKER_PID" 2>/dev/null
    [ -n "$MOSQ_PID" ] && kill "$MOSQ_PID" 2>/dev/null
    mysql --socket="$DBSOCK" -u root -e "drop database if exists \`$DBNAME\`;" 2>/dev/null
    # Leave the scratch dir (worker.log, mosquitto.log, client.log) behind on
    # failure so the run can be inspected; remove it on success.
    if [ "$FAILURES" -gt 0 ]; then
        echo "Artifacts left in $SCRATCH for inspection."
    else
        rm -rf "$SCRATCH"
    fi
}
trap cleanup EXIT

dbq() {
    mysql --socket="$DBSOCK" -u root -N -e "$1" "$DBNAME" 2>/dev/null
}

# --- TLS certificate: a CA (trust anchor) + a server leaf it signs -----------
# webpki (the Rust client's rustls) refuses a CA:TRUE cert as the presented
# leaf, so the broker presents a real leaf signed by a separate CA. The client
# stores the CA as its trust anchor; the leaf SAN covers the hostname the
# client verifies ("127.0.0.1" becomes a DNS name).
mkdir -p "$CERTDIR" || exit 1
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout "$CERTDIR/ca.key" -out "$CERTDIR/ca.pem" \
    -subj "/CN=Luminum Test CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
openssl genpkey -algorithm rsa -pkeyopt rsa_keygen_bits:2048 -out "$CERTDIR/tls.key" 2>/dev/null
openssl req -new -key "$CERTDIR/tls.key" -subj "/CN=127.0.0.1" -out "$CERTDIR/tls.csr" 2>/dev/null
cat > "$CERTDIR/tls.ext" <<'EOF'
subjectAltName=DNS:127.0.0.1,IP:127.0.0.1
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF
openssl x509 -req -in "$CERTDIR/tls.csr" -CA "$CERTDIR/ca.pem" -CAkey "$CERTDIR/ca.key" \
    -set_serial 0x01 -days 30 -extfile "$CERTDIR/tls.ext" -out "$CERTDIR/tls.crt" 2>/dev/null
[ -s "$CERTDIR/tls.crt" ] || { echo "SKIP - could not issue the TLS server leaf"; exit 0; }

# --- server Ed25519 signing key (the worker signs commands with this) --------
openssl genpkey -algorithm ed25519 -out "$CERTDIR/srv.key" 2>/dev/null
# PKCS#8 Ed25519 DER is a fixed 48-byte prefix + the 32-byte seed.
openssl pkey -in "$CERTDIR/srv.key" -outform DER 2>/dev/null | tail -c 32 > "$CERTDIR/srv.seed"
[ "$(stat -c %s "$CERTDIR/srv.seed")" = "32" ] || { echo "SKIP - could not derive the server signing seed"; exit 0; }
# SRVPUB = base64 of the raw 32-byte public key (what the client stores).
SRVPUB_B64=$(PERL5LIB="$PERL_LIBS" perl -e '
    use Crypt::Perl::Ed25519::PrivateKey; use MIME::Base64;
    open(my $sf, "<", $ARGV[0]) or die "seed: $!"; binmode($sf); read($sf, my $seed, 32); close($sf);
    my $priv = Crypt::Perl::Ed25519::PrivateKey->new($seed);
    print encode_base64($priv->get_public_key()->get_public(), "");
' "$CERTDIR/srv.seed")
[ -n "$SRVPUB_B64" ] || { echo "SKIP - could not derive the server public key"; exit 0; }

# --- scratch MySQL CLIENTS database ------------------------------------------
mysql --socket="$DBSOCK" -u root <<SQL
create database \`$DBNAME\` default character set utf8mb4 collate utf8mb4_general_ci;
use \`$DBNAME\`;
create table AUTH (
  ID int(20) not null auto_increment,
  NAME tinytext not null,
  FINGERPRINT tinytext not null,
  PUBKEY text not null,
  MQTTSECRET char(64) not null,
  primary key (ID)
) engine=InnoDB default charset=utf8mb4;
create table GROUPS (
  ID int(20) not null auto_increment,
  NAME tinytext not null,
  AUTHOR int(20) default null,
  CREATED datetime not null,
  MODIFIED datetime default null,
  EDITOR int(20) default null,
  primary key (ID)
) engine=InnoDB default charset=utf8mb4;
create table STATUS (
  ID int(20) not null,
  HOSTNAME tinytext not null,
  IPV4 tinytext not null,
  IPV6 tinytext default null,
  OSPLATFORM tinytext not null,
  OSRELEASE tinytext not null,
  CLIENTVER tinytext not null,
  CSTATE tinytext not null,
  INGROUPS text default null,
  REGDATE datetime not null,
  LASTSEEN datetime default null,
  MISSING tinyint(1) default 0,
  primary key (ID)
) engine=InnoDB default charset=utf8mb4;
create table COMMANDS (
  ID int(20) not null auto_increment,
  SID int(20) not null,
  TARGET tinytext not null,
  LUMY tinytext not null,
  ACTION tinytext not null,
  DATA text default null,
  QID char(36) not null,
  STATUS tinytext not null default 'PENDING',
  CREATED datetime not null,
  SENT datetime default null,
  ACKED datetime default null,
  DEADLINE datetime default null,
  primary key (ID),
  key IDX_COMMANDS_STATUS (STATUS)
) engine=InnoDB default charset=utf8mb4;
create table QUERYRESULTS (
  ID int(20) not null auto_increment,
  CMDID int(20) not null,
  QID char(36) not null,
  UID int(20) not null,
  SENSORID int(20) not null,
  STATUS tinytext not null,
  OUTPUT mediumtext default null,
  ERR tinytext default null,
  TS datetime not null,
  primary key (ID),
  key IDX_QUERYRESULTS_QID (QID)
) engine=InnoDB default charset=utf8mb4;
SQL
[ $? -eq 0 ] || { echo "SKIP - could not create the scratch database"; exit 0; }

# Seed a registered client (UID 42) + a group. MQTTSECRET stores the SHA-256
# hash (as the broker does); the client and mosquitto use the raw secret.
SECHASH=$(printf '%s' "$CLIENT_SECRET" | sha256sum | cut -d' ' -f1)
dbq "insert into AUTH (ID,NAME,FINGERPRINT,PUBKEY,MQTTSECRET) values ($UID_TEST,'worker-test','deadbeef','$SRVPUB_B64','$SECHASH');"
dbq "insert into GROUPS (ID,NAME,AUTHOR,CREATED) values (1,'$GROUP',1,now());"
dbq "insert into STATUS (ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,INGROUPS,REGDATE,LASTSEEN) values ($UID_TEST,'sentinel-host','127.0.0.1','Linux','6.1','0.0.1','OK','$GROUP',now(),'1970-01-01 00:00:00');"

# --- ACL file: generated from the DB by regen_acl ----------------------------
PERL5LIB="$PERL_LIBS" perl -e '
    use strict; use warnings;
    use DBI; use Luminum::MQTT;
    my ($db,$sid,$user,$acl,$pid,$sock) = @ARGV;
    my $dbh = DBI->connect("DBI:mysql:$db","root","", {mysql_socket=>$sock, PrintError=>0, RaiseError=>0}) or die "db: ".DBI->errstr;
    Luminum::MQTT::regen_acl($dbh, sid=>$sid, server_user=>$user, acl_file=>$acl, pid_file=>$pid);
    $dbh->disconnect();
' "$DBNAME" "$SID" "$SERVER_USER" "$SCRATCH/acl" "$SCRATCH/mosquitto.pid" "$DBSOCK"
check "regen_acl generated the ACL file" $([ -s "$SCRATCH/acl" ]; echo $?)
check "ACL grants the per-UID cmd topic (pattern %u)" "$(grep -q "pattern read  luminum/$SID/%u/cmd" "$SCRATCH/acl"; echo $?)"
check "ACL grants the all/cmd topic" "$(grep -q "pattern read  luminum/$SID/all/cmd" "$SCRATCH/acl"; echo $?)"
check "ACL enumerates the lowercased OS topic (os/linux)" "$(grep -q "pattern read  luminum/$SID/os/linux/cmd" "$SCRATCH/acl"; echo $?)"
check "ACL enumerates the group topic (grp/$GROUP)" "$(grep -q "pattern read  luminum/$SID/grp/$GROUP/cmd" "$SCRATCH/acl"; echo $?)"
check "ACL grants the server user readwrite over the tree" "$(grep -q "topic readwrite luminum/$SID/#" "$SCRATCH/acl"; echo $?)"

# --- Mosquitto password_file + config ----------------------------------------
mosquitto_passwd -b -c "$SCRATCH/passwd" "$UID_TEST" "$CLIENT_SECRET"
mosquitto_passwd -b "$SCRATCH/passwd" "$SERVER_USER" "$SERVER_SECRET"

cat > "$SCRATCH/mosquitto.conf" <<EOF
listener $PORT 127.0.0.1
cafile $CERTDIR/ca.pem
certfile $CERTDIR/tls.crt
keyfile $CERTDIR/tls.key
password_file $SCRATCH/passwd
acl_file $SCRATCH/acl
max_packet_size 65536
allow_anonymous false
pid_file $SCRATCH/mosquitto.pid
log_dest file $SCRATCH/mosquitto.log
log_type error
log_type warning
log_type notice
log_type debug
EOF
chmod 600 "$SCRATCH/acl" "$SCRATCH/passwd"

# --- start Mosquitto ----------------------------------------------------------
mosquitto -c "$SCRATCH/mosquitto.conf" &
MOSQ_PID=$!
ready=1
for i in $(seq 1 40); do
    if (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then
        exec 3>&- 3<&- 2>/dev/null
        ready=0
        break
    fi
    sleep 0.25
done
check "Mosquitto is listening on port $PORT" "$ready" "see $SCRATCH/mosquitto.log"
[ "$ready" -eq 0 ] || exit 1

# --- client home + pre-seeded config DB --------------------------------------
# UID/SID/MQTT* are pre-seeded so the client skips registration and goes
# straight to the MQTT control channel. SRVPUB is the worker's signing key so
# the client accepts the worker's commands.
mkdir -p "$HOME_TEST/config"
python3 - "$HOME_TEST" "$PORT" "$SRVPUB_B64" <<'EOF'
import sqlite3, sys
home, port, srvpub = sys.argv[1], sys.argv[2], sys.argv[3]
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
for k, v in [
    ("UID", "42"), ("SID", "1"),
    ("MQTTSECRET", "testsecret123"), ("MQTTHOST", "127.0.0.1"), ("MQTTPORT", port),
    ("GROUPS", "testgrp"), ("SRVPUB", srvpub),
]:
    conn.execute("insert into CONFIG (KEY,VALUE) values (?,?)", (k, v))
conn.commit()
EOF
chmod 600 "$HOME_TEST/config/client.conf.db"
cp "$CERTDIR/ca.pem" "$HOME_TEST/config/server.crt"

# --- worker driver (runs Luminum::MQTT::worker against the scratch DB) -------
# cmd_timeout is 5s (vs the 120s production default) so the TIMEDOUT check
# below does not have to wait out CMDTIMEOUT.
cat > "$SCRATCH/worker.pl" <<'EOF'
use strict; use warnings;
use Luminum::MQTT;
my ($seedfile, $sid, $host, $port, $ca, $user, $secret, $dbname, $dbsock, $cmdtimeout, $depltimeout) = @ARGV;
open(my $sf, "<", $seedfile) or die "seed: $!"; binmode($sf); read($sf, my $seed, 32); close($sf);
Luminum::MQTT::worker(
    sid => $sid, host => $host, port => $port, ca => $ca,
    user => $user, secret => $secret, seed => $seed,
    dbname => $dbname, dbuser => "root", dbpass => "", dbsock => $dbsock,
    poll_secs => 1,
    cmd_timeout => $cmdtimeout, depl_timeout => $depltimeout,
    log => sub { print "[worker] $_[0]\n"; },
);
EOF

PERL5LIB="$PERL_LIBS" perl "$SCRATCH/worker.pl" \
    "$CERTDIR/srv.seed" "$SID" 127.0.0.1 "$PORT" "$CERTDIR/ca.pem" \
    "$SERVER_USER" "$SERVER_SECRET" "$DBNAME" "$DBSOCK" 5 30 \
    > "$SCRATCH/worker.log" 2>&1 &
WORKER_PID=$!
sleep 1
check "worker process is alive after startup" "$(kill -0 "$WORKER_PID" 2>/dev/null; echo $?)" "see $SCRATCH/worker.log"

# --- start the client ---------------------------------------------------------
LUMINUM_HOME="$HOME_TEST" LUMINUM_CHECKIN_SECS=2 "$CLIENT_BIN" > "$SCRATCH/client.log" 2>&1 &
CLIENT_PID=$!
sleep 1
check "client process is alive after startup" "$(kill -0 "$CLIENT_PID" 2>/dev/null; echo $?)" "see $SCRATCH/client.log"

# --- check-in updates CLIENTS.STATUS -----------------------------------------
HOSTNAME_OK=1
for i in $(seq 1 40); do
    hn=$(dbq "select HOSTNAME from STATUS where ID=$UID_TEST;")
    [ -n "$hn" ] && [ "$hn" != "sentinel-host" ] && { HOSTNAME_OK=0; break; }
    sleep 0.5
done
check "check-in updated STATUS.HOSTNAME (no longer sentinel)" "$HOSTNAME_OK" "see $SCRATCH/worker.log"
CSTATE=$(dbq "select CSTATE from STATUS where ID=$UID_TEST;")
check "check-in set STATUS.CSTATE=OK" "$([ "$CSTATE" = "OK" ]; echo $?)" "got: $CSTATE"

# --- outbox command round trip (per-UID target) ------------------------------
# Insert a PENDING command; the worker publishes it, the client verifies the
# signature and responds, and the worker marks the row ACKED.
QID1=$(python3 -c 'import uuid;print(uuid.uuid4())')
dbq "insert into COMMANDS (SID,TARGET,LUMY,ACTION,QID,STATUS,CREATED) values ($SID,'$UID_TEST','core','queryall','$QID1','PENDING',now());"
ACK1=1
for i in $(seq 1 60); do
    st=$(dbq "select STATUS from COMMANDS where QID='$QID1';")
    [ "$st" = "ACKED" ] && { ACK1=0; break; }
    sleep 0.5
done
check "per-UID outbox command was published and ACKED" "$ACK1" "final status: $(dbq "select STATUS from COMMANDS where QID='$QID1';")"

# --- OS-targeted command (lowercased topic) ----------------------------------
QID2=$(python3 -c 'import uuid;print(uuid.uuid4())')
dbq "insert into COMMANDS (SID,TARGET,LUMY,ACTION,QID,STATUS,CREATED) values ($SID,'os/Linux','core','queryos','$QID2','PENDING',now());"
ACK2=1
for i in $(seq 1 60); do
    st=$(dbq "select STATUS from COMMANDS where QID='$QID2';")
    [ "$st" = "ACKED" ] && { ACK2=0; break; }
    sleep 0.5
done
check "OS-targeted command (os/Linux -> os/linux) was published and ACKED" "$ACK2" "final status: $(dbq "select STATUS from COMMANDS where QID='$QID2';")"

# --- group-targeted command ---------------------------------------------------
QID3=$(python3 -c 'import uuid;print(uuid.uuid4())')
dbq "insert into COMMANDS (SID,TARGET,LUMY,ACTION,QID,STATUS,CREATED) values ($SID,'grp/$GROUP','core','querygrp','$QID3','PENDING',now());"
ACK3=1
for i in $(seq 1 60); do
    st=$(dbq "select STATUS from COMMANDS where QID='$QID3';")
    [ "$st" = "ACKED" ] && { ACK3=0; break; }
    sleep 0.5
done
check "group-targeted command (grp/$GROUP) was published and ACKED" "$ACK3" "final status: $(dbq "select STATUS from COMMANDS where QID='$QID3';")"

# --- query / answer end to end (protocol 6.1, 7.3) -----------------------------
# Two outbox rows: a core/config row with the sensor definition, then the
# core/query row (its QID is the envelope id and data.qid). The worker
# publishes them in ID order; the client applies the definition, runs the
# sensor, and answers with data.qid; the worker ACKs both and stores the
# per-sensor result in QUERYRESULTS.
QCFG=$(python3 -c 'import uuid;print(uuid.uuid4())')
QQRY=$(python3 -c 'import uuid;print(uuid.uuid4())')
CFGDATA='{"sensors":[{"sid":7,"name":"probe","lstype":"shell","lscript":"echo probe-7"}]}'
QRYDATA="{\"qid\":\"$QQRY\",\"sensors\":[{\"sid\":7}]}"
dbq "insert into COMMANDS (SID,TARGET,LUMY,ACTION,DATA,QID,STATUS,CREATED) values ($SID,'$UID_TEST','core','config','$CFGDATA','$QCFG','PENDING',now());"
dbq "insert into COMMANDS (SID,TARGET,LUMY,ACTION,DATA,QID,STATUS,CREATED) values ($SID,'$UID_TEST','core','query','$QRYDATA','$QQRY','PENDING',now());"
ACKC=1
ACKQ=1
for i in $(seq 1 60); do
    stc=$(dbq "select STATUS from COMMANDS where QID='$QCFG';")
    [ "$stc" = "ACKED" ] && { ACKC=0; }
    stq=$(dbq "select STATUS from COMMANDS where QID='$QQRY';")
    [ "$stq" = "ACKED" ] && { ACKQ=0; }
    [ "$ACKC" -eq 0 ] && [ "$ACKQ" -eq 0 ] && break
    sleep 0.5
done
check "query config command (sensor definitions) was published and ACKED" "$ACKC" "final status: $(dbq "select STATUS from COMMANDS where QID='$QCFG';")"
check "query command was ACKED via the answer's data.qid" "$ACKQ" "final status: $(dbq "select STATUS from COMMANDS where QID='$QQRY';")"
# The mysql client escapes newlines in batch output, so the trailing newline
# of the sensor output is stripped in SQL before comparing.
qout=$(dbq "select concat(STATUS,'|',ifnull(replace(OUTPUT,char(10),''),''),'|',ifnull(ERR,'')) from QUERYRESULTS where QID='$QQRY';")
check "answer result stored in QUERYRESULTS (sensor 7 output)" $([ "$qout" = "OK|probe-7|" ]; echo $?) "got: $qout"

# --- query deadline: no answer by the deadline => TIMEDOUT (protocol 7.3) -----
# The worker runs with cmd_timeout=5s. Target 99 has no client, so the query
# gets no answer and must be marked TIMEDOUT (and not republished).
QTMO=$(python3 -c 'import uuid;print(uuid.uuid4())')
dbq "insert into COMMANDS (SID,TARGET,LUMY,ACTION,DATA,QID,STATUS,CREATED) values ($SID,'99','core','query','{\"qid\":\"$QTMO\",\"sensors\":[{\"sid\":7}]}','$QTMO','PENDING',now());"
TMO=1
for i in $(seq 1 40); do
    st=$(dbq "select STATUS from COMMANDS where QID='$QTMO';")
    [ "$st" = "TIMEDOUT" ] && { TMO=0; break; }
    sleep 0.5
done
check "unanswered query was marked TIMEDOUT at its deadline" "$TMO" "final status: $(dbq "select STATUS from COMMANDS where QID='$QTMO';")"

# --- password_file maintenance (on a spare UID, not the running client) ------
PERL5LIB="$PERL_LIBS" perl -e '
    use strict; use warnings;
    use Luminum::MQTT;
    my ($uid,$secret,$file,$pid) = @ARGV;
    Luminum::MQTT::on_register($uid,$secret,passwd_file=>$file,pid_file=>$pid);
' 43 "sparesecret43" "$SCRATCH/passwd" "$SCRATCH/mosquitto.pid"
check "on_register added the client to the password_file" "$(grep -q '^43:' "$SCRATCH/passwd"; echo $?)"

PERL5LIB="$PERL_LIBS" perl -e '
    use strict; use warnings;
    use Luminum::MQTT;
    my ($uid,$file,$pid) = @ARGV;
    Luminum::MQTT::on_deactivate($uid,passwd_file=>$file,pid_file=>$pid);
' 43 "$SCRATCH/passwd" "$SCRATCH/mosquitto.pid"
check "on_deactivate removed the client from the password_file" "$(! grep -q '^43:' "$SCRATCH/passwd"; echo $?)"

# --- LWT: kill the client, expect STATUS.CSTATE=OFFLINE ----------------------
kill -9 "$CLIENT_PID" 2>/dev/null
CLIENT_PID=""
LWT_OK=1
for i in $(seq 1 40); do
    cstate=$(dbq "select CSTATE from STATUS where ID=$UID_TEST;")
    [ "$cstate" = "OFFLINE" ] && { LWT_OK=0; break; }
    sleep 0.5
done
check "offline LWT flipped STATUS.CSTATE to OFFLINE" "$LWT_OK" "final cstate: $(dbq "select CSTATE from STATUS where ID=$UID_TEST;")"

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    echo "Artifacts left in $SCRATCH for inspection (worker.log, mosquitto.log, client.log)"
    exit 1
fi
echo "All checks passed."
exit 0
