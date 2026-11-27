#!/usr/bin/env bash
# P2P seed path (docs/p2p.md Phase 3) end-to-end test: runs the real
# Luminum::MQTT worker (with the seed-path push material) against a scratch
# Mosquitto broker and scratch CLIENTS/CONTENT databases, with the Rust
# client as the endpoint. Verifies end to end:
#   - a PENDING deploy command mints a server-only grant (uid 0, port
#     10704), is published in the grant form, and is ACKED by the client
#   - the worker's forked push child dials the client's 10704 inbound data
#     channel over mutual TLS (the client presents the CA-issued client
#     certificate CN = luminum-client-{UID}; the server presents the CA's
#     leaf, which the client verifies chain-to-root against the stored
#     anchor - docs/p2p.md 4.4)
#   - the grant is presented verbatim, the client stages the files under
#     Downloads/{token}/, verifies size + SHA-256, and installs them under
#     Packages/{pkgid}/{path}
#   - the terminal p2p_fetch_ok report (on the resp topic) consumes the
#     P2PTOKENS row and upserts the PKGHOLDERS rows with SOURCE 'server'
#   - the per-file manifest row is recorded in the client's config/p2p.db
#   - the per-token staging tree is removed after the install
#
# Unlike tests/mqtt_worker_test.sh (which runs the worker without TLS
# material, so deploys publish but never push), this test exercises the
# full seed path: mint -> publish -> push -> install -> report -> fold.
#
# Usage: bash tests/p2p_seed_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
CLIENT_BIN="$REPO/client/linux/target/debug/LuminumClient"
[ -x "$CLIENT_BIN" ] || { echo "SKIP - client binary not built at $CLIENT_BIN"; exit 0; }
[ -x "$(command -v openssl)" ]        || { echo "SKIP - openssl not available"; exit 0; }
[ -x "$(command -v mosquitto)" ]      || { echo "SKIP - mosquitto not available"; exit 0; }
[ -x "$(command -v mosquitto_passwd)" ] || { echo "SKIP - mosquitto_passwd not available"; exit 0; }
[ -x "$(command -v mysql)" ]          || { echo "SKIP - mysql client not available"; exit 0; }
[ -x "$(command -v python3)" ]        || { echo "SKIP - python3 not available"; exit 0; }
[ -S /tmp/mysqld.sock ]               || { echo "SKIP - MariaDB not running at /tmp/mysqld.sock"; exit 0; }
# Luminum::MQTT + Luminum::P2P live in the repo; the broker's non-core
# modules (Crypt::Perl::Ed25519, Net::MQTT::Simple, IO::Socket::SSL,
# DBD::mysql) come from the ambient PERL5LIB.
PERL_LIBS="$REPO/server/lib${PERL5LIB:+:$PERL5LIB}"
PERL5LIB="$PERL_LIBS" perl -e \
    'use Crypt::Perl::Ed25519::PrivateKey; use Crypt::Perl::Ed25519::PublicKey;
     use DBI; use DBD::mysql; use Net::MQTT::Simple::SSL; use IO::Socket::SSL;
     use Luminum::MQTT; use Luminum::P2P;' 2>/dev/null \
    || { echo "SKIP - Perl dependencies for the P2P seed path are missing"; exit 0; }

PORT=18886
SID=1
UID_TEST=42
CLIENT_SECRET="p2ptestsecret"
SERVER_USER="luminum-server"
SERVER_SECRET="serversecret123"
DBSOCK=/tmp/mysqld.sock
DBNAME="LUMP2PSEED_$$"
CONTENT_DB="CONTENT"
PKGID=7

SCRATCH="$HOME/.lump2p-seed-test.$$"
CERTDIR="$SCRATCH/certs"
HOME_TEST="$SCRATCH/home"
CONTENT_ROOT="$SCRATCH/content"
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
    mysql --socket="$DBSOCK" -u root -e "drop database if exists \`$DBNAME\`; drop database if exists \`$CONTENT_DB\`;" 2>/dev/null
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
cdbq() {
    mysql --socket="$DBSOCK" -u root -N -e "$1" "$CONTENT_DB" 2>/dev/null
}

