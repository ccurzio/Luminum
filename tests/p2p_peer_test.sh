#!/usr/bin/env bash
# P2P peer channel (docs/p2p.md Phase 4) end-to-end test.
#
# Two real Luminum clients cannot run on one host (both bind the fixed
# 10704/10464 ports on the local IP), so the test runs one real client in a
# role and tests/p2p_peer_helper.pl in the other, over the 10464 mutual-TLS
# channel (protocol 8.4):
#
#   Phase 1 - the SERVING side (real client A as source):
#     - a peer (the helper, presenting the CA-issued certificate
#       CN = luminum-client-42) dials A's 10464 and presents a server-signed
#       grant; A runs the source-side checklist (docs/p2p.md 5.3) and serves
#       the grant's files from its local Packages/ tree
#     - the served files verify by size + SHA-256
#     - source-side rejections: a tampered hash (FILE_MISMATCH), a grant
#       replay (GRANT_USED), and a channel-identity mismatch (UID_MISMATCH)
#     - the check-in p2p flag sets STATUS.P2P, and the one-shot p2p/have
#       startup sync folds A's manifest into PKGHOLDERS (SOURCE 'local')
#
#   Phase 2 - the FETCHER (real client B as requester):
#     - a server-signed deploy command whose grant carries a peer source
#       (uid 41, the helper acting as the source) is published directly to
#       B's cmd topic (bypassing the worker outbox, which would re-mint a
#       server-only grant)
#     - B's fetcher dials the source's 10464, presents the grant, receives
#       and verifies the files, installs them under Packages/, records the
#       manifest, and reports p2p_fetch_ok (srcuid 41)
#     - the worker folds the report: the token is consumed and the holders
#       are upserted with SOURCE '41' (the serving peer's UID)
#
# Usage: bash tests/p2p_peer_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
CLIENT_BIN="$REPO/client/linux/target/debug/LuminumClient"
[ -x "$CLIENT_BIN" ] || { echo "SKIP - client binary not built at $CLIENT_BIN"; exit 0; }
[ -x "$(command -v openssl)" ]        || { echo "SKIP - openssl not available"; exit 0; }
[ -x "$(command -v mosquitto)" ]      || { echo "SKIP - mosquitto not available"; exit 0; }
[ -x "$(command -v mosquitto_passwd)" ] || { echo "SKIP - mosquitto_passwd not available"; exit 0; }
[ -x "$(command -v mosquitto_pub)" ]  || { echo "SKIP - mosquitto_pub not available"; exit 0; }
[ -x "$(command -v mysql)" ]          || { echo "SKIP - mysql client not available"; exit 0; }
[ -x "$(command -v python3)" ]        || { echo "SKIP - python3 not available"; exit 0; }
[ -S /tmp/mysqld.sock ]               || { echo "SKIP - MariaDB not running at /tmp/mysqld.sock"; exit 0; }
PERL_LIBS="$REPO/server/lib${PERL5LIB:+:$PERL5LIB}"
PERL5LIB="$PERL_LIBS" perl -e \
    'use Crypt::Perl::Ed25519::PrivateKey; use Crypt::Perl::Ed25519::PublicKey;
     use DBI; use DBD::mysql; use Net::MQTT::Simple::SSL; use IO::Socket::SSL;
     use Net::SSLeay; use Luminum::MQTT; use Luminum::P2P;' 2>/dev/null \
    || { echo "SKIP - Perl dependencies for the P2P peer channel are missing"; exit 0; }

PORT=18887
SID=1
UID_A=41
UID_B=42
SECRET_A="peersecret-a"
SECRET_B="peersecret-b"
SERVER_USER="luminum-server"
SERVER_SECRET="serversecret123"
DBSOCK=/tmp/mysqld.sock
DBNAME="LUMPP2P_$$"
CONTENT_DB="CONTENT"
PKGID=7
# The client binds its 10704/10464 listeners on the host's primary non-
# loopback IP (local_ip_address::local_ip); the helper dials A there.
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -n "$LOCAL_IP" ] || { echo "SKIP - cannot determine the local IP"; exit 0; }

SCRATCH="$HOME/.lump2p-peer-test.$$"
CERTDIR="$SCRATCH/certs"
HOME_A="$SCRATCH/home_a"
HOME_B="$SCRATCH/home_b"
SRCFILES="$SCRATCH/srcfiles"
FAILURES=0
MOSQ_PID=""; CLIENT_PID=""; WORKER_PID=""; SOURCE_PID=""

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
    [ -n "$SOURCE_PID" ] && kill -9 "$SOURCE_PID" 2>/dev/null
    [ -n "$WORKER_PID" ] && kill "$WORKER_PID" 2>/dev/null
    [ -n "$MOSQ_PID" ] && kill "$MOSQ_PID" 2>/dev/null
    mysql --socket="$DBSOCK" -u root -e "drop database if exists \`$DBNAME\`; drop database if exists \`$CONTENT_DB\`;" 2>/dev/null
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
# A dedicated Luminum CA issues the server leaf and the two client
# certificates (CN = luminum-client-41 for A, luminum-client-42 for B). The
# channel identity on 10464 is the certificate CN (docs/p2p.md 4.2).
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

