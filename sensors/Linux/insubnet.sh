#!/bin/sh
#
# Luminum "In Subnet" Sensor (Linux)
# ==================================

ip -o addr show 2>/dev/null | awk -v s="$1" '
function bits(v, n,    out, i) {
	out = ""
	for (i = 0; i < n; i++) { out = (v % 2) out; v = int(v / 2) }
	return out
	}

function bin4(a, o, n, i, out) {
	n = split(a, o, ".")
	if (n != 4) return ""
	out = ""
	for (i = 1; i <= 4; i++) {
		if (o[i] !~ /^[0-9]+$/ || length(o[i]) > 3 || o[i] + 0 > 255) return ""
		out = out bits(o[i] + 0, 8)
		}
	return out
	}

function hex(h, i, v) {
	v = 0
	for (i = 1; i <= length(h); i++) v = v * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1
	return v
	}

function bin6(a, p, l, r, nl, nr, L, R, g, n, i, out) {
	a = tolower(a)
	if (a !~ /^[0-9a-f:]+$/) return ""
	p = index(a, "::")
	if (p) {
		l = substr(a, 1, p - 1); r = substr(a, p + 2)
		if (index(r, "::")) return ""
		nl = (l == "") ? 0 : split(l, L, ":")
		nr = (r == "") ? 0 : split(r, R, ":")
		if (nl + nr > 7) return ""
		n = 0
		for (i = 1; i <= nl; i++) g[++n] = L[i]
		for (i = 0; i < 8 - nl - nr; i++) g[++n] = "0"
		for (i = 1; i <= nr; i++) g[++n] = R[i]
		}
	else {
		n = split(a, g, ":")
		if (n != 8) return ""
		}
	out = ""
	for (i = 1; i <= 8; i++) {
		if (g[i] == "" || length(g[i]) > 4) return ""
		out = out bits(hex(g[i]), 16)
		}
	return out
	}

BEGIN {
	net = s; len = ""
	p = index(s, "/")
	if (p) { net = substr(s, 1, p - 1); len = substr(s, p + 1) }
	if (index(net, ":")) { fam = "inet6"; max = 128; nb = bin6(net) }
	else { fam = "inet";  max = 32;  nb = bin4(net) }
	if (p) { if (len !~ /^[0-9]+$/ || len + 0 > max) bad = 1; else len = len + 0 }
	else len = max
	if (nb == "") bad = 1
	if (bad) { print "FALSE"; done = 1; exit }
	pre = substr(nb, 1, len)
	}

$3 == fam {
	a = $4; sub(/\/.*/, "", a)
	ab = (fam == "inet6") ? bin6(a) : bin4(a)
	if (ab != "" && substr(ab, 1, len) == pre) { print "TRUE"; done = 1; exit }
	}
END { if (!done) print "FALSE" }
'