# --- TLS certificates ----------------------------------------------------------
# The production generate-mode layout (server/setup.pl): a dedicated
# Luminum CA (luminum-ca.crt/.key) issues the server leaf
# (server.crt/server.key). Both pairs sit in the same directory so
# Luminum::Cert::ca_material() finds the CA next to the server certificate
# (the push child verifies the client certificate against it). The client
# stores the CA as its anchor (config/server.crt, as mkprovision.pl does)
# and verifies the leaf Mosquitto and the push child present
# chain-to-root (docs/p2p.md 4.4).
mkdir -p "$CERTDIR" || exit 1
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout "$CERTDIR/luminum-ca.key" -out "$CERTDIR/luminum-ca.crt" \
    -subj "/CN=Luminum Test CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
openssl req -newkey rsa:2048 -nodes \
    -keyout "$CERTDIR/server.key" -out "$CERTDIR/server.csr" \
    -subj "/CN=127.0.0.1" 2>/dev/null
openssl x509 -req -in "$CERTDIR/server.csr" \
    -CA "$CERTDIR/luminum-ca.crt" -CAkey "$CERTDIR/luminum-ca.key" \
    -set_serial 0x0200 -days 30 \
    -extfile <(printf "basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=IP:127.0.0.1\n") \
    -out "$CERTDIR/server.crt" 2>/dev/null
[ -s "$CERTDIR/server.crt" ] || { echo "SKIP - could not generate the TLS certificates"; exit 0; }

# --- server Ed25519 signing key (the worker signs commands and grants) --------
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

