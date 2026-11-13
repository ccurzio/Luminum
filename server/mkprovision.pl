#!/usr/bin/perl -w
#
# Luminum Client Provisioning File Generator
# by Christopher R. Curzio (ccurzio@luminum.net)
#
# Emits the out-of-band provisioning file (config.ini) that ships with a
# client distribution: a single self-contained JSON document carrying
# everything a fresh endpoint needs to register and talk to this server -
# the server host/port, the server key (SKEY), and the two trust-anchor
# certificates (the TLS server certificate and the Ed25519 signing
# certificate, protocol 7.1).
#
# The values are read from this server's own installed state, so the file
# always matches the running server:
#   - config/broker.conf  -> database credentials (DBUSER/DBPASS/DBSOCKET/DBHOST)
#   - SYSTEM.CONFIG       -> SHOST, LPORT, SKEY, SSLCERT
#   - <ssldir>/server.crt            (SSLCERT)
#   - <ssldir>/server-signing.crt    (dirname of SSLCERT)
#
# The client's UID/SID/MQTT credentials and the server signing public key are
# NOT in this file: they are issued in the signed registration response
# (protocol 7.1), so a single provisioning file can be shared by every
# endpoint that registers with this server.
#
# Usage:
#   perl mkprovision.pl            # write config.ini to stdout
#   perl mkprovision.pl --out F    # write to F (0600)
#   perl mkprovision.pl --help
#
# Run as the user that can read the install's config/ and ssl/ (the DB
# credentials and the certificates are 0600/0644 under the install root).

use strict;
use Cwd qw(abs_path);
use FindBin qw($Bin);
use DBI;
use JSON::PP;

# --- arguments ---------------------------------------------------------------
my $out;
my $help = 0;
my @args = @ARGV;
while (@args) {
	my $a = shift @args;
	if ($a eq "--help" || $a eq "-h") { $help = 1; }
	elsif ($a eq "--out") { $out = shift @args; die "ERROR: --out requires a path\n" unless defined $out; }
	elsif ($a =~ /^--out=(.+)$/) { $out = $1; }
	else { die "Unknown option: $a (see --help)\n"; }
}
if ($help) {
	print <<'USAGE';
Luminum Client Provisioning File Generator

Usage: perl mkprovision.pl [--out FILE]

  --out FILE   write the provisioning file to FILE (mode 0600) instead of stdout
  -h, --help   show this help

Reads SHOST/LPORT/SKEY/SSLCERT from this server's SYSTEM.CONFIG and the
server + signing certificates from the install's ssl/ directory, and emits
a self-contained config.ini (JSON) for client out-of-band provisioning.
USAGE
	exit 0;
}

# --- install root (same resolution as broker.pl) -----------------------------
my $mgrpath = abs_path($0);
my $mgrname = $mgrpath;
$mgrname =~ s{^(\/.*\/)}{};
$mgrpath =~ s{\/$mgrname}{};

# --- database credentials from broker.conf -----------------------------------
my $brokerconf = "$mgrpath/config/broker.conf";
open(my $bc, "<", $brokerconf) or die "FATAL: cannot read broker configuration: $brokerconf ($!)\n";
my ($dbuser, $dbpass, $dbhost, $dbsock);
while (my $line = <$bc>) {
	next if $line =~ /^#/;
	if ($line =~ /^DBUSER[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbuser = $1; }
	elsif ($line =~ /^DBPASS[\s|\t]?+\=[\s|\t]?+(.*)$/) { $dbpass = $1; }
	elsif ($line =~ /^DBHOST[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbhost = $1; }
	elsif ($line =~ /^DBSOCKET[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbsock = $1; }
}
close($bc);
die "FATAL: no database user in $brokerconf\n" unless defined $dbuser && $dbuser ne "";

my %attr = ( PrintError => 0, RaiseError => 1 );
$attr{mysql_socket} = $dbsock if $dbsock;
$attr{mysql_host}   = $dbhost if $dbhost;

my $dbh = eval { DBI->connect("DBI:mysql:SYSTEM", $dbuser, $dbpass, \%attr) };
die "FATAL: cannot connect to the SYSTEM database: $@\n" unless $dbh;

# --- SYSTEM.CONFIG -----------------------------------------------------------
my %cfg;
my $sth = eval { $dbh->prepare("select CKEY, CVAL from CONFIG") };
die "FATAL: cannot read SYSTEM.CONFIG: $@\n" unless $sth;
$sth->execute();
while (my @row = $sth->fetchrow_array()) { $cfg{$row[0]} = $row[1]; }
$sth->finish();
$dbh->disconnect();

my $shost = $cfg{SHOST};
my $lport = $cfg{LPORT};
my $skey  = $cfg{SKEY};
my $cert  = $cfg{SSLCERT};

die "FATAL: SYSTEM.CONFIG is missing SHOST (run the installer)\n" unless defined $shost && $shost ne "";
die "FATAL: SYSTEM.CONFIG is missing LPORT (run the installer)\n" unless defined $lport && $lport =~ /^\d+$/;
die "FATAL: SYSTEM.CONFIG is missing SKEY (run the installer)\n" unless defined $skey && $skey ne "";
die "FATAL: SYSTEM.CONFIG is missing SSLCERT (run the installer)\n" unless defined $cert && $cert ne "";

# --- certificates ------------------------------------------------------------
my $ssldir = $cert;
$ssldir =~ s{/[^/]+$}{};   # dirname of SSLCERT
my $signcert = "$ssldir/server-signing.crt";

sub slurp {
	my ($path) = @_;
	open(my $fh, "<:raw", $path) or die "FATAL: cannot read certificate: $path ($!)\n";
	local $/;
	my $data = <$fh>;
	close($fh);
	return $data;
}

my $server_pem = slurp($cert);
my $signing_pem = slurp($signcert);
die "FATAL: server certificate is empty: $cert\n" unless $server_pem =~ /BEGIN CERTIFICATE/;
die "FATAL: server signing certificate is empty: $signcert\n" unless $signing_pem =~ /BEGIN CERTIFICATE/;

# --- emit --------------------------------------------------------------------
my $doc = {
	v => "1.0",
	server => {
		host => $shost,
		port => 0 + $lport,
		key  => $skey,
	},
	certificates => {
		server  => $server_pem,
		signing => $signing_pem,
	},
};
my $json = JSON::PP->new->canonical->pretty->allow_nonref->encode($doc);

if (defined $out) {
	open(my $ofh, ">", $out) or die "FATAL: cannot write $out ($!)\n";
	print $ofh $json;
	close($ofh);
	chmod(0600, $out);
	print "Provisioning file written to $out\n";
} else {
	print $json;
}
exit 0;
