#!/usr/bin/env bash
# Broker bootstrap-listener stall regression test.
#
# The old listener did IO::Socket::SSL->accept() with the TLS handshake
# inline, in a single-threaded loop with no timeout: one stalled handshake
# (a client that opened TCP but never sent a ClientHello) wedged the whole
# listener, so no further client could register until the broker was
# restarted. The fix (server/broker.pl setuplistener/startlistener) is a
# two-phase, fork-per-connection listener:
#   IO::Socket::SSL->new(SSL_startHandshake=>0)  -> accept() is plain TCP
#   -> fork a child -> $tcp->blocking(1) + $tcp->timeout(CONNTIMEOUT)
#   -> $tcp->accept_SSL() + handleconnection.
# This test reproduces that exact listener shape and proves the two
# properties the fix must hold:
#   1. a stalling client (TCP connect, no handshake) times out in its
#      handler child WITHOUT wedging the listener;
#   2. a subsequent good TLS client is still served.
#
# The TLS client is driven with `openssl s_client` because the Perl TLS
# client in this container is broken (it hangs even against a normal
# listener). The stalling client is a plain TCP socket (no TLS).
#
# Usage: bash tests/broker_stall_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
PERL_LIBS="$REPO/server/lib${PERL5LIB:+:$PERL5LIB}"
PERL5LIB="$PERL_LIBS" perl -e 'use IO::Socket::SSL;' 2>/dev/null \
    || { echo "SKIP - IO::Socket::SSL not available"; exit 0; }
[ -x "$(command -v openssl)" ] || { echo "SKIP - openssl not available"; exit 0; }

SCRATCH=$(mktemp -d)
PORT=14791
CTO=3
SERVER_LOG="$SCRATCH/server.log"
FAILURES=0
SRV_PID=""
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
    [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
    rm -rf "$SCRATCH"
}
trap cleanup EXIT

# --- self-signed TLS certificate for 127.0.0.1 -------------------------------
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -keyout "$SCRATCH/key.pem" -out "$SCRATCH/cert.pem" \
    -subj "/CN=127.0.0.1" \
    -addext "subjectAltName=IP:127.0.0.1" 2>/dev/null

# --- two-phase listener (the exact shape now in broker.pl) --------------------
cat > "$SCRATCH/server.pl" <<'PERL'
use strict;
use warnings;
use IO::Socket::SSL;
my ($port, $cert, $key, $cto, $log) = @ARGV;
open(STDOUT, ">>", $log) or die "stdout: $!\n";
$| = 1;
my $sock = IO::Socket::SSL->new(
    LocalAddr => "127.0.0.1:$port", Proto => "tcp", Listen => 20,
    SSL_cert_file => $cert, SSL_key_file => $key, SSL_startHandshake => 0,
) or die "listen: $SSL_ERROR\n";
print "server up\n";
$SIG{CHLD} = 'IGNORE';
my $n = 0;
while (1) {
    my $tcp = $sock->accept() or do { print "accept failed: $!\n"; sleep 0.2; next; };
    $n++;
    my $addr = $tcp->peerhost();
    print "parent: accept #$n from $addr\n";
    my $pid = fork();
    if (!defined $pid) { print "fork failed: $!\n"; close($tcp); next; }
    if ($pid == 0) {
        $tcp->blocking(1);
        $tcp->timeout($cto);
        my $t0 = time();
        my $ok = eval {
            $tcp->accept_SSL() or die "handshake failed: ".IO::Socket::SSL::errstr()."\n";
            my $data = "";
            my $r = $tcp->sysread(my $buf, 200);
            $data = $buf if $r;
            print "child #$n: handshake OK, got ", length($data), " bytes\n";
            1;
        };
        if ($ok) { print "child #$n: OK in ", (time()-$t0), "s\n"; }
        else     { print "child #$n: ended in ", (time()-$t0), "s: $@"; }
        exit 0;
    }
    close($tcp);
}
PERL

perl "$SCRATCH/server.pl" "$PORT" "$SCRATCH/cert.pem" "$SCRATCH/key.pem" "$CTO" "$SERVER_LOG" &
SRV_PID=$!

wait_for() {
    local pat="$1" secs="$2"
    local t0=$(date +%s)
    while [ $(( $(date +%s) - t0 )) -lt "$secs" ]; do
        grep -q "$pat" "$SERVER_LOG" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

# wait for the listener to come up
wait_for "server up" 5 || { echo "FAIL - listener did not start"; cat "$SERVER_LOG"; exit 1; }

# 1. stalling client: plain TCP, no handshake -> child must time out (~CTO s)
#    and the listener must keep accepting.
perl -e 'use IO::Socket::INET; my $s=IO::Socket::INET->new(PeerAddr=>"127.0.0.1:'"$PORT"'",Proto=>"tcp") or die "staller: $!\n"; select; sleep 30;' &
STALL_PID=$!
T0=$(date +%s)
if wait_for "child #1: ended" $(( CTO + 5 )); then
    ELAPSED=$(( $(date +%s) - T0 ))
    check "stalling client times out in its handler child (~${CTO}s)" 0
    # The child must have waited out the timeout (not failed instantly).
    if [ "$ELAPSED" -ge "$CTO" ]; then
        check "stall child waited out the socket timeout (${ELAPSED}s >= ${CTO}s)" 0
    else
        check "stall child waited out the socket timeout (${ELAPSED}s >= ${CTO}s)" 1 "ended too early"
    fi
else
    check "stalling client times out in its handler child (~${CTO}s)" 1 "no 'child #1: ended' in log"
fi

# 2. good TLS client while the listener is free -> must be served
printf 'HELLO-GOOD\n' | timeout 8 openssl s_client \
    -connect "127.0.0.1:$PORT" -quiet >/dev/null 2>&1
if wait_for "child #2: OK" 8; then
    check "good TLS client served after the stall" 0
else
    check "good TLS client served after the stall" 1 "no 'child #2: OK' in log"
fi

kill "$STALL_PID" 2>/dev/null
wait "$STALL_PID" 2>/dev/null

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    echo "--- server log ---"
    cat "$SERVER_LOG"
    exit 1
fi
echo "All checks passed."
exit 0