# --- client Ed25519 signing keypair (pre-seeded into the config DB) ------------
# The client would generate one on first start, but the worker verifies the
# client's p2pfetch envelopes against CLIENTS.AUTH.PUBKEY, so the test
# generates the keypair and seeds both sides.
openssl genpkey -algorithm ed25519 -out "$CERTDIR/cl.key" 2>/dev/null
openssl pkey -in "$CERTDIR/cl.key" -outform DER 2>/dev/null | tail -c 32 > "$CERTDIR/cl.seed"
[ "$(stat -c %s "$CERTDIR/cl.seed")" = "32" ] || { echo "SKIP - could not derive the client signing seed"; exit 0; }
CLPPRV_B64=$(base64 -w0 "$CERTDIR/cl.seed")
CLPPUB_B64=$(PERL5LIB="$PERL_LIBS" perl -e '
    use Crypt::Perl::Ed25519::PrivateKey; use MIME::Base64;
    open(my $sf, "<", $ARGV[0]) or die "seed: $!"; binmode($sf); read($sf, my $seed, 32); close($sf);
    my $priv = Crypt::Perl::Ed25519::PrivateKey->new($seed);
    print encode_base64($priv->get_public_key()->get_public(), "");
' "$CERTDIR/cl.seed")
# AUTH.PUBKEY stores the base64 SPKI/DER (the broker's getpubkey() decodes
# it); the fingerprint is the SHA-256 of the SPKI/DER (protocol 3.1).
CLPUB_SPKI_B64=$(PERL5LIB="$PERL_LIBS" perl -e '
    use MIME::Base64;
    my $raw = decode_base64($ARGV[0]);
    print encode_base64(pack("H*", "302a300506032b6570032100") . $raw, "");
' "$CLPPUB_B64")
CLFPNT=$(PERL5LIB="$PERL_LIBS" perl -e '
    use Digest::SHA qw(sha256_hex); use MIME::Base64;
    my $raw = decode_base64($ARGV[0]);
    print sha256_hex(pack("H*", "302a300506032b6570032100") . $raw);
' "$CLPPUB_B64")

# --- client TLS keypair + CA-issued certificate (Phase 2 material) -------------
# P-256 key (PKCS#8, as the client loads it) + a CSR the test signs the way
# the broker does (x509 -req with the CN override): CN = luminum-client-42.
mkdir -p "$HOME_TEST/config"
openssl genpkey -algorithm ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -out "$HOME_TEST/config/client.key" 2>/dev/null
chmod 600 "$HOME_TEST/config/client.key"
openssl req -new -key "$HOME_TEST/config/client.key" \
    -subj "/CN=luminum-client-pending" -out "$CERTDIR/cl.csr" 2>/dev/null
openssl x509 -req -in "$CERTDIR/cl.csr" -CA "$CERTDIR/luminum-ca.crt" -CAkey "$CERTDIR/luminum-ca.key" \
    -set_serial 0x0100 -days 365 -subj "/CN=luminum-client-$UID_TEST" \
    -out "$HOME_TEST/config/client.crt" 2>/dev/null
[ -s "$HOME_TEST/config/client.crt" ] || { echo "SKIP - could not issue the client TLS certificate"; exit 0; }

# --- scratch MySQL databases -----------------------------------------------------
# CLIENTS: the per-test name (AUTH, STATUS, COMMANDS, GROUPS, CONFIG); the
# worker's _ensure_schema adds P2PTOKENS and P2PTRANSFERS. CONTENT: the
# worker hardcodes the name (the file repository catalog); the test creates
# FILES and PKGFILES, the worker's _ensure_content_schema adds PKGHOLDERS.
mysql --socket="$DBSOCK" -u root <<SQL
create database \`$DBNAME\` default character set utf8mb4 collate utf8mb4_general_ci;
create database if not exists \`$CONTENT_DB\` default character set utf8mb4 collate utf8mb4_general_ci;
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
create table CONFIG (
  CKEY tinytext not null,
  CVAL tinytext not null
) engine=InnoDB default charset=utf8mb4;
insert into CONFIG (CKEY,CVAL) values ('MISSINGAFTER','90');
use \`$CONTENT_DB\`;
create table if not exists FILES (
  ID int(20) not null auto_increment,
  SHA256 char(64) not null,
  SIZE bigint(20) not null,
  NAME tinytext not null,
  VIA tinytext not null,
  STAGED datetime not null,
  primary key (ID),
  unique key UQ_FILES_SHA (SHA256)
) engine=InnoDB default charset=utf8mb4;
create table if not exists PKGFILES (
  ID int(20) not null auto_increment,
  PKGID int(20) not null,
  OS tinytext not null,
  FILEID int(20) not null,
  PATH tinytext not null,
  primary key (ID),
  key IDX_PKGFILES_PKG (PKGID),
  key IDX_PKGFILES_FILE (FILEID)
) engine=InnoDB default charset=utf8mb4;
SQL
[ $? -eq 0 ] || { echo "SKIP - could not create the scratch databases"; exit 0; }

# --- package content: two files attached to package $PKGID for Linux ----------
mkdir -p "$CONTENT_ROOT/files"
printf 'luminum seed path test file one\n' > "$SCRATCH/file1.bin"
printf 'luminum seed path test file two, a bit longer so the install path is nested\n' > "$SCRATCH/file2.bin"
SHA1=$(sha256sum "$SCRATCH/file1.bin" | cut -d' ' -f1)
SHA2=$(sha256sum "$SCRATCH/file2.bin" | cut -d' ' -f1)
SIZE1=$(stat -c %s "$SCRATCH/file1.bin")
SIZE2=$(stat -c %s "$SCRATCH/file2.bin")
mkdir -p "$CONTENT_ROOT/files/${SHA1:0:2}/${SHA1:2:2}" "$CONTENT_ROOT/files/${SHA2:0:2}/${SHA2:2:2}"
cp "$SCRATCH/file1.bin" "$CONTENT_ROOT/files/${SHA1:0:2}/${SHA1:2:2}/$SHA1"
cp "$SCRATCH/file2.bin" "$CONTENT_ROOT/files/${SHA2:0:2}/${SHA2:2:2}/$SHA2"
mysql --socket="$DBSOCK" -u root "$CONTENT_DB" <<SQL
insert into FILES (SHA256,SIZE,NAME,VIA,STAGED) values ('$SHA1',$SIZE1,'file1','drop',now()),('$SHA2',$SIZE2,'file2','drop',now());
insert into PKGFILES (PKGID,OS,FILEID,PATH) values ($PKGID,'Linux',1,'bin/file1'),($PKGID,'Linux',2,'lib/nested/file2');
SQL
[ $? -eq 0 ] || { echo "SKIP - could not seed the package files"; exit 0; }

# Seed the registered client (UID 42). MQTTSECRET stores the SHA-256 hash
# (as the broker does); the client and mosquitto use the raw secret.
SECHASH=$(printf '%s' "$CLIENT_SECRET" | sha256sum | cut -d' ' -f1)
dbq "insert into AUTH (ID,NAME,FINGERPRINT,PUBKEY,MQTTSECRET) values ($UID_TEST,'seed-test','$CLFPNT','$CLPUB_SPKI_B64','$SECHASH');"
dbq "insert into STATUS (ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,REGDATE,LASTSEEN) values ($UID_TEST,'seed-sentinel','127.0.0.1','Linux','6.1','0.0.1','OK',now(),now());"

# --- ACL file: generated from the DB by regen_acl ------------------------------
PERL5LIB="$PERL_LIBS" perl -e '
    use strict; use warnings;
    use DBI; use Luminum::MQTT;
    my ($db,$sid,$user,$acl,$pid,$sock) = @ARGV;
    my $dbh = DBI->connect("DBI:mysql:$db","root","", {mysql_socket=>$sock, PrintError=>0, RaiseError=>0}) or die "db: ".DBI->errstr;
    Luminum::MQTT::regen_acl($dbh, sid=>$sid, server_user=>$user, acl_file=>$acl, pid_file=>$pid);
    $dbh->disconnect();
' "$DBNAME" "$SID" "$SERVER_USER" "$SCRATCH/acl" "$SCRATCH/mosquitto.pid" "$DBSOCK"
check "regen_acl generated the ACL file" $([ -s "$SCRATCH/acl" ]; echo $?)

# --- Mosquitto password_file + config -------------------------------------------
mosquitto_passwd -b -c "$SCRATCH/passwd" "$UID_TEST" "$CLIENT_SECRET"
mosquitto_passwd -b "$SCRATCH/passwd" "$SERVER_USER" "$SERVER_SECRET"

cat > "$SCRATCH/mosquitto.conf" <<EOF
listener $PORT 127.0.0.1
cafile $CERTDIR/luminum-ca.crt
certfile $CERTDIR/server.crt
keyfile $CERTDIR/server.key
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

# --- start Mosquitto --------------------------------------------------------------
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

# --- client home + pre-seeded config DB -------------------------------------------
# UID/SID/MQTT* are pre-seeded so the client skips registration and goes
# straight to the MQTT control channel. SRVPUB is the worker's signing key
# (the client verifies the grant and the commands against it). CLPPRV/
# CLPPUB/FPNT are the pre-generated client signing keypair (the worker
# verifies the client's p2pfetch envelopes against AUTH.PUBKEY).
# config/server.crt is the anchor (the CA that issued the certificate the
# push presents); config/client.crt + client.key are the CA-issued client
# certificate.
mkdir -p "$HOME_TEST/config"
cp "$CERTDIR/luminum-ca.crt" "$HOME_TEST/config/server.crt"
python3 - "$HOME_TEST" "$PORT" "$SRVPUB_B64" "$CLPPRV_B64" "$CLPPUB_B64" "$CLFPNT" <<'EOF'
import sqlite3, sys
home, port, srvpub, clpprv, clppub, fpnt = sys.argv[1:7]
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
for k, v in [
    ("UID", "42"), ("SID", "1"),
    ("MQTTSECRET", "p2ptestsecret"), ("MQTTHOST", "127.0.0.1"), ("MQTTPORT", port),
    ("SHOST", "127.0.0.1"), ("SPORT", "18887"),
    ("SRVPUB", srvpub),
    ("CLPPRV", clpprv), ("CLPPUB", clppub), ("FPNT", fpnt),
]:
    conn.execute("insert into CONFIG (KEY,VALUE) values (?,?)", (k, v))
conn.commit()
EOF
chmod 600 "$HOME_TEST/config/client.conf.db"

# --- worker driver (runs Luminum::MQTT::worker with the seed-path push) --------
# depl_timeout is 60s (vs the 3600s production default) so a wedged deploy
# cannot hold the test open; the transfer itself takes seconds.
cat > "$SCRATCH/worker.pl" <<'EOF'
use strict; use warnings;
$| = 1;   # autoflush: the forked push child inherits this, and the parent
          # is SIGKILLed on cleanup (block-buffered log lines would be lost)
use Luminum::MQTT;
my ($seedfile, $sid, $host, $port, $ca, $user, $secret, $dbname, $dbsock, $cmdtimeout, $depltimeout, $sysdb, $passwdfile, $pidfile, $sslcert, $sslprvkey, $serverip, $contentroot) = @ARGV;
open(my $sf, "<", $seedfile) or die "seed: $!"; binmode($sf); read($sf, my $seed, 32); close($sf);
Luminum::MQTT::worker(
    sid => $sid, host => $host, port => $port, ca => $ca,
    user => $user, secret => $secret, seed => $seed,
    dbname => $dbname, dbuser => "root", dbpass => "", dbsock => $dbsock,
    sysdb_name => $sysdb,
    poll_secs => 1,
    cmd_timeout => $cmdtimeout, depl_timeout => $depltimeout,
    passwd_file => $passwdfile, pid_file => $pidfile,
    sslcert => $sslcert, sslprvkey => $sslprvkey, server_ip => $serverip,
    content_root => $contentroot,
    log => sub { print "[worker] $_[0]\n"; },
);
EOF

PERL5LIB="$PERL_LIBS" perl "$SCRATCH/worker.pl" \
    "$CERTDIR/srv.seed" "$SID" 127.0.0.1 "$PORT" "$CERTDIR/luminum-ca.crt" \
    "$SERVER_USER" "$SERVER_SECRET" "$DBNAME" "$DBSOCK" 30 60 "$DBNAME" \
    "$SCRATCH/passwd" "$SCRATCH/mosquitto.pid" \
    "$CERTDIR/server.crt" "$CERTDIR/server.key" "127.0.0.1" "$CONTENT_ROOT" \
    > "$SCRATCH/worker.log" 2>&1 &
WORKER_PID=$!
sleep 1
check "worker process is alive after startup" "$(kill -0 "$WORKER_PID" 2>/dev/null; echo $?)" "see $SCRATCH/worker.log"

# --- start the client ---------------------------------------------------------------
LUMINUM_HOME="$HOME_TEST" LUMINUM_CHECKIN_SECS=2 "$CLIENT_BIN" > "$SCRATCH/client.log" 2>&1 &
CLIENT_PID=$!
sleep 1
check "client process is alive after startup" "$(kill -0 "$CLIENT_PID" 2>/dev/null; echo $?)" "see $SCRATCH/client.log"

# --- check-in: the worker learns the client's address (the push target) ---------
HOSTNAME_OK=1
for i in $(seq 1 40); do
    hn=$(dbq "select HOSTNAME from STATUS where ID=$UID_TEST;")
    [ -n "$hn" ] && [ "$hn" != "seed-sentinel" ] && { HOSTNAME_OK=0; break; }
    sleep 0.5
done
check "check-in updated STATUS.HOSTNAME (no longer sentinel)" "$HOSTNAME_OK" "see $SCRATCH/worker.log"
check "check-in recorded the client's IPv4 (the push target)" \
    "$([ -n "$(dbq "select IPV4 from STATUS where ID=$UID_TEST;")" ]; echo $?)" \
    "ipv4: $(dbq "select IPV4 from STATUS where ID=$UID_TEST;")"

# --- deploy: the seed path end to end ------------------------------------------------
# A PENDING deploy for the single target: the worker mints the server-only
# grant, publishes the command in the grant form, and forks the push child
# that serves the files on 10704. The client installs them and reports
# p2p_fetch_ok, which the worker folds into the token and holder tables.
QID=$(python3 -c 'import uuid;print(uuid.uuid4())')
dbq "insert into COMMANDS (SID,TARGET,LUMY,ACTION,DATA,QID,STATUS,CREATED) values ($SID,'$UID_TEST','core','deploy','{\"pkgid\":$PKGID}','$QID','PENDING',now());"
ACK=1
for i in $(seq 1 90); do
    st=$(dbq "select STATUS from COMMANDS where QID='$QID';")
    [ "$st" = "ACKED" ] && { ACK=0; break; }
    sleep 0.5
done
check "deploy command was published in the grant form and ACKED" "$ACK" "final status: $(dbq "select STATUS from COMMANDS where QID='$QID';") see $SCRATCH/worker.log"

# The grant was minted for the target with the seed-form source list.
TOK=$(dbq "select TOKEN from P2PTOKENS where REQUID=$UID_TEST and PKGID=$PKGID order by EXPIRES desc limit 1;")
[ -n "$TOK" ] || TOK=$(dbq "select TOKEN from P2PTOKENS limit 1;")
check "a P2PTOKENS grant row was minted for the target" "$([ -n "$TOK" ]; echo $?)" "rows: $(dbq 'select count(*) from P2PTOKENS;')"
check "the grant carries the seed-form source list (uid 0, port 10704)" \
    "$(dbq "select SOURCES from P2PTOKENS where TOKEN='$TOK';" | grep -q '10704'; echo $?)" \
    "sources: $(dbq "select SOURCES from P2PTOKENS where TOKEN='$TOK';")"

# The files land under Packages/{pkgid}/{path} with the right content. The
# command is ACKed as soon as it is received, but the push races the command
# delivery, so poll for the install (the transfer itself takes seconds).
F1="$HOME_TEST/Packages/$PKGID/bin/file1"
F2="$HOME_TEST/Packages/$PKGID/lib/nested/file2"
GOT1=""; GOT2=""
for i in $(seq 1 60); do
    GOT1=$(sha256sum "$F1" 2>/dev/null | cut -d' ' -f1)
    GOT2=$(sha256sum "$F2" 2>/dev/null | cut -d' ' -f1)
    { [ "$GOT1" = "$SHA1" ] && [ "$GOT2" = "$SHA2" ]; } && break
    sleep 0.5
done
check "file 1 installed at Packages/$PKGID/bin/file1" $([ "$GOT1" = "$SHA1" ]; echo $?) "got: ${GOT1:-missing}"
check "file 2 installed at Packages/$PKGID/lib/nested/file2" $([ "$GOT2" = "$SHA2" ]; echo $?) "got: ${GOT2:-missing}"

# The terminal report folded: the token is consumed, the holders are
# upserted with SOURCE 'server'.
USED_OK=1
for i in $(seq 1 60); do
    # mysql batch mode prints the literal string NULL for a NULL column.
    used=$(dbq "select USED from P2PTOKENS where TOKEN='$TOK';")
    [ -n "$used" ] && [ "$used" != "NULL" ] && { USED_OK=0; break; }
    sleep 0.5
done
check "p2p_fetch_ok consumed the grant token" "$USED_OK" "used: $(dbq "select USED from P2PTOKENS where TOKEN='$TOK';")"
H1=$(cdbq "select SOURCE from PKGHOLDERS where FILEID=1 and UID=$UID_TEST;")
H2=$(cdbq "select SOURCE from PKGHOLDERS where FILEID=2 and UID=$UID_TEST;")
check "PKGHOLDERS: file 1 held with SOURCE 'server'" $([ "$H1" = "server" ]; echo $?) "source: ${H1:-none}"
check "PKGHOLDERS: file 2 held with SOURCE 'server'" $([ "$H2" = "server" ]; echo $?) "source: ${H2:-none}"

# The client recorded the manifest rows (config/p2p.db).
M1=$(python3 -c "
import sqlite3, sys
conn = sqlite3.connect('$HOME_TEST/config/p2p.db')
row = conn.execute('select PKGID, OS, PATH, SIZE, SHA256 from MANIFEST where FILEID = 1').fetchone()
print('|'.join(str(x) for x in row) if row else '')
" 2>/dev/null)
check "manifest: file 1 recorded" $([ "$M1" = "$PKGID|Linux|bin/file1|$SIZE1|$SHA1" ]; echo $?) "got: ${M1:-none}"
M2=$(python3 -c "
import sqlite3, sys
conn = sqlite3.connect('$HOME_TEST/config/p2p.db')
row = conn.execute('select PKGID, OS, PATH, SIZE, SHA256 from MANIFEST where FILEID = 2').fetchone()
print('|'.join(str(x) for x in row) if row else '')
" 2>/dev/null)
check "manifest: file 2 recorded" $([ "$M2" = "$PKGID|Linux|lib/nested/file2|$SIZE2|$SHA2" ]; echo $?) "got: ${M2:-none}"

# The per-token staging tree is removed after the install.
check "staging tree removed after the install" \
    "$([ ! -d "$HOME_TEST/Downloads/$TOK" ]; echo $?)" \
    "left: $(ls "$HOME_TEST/Downloads" 2>/dev/null | tr '\n' ' ')"

# The push completed on the server side (the forked child logged it).
check "worker log: the push completed" \
    "$(grep -q "push to .* completed" "$SCRATCH/worker.log"; echo $?)" "see $SCRATCH/worker.log"
check "worker log: the fetch_ok report was folded" \
    "$(grep -q "completed grant $TOK" "$SCRATCH/worker.log"; echo $?)" "see $SCRATCH/worker.log"

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    echo "Artifacts left in $SCRATCH for inspection (worker.log, mosquitto.log, client.log)"
    exit 1
fi
echo "All checks passed."
exit 0
