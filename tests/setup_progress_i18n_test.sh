#!/usr/bin/env bash
# setup_progress_i18n_test.sh - static check that the installer's rotating
# progress texts (the step texts Luminum::Setup reports to the progress
# callback, displayed by the curses wizard's step label) carry a
# translation in every supported non-English language block of setup.pl
# (DE, IT, FR, ES), that each block sets the initial step label, and that
# every key still exists in Setup.pm (drift in either direction fails):
#   - a step added to Setup.pm without a translation
#   - a translation key whose step text was renamed or removed
#
# Usage: bash tests/setup_progress_i18n_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
SETUP="$REPO/server/setup.pl"
LIB="$REPO/server/lib/Luminum/Setup.pm"
[ -f "$SETUP" ] && [ -f "$LIB" ] || { echo "SKIP - setup.pl / Setup.pm not found"; exit 0; }

FAILURES=0
check() {
    local name="$1" ok="$2" detail="${3:-}"
    if [ "$ok" -eq 0 ]; then
        echo "ok   - $name"
    else
        FAILURES=$((FAILURES + 1))
        echo "FAIL - $name${detail:+ ($detail)}"
    fi
}

# The wizard's step list (mirrors tests/setup_progress_test.pl; the
# certificate step has three variants selected by the certificate mode).
keys=(
    "Checking dependencies..."
    "Synchronizing server files..."
    "Setting up database..."
    "Generating server certificate..."
    "Generating server certificate from existing key..."
    "Importing server certificate..."
    "Provisioning MQTT broker..."
    "Generating server identity..."
    "Writing configuration files..."
    "Seeding database configuration..."
    "Writing web console configuration..."
    "Installing service management..."
    "Starting and verifying services..."
)

# Every key must still be a step text in Setup.pm. The certificate step's
# three variants are stored without the trailing "..." (the step call
# appends it), so match on the base text.
for k in "${keys[@]}"; do
    check "Setup.pm still reports '$k'" \
        $(grep -Fq "${k%...}" "$LIB" && echo 0 || echo 1)
done

# Extract one language block: from its "elsif ($ENV{LANG} =~ /xx_/)" line
# up to (not including) the next elsif/else line.
block() {
    awk -v lang="$1" '
        $0 ~ "elsif \\(\\$ENV\\{LANG\\} =~ /" lang "_/" { inblk = 1; next }
        inblk && ($0 ~ /^elsif / || $0 ~ /^else /) { inblk = 0 }
        inblk { print }
    ' "$SETUP"
}

for lang in de it fr es; do
    b=$(block "$lang")
    if [ -z "$b" ]; then
        check "language block $lang found" 1
        continue
    fi
    check "language block $lang found" 0
    check "language block $lang sets the initial step label" \
        $(printf '%s\n' "$b" | grep -qF "$(printf '\t$startlabel = ')" && echo 0 || echo 1)
    for k in "${keys[@]}"; do
        check "language block $lang translates '$k'" \
            $(printf '%s\n' "$b" | grep -Fq "\"$k\"" && echo 0 || echo 1)
    done
done

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
fi
echo "All checks passed."
exit 0