# --- server Ed25519 signing key ------------------------------------------------
openssl genpkey -algorithm ed25519 -out "$CERTDIR/srv.key" 2>/dev/null
openssl pkey -in "$CERTDIR/srv.key" -outform DER 2>/dev/null | tail -c 32 > "$CERTDIR/srv.seed"
[ "$(stat -c %s "$CERTDIR/srv.seed")" = "32" ] || { echo "SKIP - could not derive the server signing seed"; exit 0; }
# SRVPUB: the raw 32-byte public key (what the client stores) and its base64.
SRVPUB_B64=$(PERL5LIB="$PERL_LIBS" perl -e '
    use Crypt::Perl::Ed25519::PrivateKey; use MIME::Base64;
    open(my $sf, "<", $ARGV[0]) or die "seed: $!"; binmode($sf); read($sf, my $seed, 32); close($sf);
    my $priv = Crypt::Perl::Ed25519::PrivateKey->new($seed);
    my $raw = $priv->get_public_key()->get_public();
    open(my $of, ">:raw", $ARGV[1]) or die "pub: $!"; print $of $raw; close($of);
    print encode_base64($raw, "");
' "$CERTDIR/srv.seed" "$CERTDIR/srvpub.bin")
[ -n "$SRVPUB_B64" ] || { echo "SKIP - could not derive the server public key"; exit 0; }

# --- client Ed25519 signing keypairs (pre-seeded into the config DBs) ----------
# Each client generates one on first start, but the worker verifies the
# client's p2pfetch envelopes against CLIENTS.AUTH.PUBKEY, so the test
# generates both keypairs and seeds both sides. AUTH.PUBKEY stores the base64
# SPKI/DER; the fingerprint is the SHA-256 of the SPKI/DER (protocol 3.1).
derive_pub() {
    # $1 = seed file; prints the raw 32-byte public key as base64
    PERL5LIB="$PERL_LIBS" perl -e '
        use Crypt::Perl::Ed25519::PrivateKey; use MIME::Base64;
        open(my $sf, "<", $ARGV[0]) or die "seed: $!"; binmode($sf); read($sf, my $seed, 32); close($sf);
        print encode_base64(Crypt::Perl::Ed25519::PrivateKey->new($seed)->get_public_key()->get_public(), "");
    ' "$1"
}
derive_spki() {
    # $1 = raw pub b64; prints the base64 SPKI/DER
    PERL5LIB="$PERL_LIBS" perl -e '
        use MIME::Base64;
        my $raw = decode_base64($ARGV[0]);
        print encode_base64(pack("H*", "302a300506032b6570032100") . $raw, "");
    ' "$1"
}
derive_fpnt() {
    # $1 = raw pub b64; prints the SHA-256 fingerprint of the SPKI/DER
    PERL5LIB="$PERL_LIBS" perl -e '
        use Digest::SHA qw(sha256_hex); use MIME::Base64;
        my $raw = decode_base64($ARGV[0]);
        print sha256_hex(pack("H*", "302a300506032b6570032100") . $raw);
    ' "$1"
}
# Client A
openssl genpkey -algorithm ed25519 -out "$CERTDIR/clA.key" 2>/dev/null
openssl pkey -in "$CERTDIR/clA.key" -outform DER 2>/dev/null | tail -c 32 > "$CERTDIR/clA.seed"
[ "$(stat -c %s "$CERTDIR/clA.seed")" = "32" ] || { echo "SKIP - could not derive client A signing seed"; exit 0; }
CLAPRV_B64=$(base64 -w0 "$CERTDIR/clA.seed")
CLAPUB_B64=$(derive_pub "$CERTDIR/clA.seed")
CLAPUB_SPKI_B64=$(derive_spki "$CLAPUB_B64")
CLAFPNT=$(derive_fpnt "$CLAPUB_B64")
# Client B
openssl genpkey -algorithm ed25519 -out "$CERTDIR/clB.key" 2>/dev/null
openssl pkey -in "$CERTDIR/clB.key" -outform DER 2>/dev/null | tail -c 32 > "$CERTDIR/clB.seed"
[ "$(stat -c %s "$CERTDIR/clB.seed")" = "32" ] || { echo "SKIP - could not derive client B signing seed"; exit 0; }
CLBPRV_B64=$(base64 -w0 "$CERTDIR/clB.seed")
CLBPUB_B64=$(derive_pub "$CERTDIR/clB.seed")
CLBPUB_SPKI_B64=$(derive_spki "$CLBPUB_B64")
CLBFPNT=$(derive_fpnt "$CLBPUB_B64")

# --- client TLS keypairs + CA-issued certificates -------------------------------
# P-256 key (PKCS#8, as the client loads it) + a CSR the test signs the way
# the broker does (x509 -req with the CN override): CN = luminum-client-{UID}.
issue_client_cert() {
    # $1 = home dir, $2 = UID, $3 = serial
    local HOME_DIR="$1" UID_N="$2" SERIAL="$3"
    mkdir -p "$HOME_DIR/config"
    openssl genpkey -algorithm ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -out "$HOME_DIR/config/client.key" 2>/dev/null
    chmod 600 "$HOME_DIR/config/client.key"
    openssl req -new -key "$HOME_DIR/config/client.key" \
        -subj "/CN=luminum-client-pending" -out "$CERTDIR/cl$UID_N.csr" 2>/dev/null
    openssl x509 -req -in "$CERTDIR/cl$UID_N.csr" -CA "$CERTDIR/luminum-ca.crt" -CAkey "$CERTDIR/luminum-ca.key" \
        -set_serial "$SERIAL" -days 365 -subj "/CN=luminum-client-$UID_N" \
        -out "$HOME_DIR/config/client.crt" 2>/dev/null
    [ -s "$HOME_DIR/config/client.crt" ]
}
issue_client_cert "$HOME_A" "$UID_A" 0x0100 || { echo "SKIP - could not issue client A TLS certificate"; exit 0; }
issue_client_cert "$HOME_B" "$UID_B" 0x0101 || { echo "SKIP - could not issue client B TLS certificate"; exit 0; }
cp "$CERTDIR/luminum-ca.crt" "$HOME_A/config/server.crt"
cp "$CERTDIR/luminum-ca.crt" "$HOME_B/config/server.crt"

# --- scratch MySQL databases -----------------------------------------------------
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
  P2P tinyint(1) default 0,
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
mkdir -p "$SRCFILES"
printf 'luminum peer path test file one\n' > "$SRCFILES/file1"
printf 'luminum peer path test file two, a bit longer so the install path is nested\n' > "$SRCFILES/file2"
SHA1=$(sha256sum "$SRCFILES/file1" | cut -d' ' -f1)
SHA2=$(sha256sum "$SRCFILES/file2" | cut -d' ' -f1)
SIZE1=$(stat -c %s "$SRCFILES/file1")
SIZE2=$(stat -c %s "$SRCFILES/file2")
mysql --socket="$DBSOCK" -u root "$CONTENT_DB" <<SQL
insert into FILES (SHA256,SIZE,NAME,VIA,STAGED) values ('$SHA1',$SIZE1,'file1','drop',now()),('$SHA2',$SIZE2,'file2','drop',now());
insert into PKGFILES (PKGID,OS,FILEID,PATH) values ($PKGID,'Linux',1,'bin/file1'),($PKGID,'Linux',2,'lib/nested/file2');
SQL
[ $? -eq 0 ] || { echo "SKIP - could not seed the package files"; exit 0; }

# Seed both registered clients. MQTTSECRET stores the SHA-256 hash (as the
# broker does); the client and mosquitto use the raw secret.
SECHASH_A=$(printf '%s' "$SECRET_A" | sha256sum | cut -d' ' -f1)
SECHASH_B=$(printf '%s' "$SECRET_B" | sha256sum | cut -d' ' -f1)
dbq "insert into AUTH (ID,NAME,FINGERPRINT,PUBKEY,MQTTSECRET) values ($UID_A,'peer-a','$CLAFPNT','$CLAPUB_SPKI_B64','$SECHASH_A');" 2>/dev/null
dbq "insert into AUTH (ID,NAME,FINGERPRINT,PUBKEY,MQTTSECRET) values ($UID_B,'peer-b','$CLBFPNT','$CLBPUB_SPKI_B64','$SECHASH_B');" 2>/dev/null
dbq "insert into STATUS (ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,REGDATE,LASTSEEN) values ($UID_A,'peer-a-sentinel','127.0.0.1','Linux','6.1','0.1.0','OK',now(),now());"
dbq "insert into STATUS (ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,REGDATE,LASTSEEN) values ($UID_B,'peer-b-sentinel','127.0.0.1','Linux','6.1','0.1.0','OK',now(),now());"

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
mosquitto_passwd -b -c "$SCRATCH/passwd" "$UID_A" "$SECRET_A"
mosquitto_passwd -b "$SCRATCH/passwd" "$UID_B" "$SECRET_B"
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

# --- client config DBs -------------------------------------------------------------
# UID/SID/MQTT* are pre-seeded so each client skips registration and goes
# straight to the MQTT control channel. SRVPUB is the worker's signing key;
# CLPPRV/CLPPUB/FPNT are the pre-generated client signing keypairs.
seed_config_db() {
    # $1 = home, $2 = UID, $3 = MQTT secret, $4 = CLPPRV b64, $5 = CLPPUB b64, $6 = FPNT
    python3 - "$1" "$2" "$3" "$SRVPUB_B64" "$4" "$5" "$6" <<'EOF'
import sqlite3, sys
home, uid, secret, srvpub, clpprv, clppub, fpnt = sys.argv[1:8]
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
for k, v in [
    ("UID", uid), ("SID", "1"),
    ("MQTTSECRET", secret), ("MQTTHOST", "127.0.0.1"), ("MQTTPORT", "18887"),
    ("SHOST", "127.0.0.1"), ("SPORT", "18888"),
    ("SRVPUB", srvpub),
    ("CLPPRV", clpprv), ("CLPPUB", clppub), ("FPNT", fpnt),
]:
    conn.execute("insert into CONFIG (KEY,VALUE) values (?,?)", (k, v))
conn.commit()
EOF
    chmod 600 "$1/config/client.conf.db"
}
seed_config_db "$HOME_A" "$UID_A" "$SECRET_A" "$CLAPRV_B64" "$CLAPUB_B64" "$CLAFPNT"
seed_config_db "$HOME_B" "$UID_B" "$SECRET_B" "$CLBPRV_B64" "$CLBPUB_B64" "$CLBFPNT"

# Pre-populate client A's Packages/ tree and manifest (A is the source; it
# already holds the package files). The manifest is the single source of
# truth for what A can serve (docs/p2p.md 8.1).
mkdir -p "$HOME_A/Packages/$PKGID/bin" "$HOME_A/Packages/$PKGID/lib/nested"
cp "$SRCFILES/file1" "$HOME_A/Packages/$PKGID/bin/file1"
cp "$SRCFILES/file2" "$HOME_A/Packages/$PKGID/lib/nested/file2"
python3 - "$HOME_A" "$PKGID" "$SIZE1" "$SHA1" "$SIZE2" "$SHA2" <<'EOF'
import sqlite3, sys, time
home, pkgid, s1, h1, s2, h2 = sys.argv[1:7]
conn = sqlite3.connect(home + "/config/p2p.db")
conn.execute("create table if not exists MANIFEST ( FILEID integer primary key, PKGID integer not null, OS text not null, PATH text not null, SIZE integer not null, SHA256 text not null, TS integer not null )")
ts = int(time.time())
conn.execute("insert into MANIFEST (FILEID,PKGID,OS,PATH,SIZE,SHA256,TS) values (?,?,?,?,?,?,?)", (1, int(pkgid), "Linux", "bin/file1", int(s1), h1, ts))
conn.execute("insert into MANIFEST (FILEID,PKGID,OS,PATH,SIZE,SHA256,TS) values (?,?,?,?,?,?,?)", (2, int(pkgid), "Linux", "lib/nested/file2", int(s2), h2, ts))
conn.commit()
EOF
chmod 600 "$HOME_A/config/p2p.db"

# --- worker driver (runs Luminum::MQTT::worker) ----------------------------------
cat > "$SCRATCH/worker.pl" <<'EOF'
use strict; use warnings;
$| = 1;
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
    "$CERTDIR/server.crt" "$CERTDIR/server.key" "127.0.0.1" "$SRCFILES" \
    > "$SCRATCH/worker.log" 2>&1 &
WORKER_PID=$!
sleep 1
check "worker process is alive after startup" "$(kill -0 "$WORKER_PID" 2>/dev/null; echo $?)" "see $SCRATCH/worker.log"

# --- helper config generator ------------------------------------------------------
# Writes a p2p_peer_helper.pl config JSON. $1 = output path, $2 = mode
# (requester|source), $3 = the peer's TLS cert/key home, $4 = the grant uid,
# $5 = req_uid (source mode), $6 = src_uid (source mode), $7 = ip, $8 = port,
# $9 = files JSON (with disk paths for source mode).
write_helper_cfg() {
    python3 - "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "$CERTDIR" "$UID_A" "$UID_B" <<'EOF'
import json, sys
out, mode, home, uid, req_uid, src_uid, ip, port, files_json, certdir, uida, uidb = sys.argv[1:13]
files = json.loads(files_json)
cfg = {
    "ip": ip, "port": int(port),
    "ca": certdir + "/luminum-ca.crt",
    "crt": home + "/config/client.crt",
    "key": home + "/config/client.key",
    "seed": certdir + "/srv.seed",
    "srvpub": certdir + "/srvpub.bin",
    "uid": int(uid), "req_uid": req_uid, "src_uid": src_uid,
    "pkgid": 7, "aid": "peer-" + mode,
    "sources": [
        {"uid": int(uida), "ip": ip, "port": int(port)},
        {"uid": 0, "ip": "127.0.0.1", "port": 10704},
    ],
    "files": files,
}
with open(out, "w") as f:
    json.dump(cfg, f)
EOF
}

# The grant's file list (the two package files). For the source role the
# helper also needs the on-disk path it serves from.
FILES_REQ='[{"fileid":1,"path":"bin/file1","size":'"$SIZE1"',"sha256":"'"$SHA1"'"},{"fileid":2,"path":"lib/nested/file2","size":'"$SIZE2"',"sha256":"'"$SHA2"'"}]'
FILES_SRC='[{"fileid":1,"path":"bin/file1","size":'"$SIZE1"',"sha256":"'"$SHA1"'","disk":"'"$SRCFILES"'/file1"},{"fileid":2,"path":"lib/nested/file2","size":'"$SIZE2"',"sha256":"'"$SHA2"'","disk":"'"$SRCFILES"'/file2"}]'

# ============================================================================
# Phase 1 - the SERVING side (real client A as source)
# ============================================================================
echo "=== Phase 1: serving side (client A as source) ==="
# --debug: the serving completion is a PROC-level log line (outlvl 0), only
# emitted in debug mode; the test greps for it.
LUMINUM_HOME="$HOME_A" LUMINUM_CHECKIN_SECS=2 "$CLIENT_BIN" --debug > "$SCRATCH/client_a.log" 2>&1 &
CLIENT_PID=$!
sleep 1
check "client A process is alive after startup" "$(kill -0 "$CLIENT_PID" 2>/dev/null; echo $?)" "see $SCRATCH/client_a.log"

# A binds its 10464 peer listener on the local IP; wait for it.
A_READY=1
for i in $(seq 1 40); do
    if (exec 3<>/dev/tcp/$LOCAL_IP/10464) 2>/dev/null; then
        exec 3>&- 3<&- 2>/dev/null
        A_READY=0
        break
    fi
    sleep 0.25
done
check "client A is listening on the 10464 peer channel" "$A_READY" "see $SCRATCH/client_a.log"
[ "$A_READY" -eq 0 ] || exit 1

# A's check-in reached the worker (STATUS updated, no longer the sentinel).
A_CHECKIN=1
for i in $(seq 1 40); do
    hn=$(dbq "select HOSTNAME from STATUS where ID=$UID_A;")
    [ -n "$hn" ] && [ "$hn" != "peer-a-sentinel" ] && { A_CHECKIN=0; break; }
    sleep 0.5
done
check "client A check-in reached the worker" "$A_CHECKIN" "see $SCRATCH/worker.log"

# The p2p check-in flag set STATUS.P2P (docs/p2p.md 7.4).
A_P2P=1
for i in $(seq 1 40); do
    p=$(dbq "select P2P from STATUS where ID=$UID_A;")
    [ "$p" = "1" ] && { A_P2P=0; break; }
    sleep 0.5
done
check "client A check-in set STATUS.P2P = 1" "$A_P2P" "p2p: $(dbq "select P2P from STATUS where ID=$UID_A;")"

# The one-shot p2p/have startup sync folded A's manifest into PKGHOLDERS
# (SOURCE 'local', docs/p2p.md 8.1).
A_HAVE=1
for i in $(seq 1 40); do
    h1=$(cdbq "select SOURCE from PKGHOLDERS where FILEID=1 and UID=$UID_A;")
    h2=$(cdbq "select SOURCE from PKGHOLDERS where FILEID=2 and UID=$UID_A;")
    [ "$h1" = "local" ] && [ "$h2" = "local" ] && { A_HAVE=0; break; }
    sleep 0.5
done
check "client A p2p/have sync folded into PKGHOLDERS (SOURCE 'local')" "$A_HAVE" \
    "h1: $(cdbq "select SOURCE from PKGHOLDERS where FILEID=1 and UID=$UID_A;") h2: $(cdbq "select SOURCE from PKGHOLDERS where FILEID=2 and UID=$UID_A;")"

# Happy path: the helper (presenting CN = luminum-client-42) dials A and
# receives both files under a server-signed grant.
write_helper_cfg "$SCRATCH/cfg_serve.json" requester "$HOME_B" "$UID_B" "$UID_B" "$UID_A" "$LOCAL_IP" 10464 "$FILES_REQ"
SERVE_OUT=$(PERL5LIB="$PERL_LIBS" perl "$REPO/tests/p2p_peer_helper.pl" requester "$SCRATCH/cfg_serve.json" 2>&1)
SERVE_RC=$?
check "serving: the peer received both files" "$(echo "$SERVE_OUT" | grep -q '^OK token=.*sha='"$SHA1"'.*sha='"$SHA2"'$'; echo $?)" "out: $SERVE_OUT"
check "serving: A logged the completed session" "$(grep -q 'served package .* to requester' "$SCRATCH/client_a.log"; echo $?)" "see $SCRATCH/client_a.log"

# Rejection: a tampered hash (the grant's sha256 does not match A's manifest).
# A 64-hex-digit value that is valid but wrong: long enough to pass the
# grant's well-formedness check, so the refusal is the manifest mismatch
# (FILE_MISMATCH), not a malformed grant (BAD_GRANT).
BADSHA=$(printf 'ff%.0s' $(seq 1 32))
FILES_BAD='[{"fileid":1,"path":"bin/file1","size":'"$SIZE1"',"sha256":"'"$BADSHA"'"},{"fileid":2,"path":"lib/nested/file2","size":'"$SIZE2"',"sha256":"'"$SHA2"'"}]'
write_helper_cfg "$SCRATCH/cfg_tamper.json" requester "$HOME_B" "$UID_B" "$UID_B" "$UID_A" "$LOCAL_IP" 10464 "$FILES_BAD"
TAMPER_OUT=$(PERL5LIB="$PERL_LIBS" perl "$REPO/tests/p2p_peer_helper.pl" requester "$SCRATCH/cfg_tamper.json" 2>&1)
check "serving: a tampered hash is refused (FILE_MISMATCH)" "$(echo "$TAMPER_OUT" | grep -q 'REFUSED: FILE_MISMATCH'; echo $?)" "out: $TAMPER_OUT"

# Rejection: a grant replay (the same token presented twice). The first
# presentation serves and consumes the token; the second is refused.
REPLAY_TOKEN=$(python3 -c 'import uuid;print(uuid.uuid4())')
python3 - "$SCRATCH/cfg_replay.json" "$HOME_B" "$UID_B" "$UID_A" "$LOCAL_IP" "$REPLAY_TOKEN" "$FILES_REQ" "$CERTDIR" <<'EOF'
import json, sys
out, home, uid, src_uid, ip, token, files_json, certdir = sys.argv[1:9]
base = json.loads(files_json)
cfg = {
    "ip": ip, "port": 10464,
    "ca": certdir + "/luminum-ca.crt",
    "crt": home + "/config/client.crt",
    "key": home + "/config/client.key",
    "seed": certdir + "/srv.seed",
    "srvpub": certdir + "/srvpub.bin",
    "uid": int(uid), "req_uid": uid, "src_uid": src_uid,
    "pkgid": 7, "aid": "peer-replay",
    "token": token,
    "sources": [{"uid": int(src_uid), "ip": ip, "port": 10464}, {"uid": 0, "ip": "127.0.0.1", "port": 10704}],
    "files": base,
}
open(out, "w").write(json.dumps(cfg))
EOF
REPLAY1_OUT=$(PERL5LIB="$PERL_LIBS" perl "$REPO/tests/p2p_peer_helper.pl" requester "$SCRATCH/cfg_replay.json" 2>&1)
check "serving: the first presentation of a grant serves" "$(echo "$REPLAY1_OUT" | grep -q '^OK token='"$REPLAY_TOKEN"' sha='; echo $?)" "out: $REPLAY1_OUT"
REPLAY2_OUT=$(PERL5LIB="$PERL_LIBS" perl "$REPO/tests/p2p_peer_helper.pl" requester "$SCRATCH/cfg_replay.json" 2>&1)
check "serving: a grant replay is refused (GRANT_USED)" "$(echo "$REPLAY2_OUT" | grep -q 'REFUSED: GRANT_USED'; echo $?)" "out: $REPLAY2_OUT"

# Rejection: a channel-identity mismatch (the grant's requester UID does not
# match the peer certificate's CN).
write_helper_cfg "$SCRATCH/cfg_uid.json" requester "$HOME_B" 99 "$UID_B" "$UID_A" "$LOCAL_IP" 10464 "$FILES_REQ"
UID_OUT=$(PERL5LIB="$PERL_LIBS" perl "$REPO/tests/p2p_peer_helper.pl" requester "$SCRATCH/cfg_uid.json" 2>&1)
check "serving: a channel-identity mismatch is refused (UID_MISMATCH)" "$(echo "$UID_OUT" | grep -q 'REFUSED: UID_MISMATCH'; echo $?)" "out: $UID_OUT"

# Stop A before Phase 2 (B binds the same fixed ports).
kill -9 "$CLIENT_PID" 2>/dev/null
wait "$CLIENT_PID" 2>/dev/null
CLIENT_PID=""

# ============================================================================
# Phase 2 - the FETCHER (real client B as requester)
# ============================================================================
echo "=== Phase 2: fetcher (client B as requester) ==="

# The helper acts as the source (uid 41), listening on 127.0.0.1:10464 and
# serving the two files. It blocks on accept until B dials in.
write_helper_cfg "$SCRATCH/cfg_source.json" source "$HOME_A" "$UID_B" "$UID_B" "$UID_A" "127.0.0.1" 10464 "$FILES_SRC"
PERL5LIB="$PERL_LIBS" perl "$REPO/tests/p2p_peer_helper.pl" source "$SCRATCH/cfg_source.json" > "$SCRATCH/source.log" 2>&1 &
SOURCE_PID=$!
sleep 1
# A process-alive check, not a port probe: the source's accept loop skips
# non-TLS connections, but a probe would still be wasted work.
check "the fake peer source process is alive" "$(kill -0 "$SOURCE_PID" 2>/dev/null; echo $?)" "see $SCRATCH/source.log"

# Start client B (the requester; no files yet).
LUMINUM_HOME="$HOME_B" LUMINUM_CHECKIN_SECS=2 "$CLIENT_BIN" --debug > "$SCRATCH/client_b.log" 2>&1 &
CLIENT_PID=$!
sleep 1
check "client B process is alive after startup" "$(kill -0 "$CLIENT_PID" 2>/dev/null; echo $?)" "see $SCRATCH/client_b.log"

# B's check-in reached the worker and set STATUS.P2P.
B_P2P=1
for i in $(seq 1 40); do
    p=$(dbq "select P2P from STATUS where ID=$UID_B;")
    [ "$p" = "1" ] && { B_P2P=0; break; }
    sleep 0.5
done
check "client B check-in set STATUS.P2P = 1" "$B_P2P" "p2p: $(dbq "select P2P from STATUS where ID=$UID_B;")"

# Mint a server-signed peer grant (sources: peer uid 41 + server) and a
# deploy command carrying it in ref. The token is recorded in P2PTOKENS so
# the worker can fold B's terminal report.
MINT_OUT=$(PERL5LIB="$PERL_LIBS" perl -e '
    use strict; use warnings;
    use FindBin qw($Bin);
    unshift @INC, "$Bin/../server/lib";
    require Luminum::Protocol;
    my ($seedfile, $uid, $pkgid, $aid, $files_json, $sources_json) = @ARGV;
    open(my $sf, "<", $seedfile) or die "seed: $!"; binmode($sf); read($sf, my $seed, 32); close($sf);
    my $files = eval { require JSON::PP; JSON::PP->new->decode($files_json) };
    my $sources = eval { require JSON::PP; JSON::PP->new->decode($sources_json) };
    my $token = Luminum::Protocol::new_uuid4();
    # The client Envelope decodes uid as a String (the server mints it from
    # the string target), so both envelopes carry uid as a JSON string.
    my $grant = Luminum::Protocol::new_envelope(
        src => "server", uid => $uid, lumy => "core", action => "p2pgrant", status => "OK",
        data => { token => $token, pkgid => 0 + $pkgid, os => "Linux", aid => $aid,
                  files => $files, sources => $sources, exp => time() + 300 },
    );
    Luminum::Protocol::sign_envelope($grant, $seed);
    my $cmd = Luminum::Protocol::new_envelope(
        src => "server", uid => $uid, lumy => "core", action => "deploy", status => "OK",
        data => { pkgid => 0 + $pkgid, ref => { channel => "p2p", grant => $grant } },
    );
    Luminum::Protocol::sign_envelope($cmd, $seed);
    print $token, "\n";
    print JSON::PP->new->encode($cmd), "\n";
' "$CERTDIR/srv.seed" "$UID_B" "$PKGID" "peer-fetch" "$FILES_REQ" \
    '[{"uid":'"$UID_A"',"ip":"127.0.0.1","port":10464},{"uid":0,"ip":"127.0.0.1","port":10704}]' 2>&1)
FETCH_TOKEN=$(echo "$MINT_OUT" | sed -n '1p')
DEPLOY_JSON=$(echo "$MINT_OUT" | sed -n '2p')
[ -n "$FETCH_TOKEN" ] && [ -n "$DEPLOY_JSON" ] || { echo "SKIP - could not mint the peer grant"; exit 1; }

# Record the single-use grant so the worker folds B's terminal report.
dbq "insert into P2PTOKENS (TOKEN,PKGID,REQUID,SOURCES,EXPIRES) values ('$FETCH_TOKEN',$PKGID,$UID_B,'peer',from_unixtime($(($(date +%s) + 300))));"

# Publish the deploy command directly to B's cmd topic (bypassing the worker
# outbox, which would re-mint a server-only grant).
mosquitto_pub -h 127.0.0.1 -p "$PORT" -u "$SERVER_USER" -P "$SERVER_SECRET" \
    --cafile "$CERTDIR/luminum-ca.crt" --cert "$CERTDIR/server.crt" --key "$CERTDIR/server.key" \
    -t "luminum/$SID/$UID_B/cmd" -m "$DEPLOY_JSON"
check "the peer-grant deploy command was published to B" "$?" "see $SCRATCH/mosquitto.log"

# B's fetcher dials the source, receives and installs the files.
BF1="$HOME_B/Packages/$PKGID/bin/file1"
BF2="$HOME_B/Packages/$PKGID/lib/nested/file2"
BGOT1=""; BGOT2=""
for i in $(seq 1 60); do
    BGOT1=$(sha256sum "$BF1" 2>/dev/null | cut -d' ' -f1)
    BGOT2=$(sha256sum "$BF2" 2>/dev/null | cut -d' ' -f1)
    { [ "$BGOT1" = "$SHA1" ] && [ "$BGOT2" = "$SHA2" ]; } && break
    sleep 0.5
done
check "fetcher: file 1 installed at Packages/$PKGID/bin/file1" $([ "$BGOT1" = "$SHA1" ]; echo $?) "got: ${BGOT1:-missing}"
check "fetcher: file 2 installed at Packages/$PKGID/lib/nested/file2" $([ "$BGOT2" = "$SHA2" ]; echo $?) "got: ${BGOT2:-missing}"

# The source completed the session.
check "fetcher: the source logged the completed session" "$(grep -q '^OK served=2' "$SCRATCH/source.log"; echo $?)" "out: $(cat "$SCRATCH/source.log" 2>/dev/null)"

# B recorded the manifest rows.
BM1=$(python3 -c "
import sqlite3, sys
conn = sqlite3.connect('$HOME_B/config/p2p.db')
row = conn.execute('select PKGID, OS, PATH, SIZE, SHA256 from MANIFEST where FILEID = 1').fetchone()
print('|'.join(str(x) for x in row) if row else '')
" 2>/dev/null)
check "fetcher: manifest file 1 recorded" $([ "$BM1" = "$PKGID|Linux|bin/file1|$SIZE1|$SHA1" ]; echo $?) "got: ${BM1:-none}"

# The terminal report folded: the token is consumed, the holders are
# upserted with SOURCE '41' (the serving peer's UID).
BUSED_OK=1
for i in $(seq 1 60); do
    used=$(dbq "select USED from P2PTOKENS where TOKEN='$FETCH_TOKEN';")
    [ -n "$used" ] && [ "$used" != "NULL" ] && { BUSED_OK=0; break; }
    sleep 0.5
done
check "fetcher: p2p_fetch_ok consumed the grant token" "$BUSED_OK" "used: $(dbq "select USED from P2PTOKENS where TOKEN='$FETCH_TOKEN';")"
BH1=$(cdbq "select SOURCE from PKGHOLDERS where FILEID=1 and UID=$UID_B;")
BH2=$(cdbq "select SOURCE from PKGHOLDERS where FILEID=2 and UID=$UID_B;")
check "fetcher: PKGHOLDERS file 1 held with SOURCE '$UID_A'" $([ "$BH1" = "$UID_A" ]; echo $?) "source: ${BH1:-none}"
check "fetcher: PKGHOLDERS file 2 held with SOURCE '$UID_A'" $([ "$BH2" = "$UID_A" ]; echo $?) "source: ${BH2:-none}"

# The per-token staging tree is removed after the install.
check "fetcher: staging tree removed after the install" \
    "$([ ! -d "$HOME_B/Downloads/$FETCH_TOKEN" ]; echo $?)" \
    "left: $(ls "$HOME_B/Downloads" 2>/dev/null | tr '\n' ' ')"

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    echo "Artifacts left in $SCRATCH for inspection (worker.log, mosquitto.log, client_a.log, client_b.log, source.log)"
    exit 1
fi
echo "All checks passed."
exit 0
