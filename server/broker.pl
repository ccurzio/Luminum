#!/usr/bin/perl -w
#
# Luminum Server Manager v0.0.2
# by Christopher R. Curzio (ccurzio@luminum.net)
#
# Wire protocol: docs/protocol.md v1.0-draft
#  - The network listener (LPORT) speaks the bootstrap channel:
#    length-prefixed JSON frames carrying Ed25519-signed envelopes
#    (protocol 5, 8.2). One request/response exchange per connection.
#  - Registration (7.1): server key check, signature possession proof,
#    UID assignment, MQTT secret issuance (SHA-256 hash stored), and a
#    signed response carrying the server signing public key.
#  - Check-in (7.2), deactivation, and Lumy configuration requests
#    (newconfig) are handled on the same channel.
#  - MQTT (MPORT): a forked Luminum::MQTT worker publishes commands from
#    the CLIENTS.COMMANDS outbox and correlates client responses -
#    setgroups/config by action, query answers by data.qid with per-sensor
#    result storage (QUERYRESULTS) and per-action deadlines (7.3, 9.3).
#  - Bulk data channel transfers (8.3) are not yet implemented.

use strict;
use Cwd qw(abs_path);
use FindBin qw($Bin);
use POSIX qw(strftime);
use Time::HiRes ("usleep");
use DBI;
use JSON::PP;
use MIME::Base64;
use Digest::SHA qw(sha256_hex);
use IO::Socket::SSL;
use Crypt::Perl::Ed25519::PrivateKey;
use Crypt::Perl::Ed25519::PublicKey;
use lib "$Bin/lib";
use Luminum::Protocol;
use Luminum::MQTT;

our $debug = 0;
our $writelog = 1;
my $suerror;
my $logdir;
our $brokerlog;
my $SID;
my $SHOST;
my $LADDR;
my $LPORT;
my $SKEY;
my $MADDR;
my $MPORT = 8883;
my $CMDTIMEOUT = 120;
my $DEPLTIMEOUT = 3600;
my $MQTTUSER;
my $MQTTPASS;
my $MQTTPASSWD;
my $MQTTACL;
my $MQTTPIDFILE;
my $MQTTCA;
my $workerpid;
my $sslcert;
my $sslprvkey;
my $sslpubkey;
my $srvseed;
my $srvpub;
my $srvpubspki;
my $sock;
my @lumys;
my %seenid;

our $dbuser;
our $dbpass;
our $dbhost;
our $dbsock;
our %attr;

my $listen = 1;

$suerror = 0;

my $broken = 0;
my $hupped = 0;
$SIG{INT} = \&catchbreak;
$SIG{HUP} = \&catchhup;

if (scalar(@ARGV) > 0) {
	foreach(@ARGV) {
		if ($_ eq "--debug") { $debug = 1; }
		elsif ($_ eq "--nolog") { $writelog = 0; }
		}
	}

# Where Am I? (Establish Filesystem Location)
#
my $mgrpath = abs_path($0);
my $mgrname = $mgrpath;
$mgrname =~ s/^(\/.*\/)//;
$mgrpath =~ s/\/$mgrname//;

getbrokerconf();

Broker::debugout(0,"Server Startup");
if ($writelog == 0) { Broker::debugout(2,"Writing broker logs to disk has been disabled."); }

startserver();
startweb();
setuplistener();
# Write our own pid file now that the listener is bound, so the installed
# stop script can find us no matter how we were started (start script,
# systemd unit, manually) - the start script's "echo $!" only covers its
# own path. A failed second start exits inside setuplistener() and never
# reaches here, so it cannot clobber the running broker's pid file. Must
# stay before startmqtt() forks the MQTT worker, which has a different
# PID.
{
	my $pidfile = "$mgrpath/run/broker.pid";
	if (open(my $pfh, ">", $pidfile)) {
		print $pfh "$$\n";
		close($pfh);
		}
	else { Broker::debugout(2,"Cannot write pid file $pidfile: $!"); }
	}
startmqtt();

Broker::debugout(1,"Server startup complete.");
Broker::debugout(0,"- Web Console: https://$SHOST");
Broker::debugout(0,"- Luminum Server ID: $SID");
Broker::debugout(0,"- Broker Log: $brokerlog");
Broker::debugout(0,"- Listening on $LADDR:$LPORT");

startlistener();

# Luminum Server Initialization
#
sub startserver {
	%attr = (
		PrintError=>0,
		RaiseError=>1
		);

	if ($dbsock && -e $dbsock) {
		# An external database socket was provided in broker.conf; the
		# database service is managed outside of the broker.
		Broker::debugout(0,"Using external database at socket: $dbsock");
		}
	else {
		my $dbstat = `/usr/bin/systemctl status mysqld | /usr/bin/grep Active`;
		if ($dbstat =~ /inactive/) {
			Broker::debugout(0,"Initializing Database...");
			system("/usr/bin/systemctl start mysqld");
			if (`/usr/bin/systemctl status mysqld | /usr/bin/grep Active` =~ /inactive/) {
				Broker::debugout(3,"Database initialization failed: Unable to start service.");
				exit 1;
				}
			}
		elsif ($dbstat =~ /running/) { Broker::debugout(0,"Database service is already running. Validating..."); }
		else {
			Broker::debugout(3,"Unable to determine database service state. Aborting.");
			exit 1;
			}

		my $mysock = `/usr/bin/grep socket /etc/mysql/my.cnf | /usr/bin/grep -v "#" | /usr/bin/sed -e 's/^socket.*= \\\//\\\//'`;
		chomp($mysock);
		if (!-e $mysock || $mysock eq "") {
			Broker::debugout(3,"Database initialization failed: Unable to validate local socket.");
			exit 1;
			}
		$dbsock = $mysock;
		Broker::debugout(0,"Validated local database socket: $dbsock");
		my $dbpid = `/usr/bin/cat /var/run/mysqld/mysqld.pid`;
		chomp ($dbpid);
		Broker::debugout(1,"Database service initialized. (PID $dbpid)");
		}

	$attr{mysql_socket} = $dbsock if $dbsock;
	$attr{mysql_host} = $dbhost if $dbhost;

	eval { my $dbh = dbconnect("SYSTEM"); $dbh->disconnect(); };
	if ($@) {
		Broker::debugout(3,"Database initialization failed: unable to connect: $@");
		exit 1;
		}
	Broker::debugout(1,"Database initialized successfully.");
	readconfig();
	lumyload();
	}

# Open a connection to a Luminum database using the configured
# credentials and (optional) socket/host from broker.conf.
#
sub dbconnect {
	my $dbname = shift;
	return DBI->connect("DBI:mysql:$dbname",$dbuser,$dbpass,\%attr);
	}

# Luminum Server Shutdown
#
sub stopserver {
	Broker::debugout(0,"Stopping database...");
	system("/usr/bin/systemctl stop mysqld");
	if (`/usr/bin/systemctl status mysqld | /usr/bin/grep Active` =~ /inactive/) { Broker::debugout(1,"Database stopped successfully."); }
	else {
		$suerror = 1;
		Broker::debugout(2,"Clean stop of database failed!");
		}
	if ($suerror == 0) { Broker::debugout(1,"Server shutdown complete."); }
	else { Broker::debugout(2,"Server shutdown completed with errors."); }
	}

# True when a usable systemd is present to manage services.
#
sub systemd_available {
	return 0 unless -x "/usr/bin/systemctl";
	my $state = `/usr/bin/systemctl is-system-running 2>/dev/null`;
	chomp($state);
	return ($state =~ /^(running|degraded)$/) ? 1 : 0;
	}

# Start Web Console
#
sub startweb {
	unless (systemd_available()) {
		Broker::debugout(0,"Web console is managed externally (no systemd); skipping nginx management.");
		return;
		}
	if (`/usr/bin/systemctl status nginx | /usr/bin/grep Active` =~ /inactive/) {
		Broker::debugout(0,"Initializing Web Console...");
		system("/usr/bin/systemctl start nginx");
		if (`/usr/bin/systemctl status nginx | /usr/bin/grep Active` =~ /inactive/) {
			Broker::debugout(3,"Web console initialization failed: Unable to start service.");
			}
		else {
			my $wspid = `/usr/bin/cat /var/run/nginx.pid`;
			chomp ($wspid);
			Broker::debugout(1,"Web console initialized successfully. (PID $wspid)");
			}
		}
	}

# Stop Web Console
#
sub stopweb {
	unless (systemd_available()) { return; }
	Broker::debugout(0,"Stopping Web Console...");
	system("/usr/bin/systemctl stop nginx");
	if (`/usr/bin/systemctl status nginx | /usr/bin/grep Active` =~ /inactive/) { Broker::debugout(1,"Web console stopped successfully."); }
	else {
		$suerror = 1;
		Broker::debugout(2,"Unable to stop Web Console.");
		}
	}

# Set Up Network Listener
#
sub setuplistener {
	Broker::debugout(0,"Initializing Network Listener...");
	undef($sock);
	$sock = IO::Socket::SSL->new(
		LocalAddr => $LADDR,
		LocalPort => $LPORT,
		Proto => 'tcp',
		Listen => 20,
		SSL_hostname => $SHOST,
		SSL_cert_file => $sslcert,
		SSL_key_file => $sslprvkey
		)
	or do {
		Broker::debugout(3,"Network Listener could not be initialized.");
		$suerror = 1;
		stopserver();
		exit 1;
		};
	if ($sock) { Broker::debugout(1,"Network Listener initialized successfully."); }
	if ($hupped == 1) {
		Broker::debugout(1,"Server Reload Complete.");
		$hupped = 0;
		}
	}

# Start Network Listener
#
sub startlistener {
	$listen = 1;
	while($listen == 1) {
		my $client_socket = $sock->accept() or do { Broker::debugout(2,"Client connection failed: $!"); next; };
		my $client_address = $client_socket->peerhost();
		my $client_port = $client_socket->peerport();
		Broker::debugout(0,"Inbound connection from $client_address:$client_port");
		handleconnection($client_socket,$client_address);
		Broker::debugout(0,"Connection with $client_address closed.");
		}
	}

# Stop Network Listener
#
sub stoplistener {
	Broker::debugout(0,"Stopping Network Listener...");
	$listen = 0;
	close($sock);
	undef($sock);
	if (!$sock) { Broker::debugout(1,"Network Listener stopped successfully."); }
	else {
		Broker::debugout(3,"Unable to stop Network Listener. Retrying in 3 seconds...");
		sleep(3);
		close($sock);
		if (!$sock) { Broker::debugout(1,"Network Listener stopped successfully."); }
		else { Broker::debugout(3,"Retry failed. Forcing shutdown."); }
		}
	}

# Start MQTT Worker (protocol 4, 9)
#
# Forks a child that runs Luminum::MQTT::worker, isolated from the blocking
# bootstrap listener loop. Before forking, the parent ensures the server user
# is in the mosquitto password_file and the ACL file reflects the known OS
# values and group names, then reloads the broker so the changes take effect.
# The worker persists across SIGHUP (this is only called at initial startup,
# not from catchhup).
#
sub startmqtt {
	if (!$MQTTPASS || $MQTTPASS eq "") {
		$MQTTPASS = encode_base64(randombytes(24), "");
		setconfig("MQTTPASS", $MQTTPASS);
		Broker::debugout(0,"Generated server MQTT password.");
	}
	unless (Luminum::MQTT::passwd_add($MQTTPASSWD, $MQTTUSER, $MQTTPASS)) {
		Broker::debugout(2,"Unable to write the server user to the MQTT password_file: $MQTTPASSWD");
	}
	my $dbh = dbconnect("CLIENTS");
	eval { Luminum::MQTT::regen_acl($dbh, sid => $SID, server_user => $MQTTUSER, acl_file => $MQTTACL, pid_file => $MQTTPIDFILE); };
	if ($@) { Broker::debugout(2,"Unable to regenerate the MQTT ACL file: $@"); }
	$dbh->disconnect();
	Luminum::MQTT::reload($MQTTPIDFILE);
	my $pid = fork();
	if (!defined $pid) { Broker::debugout(3,"Failed to fork the MQTT worker: $!"); return; }
	if ($pid == 0) {
		Luminum::MQTT::worker(
			sid => $SID, host => $MADDR, port => $MPORT, ca => $MQTTCA,
			user => $MQTTUSER, secret => $MQTTPASS, seed => $srvseed,
			dbname => "CLIENTS", dbuser => $dbuser, dbpass => $dbpass, dbsock => $dbsock, dbhost => $dbhost,
			poll_secs => 1,
			cmd_timeout => $CMDTIMEOUT, depl_timeout => $DEPLTIMEOUT,
			log => sub { Broker::debugout(0, "[mqtt] $_[0]"); },
			);
		exit 0;
	}
	$workerpid = $pid;
	Broker::debugout(1,"MQTT worker started (PID $pid).");
}

# Read Broker Configuration
#
sub getbrokerconf {
	if (-e "$mgrpath\/config") {
		# Check for Broker Configuration
		if (-e "$mgrpath\/config\/broker.conf") {
			open (BCONF, "$mgrpath\/config\/broker.conf");
			foreach (<BCONF>) {
				next if ($_ =~ /^#.*$/);
				if ($_ =~ /^LOGDIR[\s|\t]?+\=[\s|\t]?+(.*)$/) {
					mkdir($1, 0700) unless(-d $1 );
					$brokerlog = "$1\/broker.log";
					}
				elsif ($_ =~ /^DBUSER[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbuser = $1; }
				elsif ($_ =~ /^DBPASS[\s|\t]?+\=[\s|\t]?+(.*)$/) { $dbpass = $1; }
				elsif ($_ =~ /^DBHOST[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbhost = $1; }
				elsif ($_ =~ /^DBSOCKET[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbsock = $1; }
				}
			close (BCONF);
			}
		else { die "FATAL: Broker Configuration Missing: $mgrpath\/config\/broker.conf"; }
		}
	else { die "FATAL: Configuration Directory Missing: $mgrpath\/config\n"; }

	if (!$dbuser || $dbuser eq "") { die "FATAL: Database user not specified in config.\n"; }
	}

# Read Server Configuration
#
sub readconfig {
	Broker::debugout(0,"Reading Server Configuration...");
	my $dbh = dbconnect("SYSTEM");
	my $sth = $dbh->prepare("select table_name from information_schema.tables where table_schema = 'SYSTEM' and table_name = 'CONFIG'");
	$sth->execute();
	if ($sth->rows == 0) {
		Broker::debugout(3,"Server configuration does not exist! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	else {
		my $sth = $dbh->prepare("select CKEY,CVAL from CONFIG");
		$sth->execute();
		while (my @row = $sth->fetchrow_array()) {
			if ($row[0] eq "SID") { $SID = $row[1]; }
			elsif ($row[0] eq "SKEY") { $SKEY = $row[1]; }
			elsif ($row[0] eq "SHOST") { $SHOST = $row[1]; }
			elsif ($row[0] eq "LADDR") { $LADDR = $row[1]; }
			elsif ($row[0] eq "LPORT") { $LPORT = $row[1]; }
			elsif ($row[0] eq "MADDR") { $MADDR = $row[1]; }
			elsif ($row[0] eq "MPORT") { $MPORT = $row[1]; }
			elsif ($row[0] eq "CMDTIMEOUT") { $CMDTIMEOUT = $row[1]; }
			elsif ($row[0] eq "DEPLTIMEOUT") { $DEPLTIMEOUT = $row[1]; }
			elsif ($row[0] eq "MQTTUSER") { $MQTTUSER = $row[1]; }
			elsif ($row[0] eq "MQTTPASS") { $MQTTPASS = $row[1]; }
			elsif ($row[0] eq "MQTTPASSWD") { $MQTTPASSWD = $row[1]; }
			elsif ($row[0] eq "MQTTACL") { $MQTTACL = $row[1]; }
			elsif ($row[0] eq "MQTTPIDFILE") { $MQTTPIDFILE = $row[1]; }
			elsif ($row[0] eq "MQTTCA") { $MQTTCA = $row[1]; }
			elsif ($row[0] eq "SSLCERT") { $sslcert = $row[1]; }
			elsif ($row[0] eq "SSLPRVKEY") { $sslprvkey = $row[1]; }
			elsif ($row[0] eq "SSLPUBKEY") { $sslpubkey = $row[1]; }
			}
		}

	if (!$SID || $SID eq "") {
		Broker::debugout(3,"Undefined Server ID! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$SKEY || $SKEY eq "") {
		Broker::debugout(3,"Undefined Server Key! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$SHOST || $SHOST eq "") {
		Broker::debugout(3,"Undefined Server Hostname! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$LADDR || $LADDR eq "") {
		Broker::debugout(3,"Undefined Network Listener Address! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$LPORT || $LPORT eq "") {
		Broker::debugout(3,"Undefined Network Listener Port! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	elsif($LPORT !~ /^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$/) {
		Broker::debugout(3,"Invalid Network Listener Port: $LPORT");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	# MQTT listener (protocol 4.1, 11). Defaults: LADDR / 8883.
	if (!$MADDR || $MADDR eq "") { $MADDR = $LADDR; }
	if (!$MPORT || $MPORT !~ /^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$/) { $MPORT = 8883; }
	if (!$CMDTIMEOUT || $CMDTIMEOUT !~ /^[0-9]+$/) { $CMDTIMEOUT = 120; }
	if (!$DEPLTIMEOUT || $DEPLTIMEOUT !~ /^[0-9]+$/) { $DEPLTIMEOUT = 3600; }
	# MQTT broker integration (protocol 4, 9). The worker connects to the
	# Mosquitto broker as $MQTTUSER and maintains the password_file and ACL
	# file that Mosquitto is configured to use, reloading it (SIGHUP) after
	# changes. The password/ACL files default under the install's config
	# dir; the pid file defaults to the system-standard location (setup
	# generates mosquitto.conf with the same path). Set the MQTT* keys in
	# SYSTEM.CONFIG to point at a different Mosquitto layout.
	if (!$MQTTUSER || $MQTTUSER eq "") { $MQTTUSER = "luminum-server"; }
	if (!$MQTTCA || $MQTTCA eq "") { $MQTTCA = $sslcert; }
	if (!$MQTTPASSWD || $MQTTPASSWD eq "") { $MQTTPASSWD = "$mgrpath/config/mosquitto/passwd"; }
	if (!$MQTTACL || $MQTTACL eq "") { $MQTTACL = "$mgrpath/config/mosquitto/acl"; }
	if (!$MQTTPIDFILE || $MQTTPIDFILE eq "") { $MQTTPIDFILE = "/var/run/mosquitto/mosquitto.pid"; }
	if (!$sslprvkey || $sslprvkey eq "") {
		Broker::debugout(3,"Server private key file is not configured! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	elsif (!-e $sslprvkey) {
		Broker::debugout(3,"Server private key file is missing: $sslprvkey");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$sslpubkey || $sslpubkey eq "") {
		Broker::debugout(3,"Server public key file is not configured! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	elsif (!-e $sslpubkey) {
		Broker::debugout(3,"Server public key file is missing: $sslpubkey");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$sslcert || $sslcert eq "") {
		Broker::debugout(3,"Server certificate is not configured! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	elsif (!-e $sslcert) {
		Broker::debugout(3,"Server certificate is missing: $sslcert");
		$suerror = 1;
		stopserver();
		exit 1;
		}

	loadserverkey();

	Broker::debugout(1,"Configuration Successfully Imported.");
	Broker::debugout(0,"- SSL Certificate: $sslcert");
	Broker::debugout(0,"- SSL Private Key File: $sslprvkey");
	Broker::debugout(0,"- SSL Public Key File: $sslpubkey");
	Broker::debugout(0,"- MQTT Listener: $MADDR:$MPORT");
	}

# Load (or generate on first run) the server Ed25519 signing keypair
# (protocol 3.1, 7.1). Stored in SYSTEM.CONFIG as SRVPRV (base64
# 32-byte seed) and SRVPUB (base64 raw public key).
#
sub loadserverkey {
	my $dbh = dbconnect("SYSTEM");
	my $sth = $dbh->prepare("select CVAL from CONFIG where CKEY = 'SRVPRV'");
	$sth->execute();
	my @row = $sth->fetchrow_array();
	my $prvb64 = $row[0];
	$sth = $dbh->prepare("select CVAL from CONFIG where CKEY = 'SRVPUB'");
	$sth->execute();
	@row = $sth->fetchrow_array();
	my $pubb64 = $row[0];

	if ($prvb64 && $pubb64) {
		my $seed = eval { decode_base64($prvb64) };
		my $pub = eval { decode_base64($pubb64) };
		if (defined $seed && length($seed) == 32 && defined $pub && length($pub) == 32) {
			$srvseed = $seed;
			$srvpub = $pub;
			$srvpubspki = encode_base64(Luminum::Protocol::raw_to_spki($pub), "");
			Broker::debugout(1,"Server signing key loaded.");
			return;
			}
		Broker::debugout(2,"Stored server signing key is invalid. Regenerating...");
		}

	my $priv = Crypt::Perl::Ed25519::PrivateKey->new();
	$srvseed = $priv->get_private();
	$srvpub = $priv->get_public_key()->get_public();
	$srvpubspki = encode_base64(Luminum::Protocol::raw_to_spki($srvpub), "");
	setconfig("SRVPRV",encode_base64($srvseed,""));
	setconfig("SRVPUB",encode_base64($srvpub,""));
	Broker::debugout(0,"Generated new server signing keypair.");
	}

# Set Server Configuration Options
# setconfig("LADDR","172.16.8.10");
#
# 1 = OK
# 2 = Error
#
sub setconfig {
	my $ckey = $_[0];
	my $cval = $_[1];
	my $scstat;

	if ($ckey =~ /^[A-Z]+$/ && $cval =~ /^[A-Za-z0-9_\.\,\/+=]+$/) {
		if ($ckey eq "LPORT" && $cval !~ /^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$/) {
			Broker::debugout(2,"Invalid value specified for configuration change to LPORT: \"$cval\"");
			$scstat = 2;
			}
		else {
			my $dbh = dbconnect("SYSTEM");
			my $sth = $dbh->prepare("update CONFIG set CVAL = '$cval' where CKEY = '$ckey'");
			$sth->execute();
			}
		}
	return $scstat;
	}

# Load Server Modules
#
sub lumyload {
	@lumys = ();
	if (-e "$mgrpath\/config/lumys_enabled" && -d "$mgrpath\/config/lumys_enabled") {
		opendir(my $dir, "$mgrpath\/config/lumys_enabled");
		my @lumylist = readdir $dir;
		close($dir);
		@lumylist = grep ! /^\..*$/, @lumylist;
		if (scalar(@lumylist) > 0) {
			Broker::debugout(0,"Initializing Lumys...");
			for my $lname (@lumylist) {
				my $dname = $lname;
				$dname =~ s/\.lumy//;
				my $elname = lc($dname);
				my $elver;
				my $elerr;
				require("$mgrpath\/config/lumys_enabled/$lname");
				if (exists &{"$dname\::checkfunc"}) {
					my $lstat = &{\&{"$dname\::checkfunc"}}();
					if ($lstat eq "OK") {
						push(@lumys,$elname);
						$elver = &{\&{"$dname\::getver"}}();
						}
					else {
						$elerr = $lstat;
						}
					}
				if (grep(/^$elname$/,@lumys) && $elver) { Broker::debugout(1,"- Lumy Loaded: $dname v$elver"); }
				else { Broker::debugout(3,"- Failure loading $dname Lumy: $elerr"); }
				}
			setconfig("ENLUMYS",join(',',@lumys));
			}
		}
	}

# Handle a single bootstrap channel connection: one framed request,
# one framed response, then close (protocol 8.2).
#
sub handleconnection {
	my $cs = shift;
	my $EPADDR = shift;
	my $authfails = 0;

	my $env = readframe($cs,64*1024);
	if (!defined $env) {
		Broker::debugout(2,"Malformed frame received from $EPADDR");
		close($cs);
		return;
		}

	my ($vok,$verr) = Luminum::Protocol::validate_envelope($env);
	if (!$vok) {
		if ($verr eq "PROTO_VERSION_MISMATCH") {
			# Protocol 6.3: drop, log, no response.
			Broker::debugout(2,"PROTO_VERSION_MISMATCH: dropping message from $EPADDR");
			close($cs);
			return;
			}
		Broker::debugout(2,"$verr: message from $EPADDR rejected");
		sendresponse($cs,$env,"ERR",$verr,undef);
		close($cs);
		return;
		}

	if ($env->{src} ne "client") {
		Broker::debugout(2,"INVALID_SRC: message from $EPADDR rejected (src=$env->{src})");
		sendresponse($cs,$env,"ERR","INVALID_SRC",undef);
		close($cs);
		return;
		}

	# Deduplication (protocol 9.2).
	if (exists $seenid{$env->{id}}) {
		if ($seenid{$env->{id}} ne $env->{sig}) {
			Broker::debugout(2,"ID_SPOOF_ATTEMPT: duplicate id with different signature from $EPADDR");
			$authfails++;
			}
		else { Broker::debugout(1,"Duplicate message id from $EPADDR dropped"); }
		sendresponse($cs,$env,"ERR","DUPLICATE_ID",undef);
		close($cs);
		return;
		}
	$seenid{$env->{id}} = $env->{sig};
	if (scalar(keys(%seenid)) > 4096) { %seenid = (); }

	# Per-message signature verification (protocol 3.3).
	my $pubraw;
	if ($env->{uid} eq "0") {
		# Registration: the public key is carried in the message and
		# the signature against it is the possession proof (7.1).
		my $pubder = eval { decode_base64($env->{data}{pubkey} // "") };
		$pubraw = defined $pubder ? Luminum::Protocol::spki_to_raw($pubder) : undef;
		}
	else {
		my $pubder = getpubkey($env->{uid});
		$pubraw = defined $pubder && $pubder ne "" ? Luminum::Protocol::spki_to_raw(decode_base64($pubder)) : undef;
		}
	if (!defined $pubraw || !Luminum::Protocol::verify_envelope($env,$pubraw)) {
		$authfails++;
		if ($authfails >= 3) {
			Broker::debugout(2,"MSG_AUTH_FAIL: terminating connection from $EPADDR (3 failures)");
			close($cs);
			return;
			}
		Broker::debugout(2,"MSG_AUTH_FAIL: signature verification failed for message from $EPADDR");
		sendresponse($cs,$env,"ERR","BAD_SIGNATURE",undef);
		close($cs);
		return;
		}

	# Deactivated clients are rejected on every channel (protocol 4.1).
	if ($env->{uid} ne "0" && getcstate($env->{uid}) eq "DEACT") {
		Broker::debugout(2,"Message from deactivated client ID $env->{uid} on $EPADDR rejected");
		sendresponse($cs,$env,"ERR","DEACTIVATED",undef);
		close($cs);
		return;
		}

	routemessage($cs,$env,$EPADDR);
	close($cs);
	}

# Route a verified message to its handler (protocol 6).
#
sub routemessage {
	my $cs = shift;
	my $env = shift;
	my $EPADDR = shift;
	my $lumy = $env->{lumy};
	my $action = $env->{action};
	my $uid = $env->{uid};
	my $data = $env->{data};

	if ($lumy eq "core") {
		if ($action eq "register") {
			if ($uid ne "0") {
				Broker::debugout(2,"Attempted registration from client with nonzero ID on $EPADDR");
				sendresponse($cs,$env,"ERR","INVALID_UID",undef);
				return;
				}
			# Data field validation (protocol 6.1).
			my $EPNAME = validstr($data->{hostname},'^[A-Za-z0-9_\.\-]+$');
			my $svrkey = validstr($data->{serverkey},'^[A-Za-z0-9]+$');
			my $EPFPNT = validstr($data->{fingerprint},'^[a-f0-9]{64}$');
			my $osplat = validstr($data->{osplat},'^[A-Za-z]+$');
			my $osrel = validstr($data->{osrel},'^[A-Za-z0-9\s\.\-]+$');
			my $clientver = validstr($data->{clientver},'^[0-9]+\.[0-9]+\.[0-9]+[ab]?$');
			$clientver = "Unknown" unless defined $clientver;
			my $ipv4 = validstr($data->{ipv4},'^[0-9]{1,3}(\.[0-9]{1,3}){3}$');
			my $pubder = defined $data->{pubkey} ? eval { decode_base64($data->{pubkey}) } : undef;
			my $pubraw = defined $pubder ? Luminum::Protocol::spki_to_raw($pubder) : undef;

			if (!$EPNAME || !$svrkey || !$EPFPNT || !$osplat || !$osrel || !$ipv4 || !defined $pubraw) {
				Broker::debugout(2,"Attempted registration with missing data from $EPADDR");
				sendresponse($cs,$env,"ERR","MISSING_DATA",undef);
				return;
				}
			if (serverkey($svrkey) != 1) {
				Broker::debugout(2,"Attempted registration with invalid server key from $EPADDR");
				sendresponse($cs,$env,"ERR","INVALID_SERVER_KEY",undef);
				return;
				}
			# The fingerprint must match the presented public key (3.1).
			if (Luminum::Protocol::fingerprint($pubraw) ne $EPFPNT) {
				Broker::debugout(2,"FINGERPRINT_MISMATCH: registration from $EPADDR rejected");
				sendresponse($cs,$env,"ERR","FINGERPRINT_MISMATCH",undef);
				return;
				}
			my $reg = isreg($EPFPNT);
			if ($reg > 0) {
				Broker::debugout(2,"Attempted registration from existing client on $EPADDR (ID $reg)");
				sendresponse($cs,$env,"ERR","ALREADY_REGISTERED",undef);
				return;
				}
			# Store the base64 SPKI/DER as sent (schema: PUBKEY is base64;
			# getpubkey() decodes it on read).
			newreg($cs,$env,$EPNAME,$EPFPNT,$data->{pubkey},$ipv4,$osplat,$osrel,$clientver,$EPADDR);
			return;
			}
		elsif ($action eq "checkin") {
			my $EPNAME = validstr($data->{hostname},'^[A-Za-z0-9_\.\-]+$');
			my $osplat = validstr($data->{osplat},'^[A-Za-z]+$');
			my $osrel = validstr($data->{osrel},'^[A-Za-z0-9\s\.\-]+$');
			my $clientver = validstr($data->{clientver},'^[0-9]+\.[0-9]+\.[0-9]+[ab]?$');
			$clientver = "Unknown" unless defined $clientver;
			my $ipv4 = validstr($data->{ipv4},'^[0-9]{1,3}(\.[0-9]{1,3}){3}$');
			if (!$EPNAME || !$osplat || !$osrel) {
				Broker::debugout(2,"Attempted check-in with missing data from $EPADDR");
				sendresponse($cs,$env,"ERR","MISSING_DATA",undef);
				return;
				}
			checkin($cs,$env,$uid,$ipv4,$EPNAME,$osplat,$osrel,$clientver,$EPADDR);
			return;
			}
		elsif ($action eq "unregister") {
			Broker::debugout(0,"Received deregistration request from client ID $uid on $EPADDR");
			dereg($cs,$env,$uid,$EPADDR);
			return;
			}
		elsif ($action eq "report") {
			# Unsolicited client report; event routing arrives with the
			# MQTT channel. Acknowledge for now.
			Broker::debugout(0,"Received report from client ID $uid on $EPADDR");
			sendresponse($cs,$env,"OK",undef,undef);
			return;
			}
		elsif ($action eq "answer") {
			# No action queue on the bootstrap channel yet (Phase 2).
			Broker::debugout(0,"Received answer from client ID $uid on $EPADDR");
			sendresponse($cs,$env,"OK",undef,undef);
			return;
			}
		elsif ($action eq "query" || $action eq "deploy" || $action eq "config") {
			# Server-to-client actions (protocol 6.1).
			Broker::debugout(2,"Client-originated $action received from $EPADDR (server-to-client action)");
			sendresponse($cs,$env,"ERR","INVALID_DIRECTION",undef);
			return;
			}
		else {
			Broker::debugout(2,"Invalid action \"$action\" specified for \"core\" Lumy in message from $EPADDR");
			sendresponse($cs,$env,"ERR","UNKNOWN_ACTION",undef);
			return;
			}
		}
	elsif ($action eq "newconfig") {
		lumyconf($cs,$env,$lumy,$uid,$EPADDR);
		return;
		}
	elsif (grep(/^$lumy$/,@lumys) && $data) {
		&{\&{"$lumy\::pass"}}($uid,$data);
		sendresponse($cs,$env,"OK",undef,undef);
		return;
		}
	else {
		Broker::debugout(2,"Invalid Lumy \"$lumy\" specified in message from $EPADDR");
		sendresponse($cs,$env,"ERR","UNKNOWN_LUMY",undef);
		return;
		}
	}

# Read one length-prefixed frame from a socket (protocol 8.2).
# Returns the decoded envelope hashref, or undef on failure.
#
sub readframe {
	my $cs = shift;
	my $max = shift;

	my $lenbuf = "";
	while (length($lenbuf) < 4) {
		my $rc = sysread($cs,$lenbuf,4 - length($lenbuf),length($lenbuf));
		if (!$rc) { return undef; }
		}
	my ($len) = unpack("N",$lenbuf);
	if ($len == 0 || $len > $max) { return undef; }
	my $payload = "";
	while (length($payload) < $len) {
		my $rc = sysread($cs,$payload,$len - length($payload),length($payload));
		if (!$rc) { return undef; }
		}
	my ($ok,$env) = Luminum::Protocol::frame_decode($lenbuf.$payload,$max);
	if (!$ok) { return undef; }
	return $env;
	}

# Build, sign, and write a framed response envelope (protocol 3.3, 5.1).
#
sub sendresponse {
	my $cs = shift;
	my $req = shift;
	my $status = shift;
	my $err = shift;
	my $data = shift;

	my $resp = Luminum::Protocol::new_envelope(
		src => "server",
		uid => $req->{uid},
		lumy => $req->{lumy},
		action => $req->{action},
		status => $status
		);
	$resp->{err} = $err if defined $err;
	$resp->{data} = $data if defined $data;
	Luminum::Protocol::sign_envelope($resp,$srvseed);
	my $frame = Luminum::Protocol::frame_encode($resp,64*1024);
	if (defined $frame) {
		syswrite($cs,$frame);
		}
	else { Broker::debugout(3,"Response frame exceeds maximum size; not sent"); }
	}

# Lumy configuration request (protocol 6.1: configuration is the
# server-side source of truth). Served from SYSTEM.LUMYCONFIG: an
# exact (LUMY, UID) row wins, falling back to the UID '0' default row.
#
sub lumyconf {
	my $cs = shift;
	my $env = shift;
	my $lumy = shift;
	my $uid = shift;
	my $EPADDR = shift;

	my $conf = getlumyconfig($lumy,$uid);
	if ($conf eq "") {
		Broker::debugout(2,"No configuration on file for \"$lumy\" Lumy (UID $uid) from $EPADDR");
		sendresponse($cs,$env,"ERR","NO_CONFIG",undef);
		return;
		}
	my $data = eval { JSON::PP->new->decode($conf) };
	if ($@ || !ref($data)) {
		Broker::debugout(3,"Stored configuration for \"$lumy\" Lumy is not valid JSON");
		sendresponse($cs,$env,"ERR","BAD_CONFIG",undef);
		return;
		}
	Broker::debugout(0,"Sent \"$lumy\" Lumy configuration to $EPADDR (UID $uid)");
	sendresponse($cs,$env,"OK",undef,$data);
	}

# Stored public key (base64 SPKI/DER) for a client UID.
#
sub getpubkey {
	my $uid = shift;
	my $pubkey;
	if ($uid =~ /^[0-9]+$/) {
		my $dbh = dbconnect("CLIENTS");
		my $sth = $dbh->prepare("select PUBKEY from AUTH where ID = '$uid'");
		$sth->execute();
		my @row = $sth->fetchrow_array();
		if (scalar(@row) > 0 && defined $row[0]) { $pubkey = $row[0]; }
		}
	return $pubkey;
	}

# Connection state for a client UID (OK, DEACT, ...).
#
sub getcstate {
	my $uid = shift;
	my $cstate;
	if ($uid =~ /^[0-9]+$/) {
		my $dbh = dbconnect("CLIENTS");
		my $sth = $dbh->prepare("select CSTATE from STATUS where ID = '$uid'");
		$sth->execute();
		my @row = $sth->fetchrow_array();
		if (scalar(@row) > 0 && defined $row[0]) { $cstate = $row[0]; }
		}
	return $cstate;
	}

# Lumy configuration row for (LUMY, UID), falling back to UID '0'.
#
sub getlumyconfig {
	my $lumy = shift;
	my $uid = shift;
	my $conf;
	if ($lumy =~ /^[a-z]+$/ && $uid =~ /^[0-9]+$/) {
		my $dbh = dbconnect("SYSTEM");
		my $sth = $dbh->prepare("select CONFIG from LUMYCONFIG where LUMY = '$lumy' and UID = '$uid'");
		$sth->execute();
		my @row = $sth->fetchrow_array();
		if (scalar(@row) > 0 && defined $row[0]) { $conf = $row[0]; }
		else {
			$sth = $dbh->prepare("select CONFIG from LUMYCONFIG where LUMY = '$lumy' and UID = '0'");
			$sth->execute();
			@row = $sth->fetchrow_array();
			if (scalar(@row) > 0 && defined $row[0]) { $conf = $row[0]; }
			}
		}
	return defined $conf ? $conf : "";
	}

# Validate a string field against a pattern; returns the value or undef.
#
sub validstr {
	my $val = shift;
	my $pat = shift;
	return undef unless defined $val && !ref($val) && $val =~ $pat;
	return $val;
	}

# Random bytes from /dev/urandom.
#
sub randombytes {
	my $n = shift;
	my $bytes;
	if (open(my $ur, "<", "/dev/urandom")) {
		read($ur,$bytes,$n);
		close($ur);
		}
	$bytes = join("",map { chr(int(rand(256))) } 1..$n) unless defined $bytes && length($bytes) == $n;
	return $bytes;
	}

# Check Server Key
#
# serverkey("X4U33MpgySchn5btKVUqTedO1bCn80LK");
#
sub serverkey {
	my $check = shift;
	my $goodkey;

	if ($check =~ /^[A-Za-z0-9]+$/) {
		my $dbh = dbconnect("SYSTEM");
		my $sth = $dbh->prepare("select CVAL from CONFIG where CKEY = 'SKEY'");
		$sth->execute();
		my @result = $sth->fetchrow_array();
		if ($check eq $result[0]) { $goodkey = 1; }
		else { $goodkey = 0; }
		}
	return $goodkey;
	}

# New Client Registration (protocol 7.1)
#
# 1 = Success
# 2 = Already Registered
# 3 = Error
#
sub newreg {
	my $cs = shift;
	my $env = shift;
	my $EPNAME = shift;
	my $EPFPNT = shift;
	my $EPPKEY = shift;
	my $ipv4 = shift;
	my $osplat = shift;
	my $osrel = shift;
	my $clientver = shift;
	my $EPADDR = shift;
	my $EPID;

	# MQTT client secret (protocol 3.1): 32 random bytes, base64.
	# Only the SHA-256 hash is stored server-side.
	my $secret = encode_base64(randombytes(32), "");
	my $sechash = sha256_hex($secret);

	my $dbh = dbconnect("CLIENTS");
	my $sth = $dbh->prepare("insert into AUTH (NAME,FINGERPRINT,PUBKEY,MQTTSECRET) values ('$EPNAME','$EPFPNT','$EPPKEY','$sechash')");
	$sth->execute();
	$sth = $dbh->prepare("select ID from AUTH where FINGERPRINT = '$EPFPNT'");
	$sth->execute();
	while (my @regdata = $sth->fetchrow()) { $EPID = $regdata[0]; }
	$sth = $dbh->prepare("insert into STATUS (ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,REGDATE,LASTSEEN) values ($EPID,'$EPNAME','$ipv4','$osplat','$osrel','$clientver','OK',now(),now())");
	$sth->execute();
	# MQTT: add the client's secret to the password_file and reload the broker
	# (protocol 7.1). A new OS value may have appeared, so regenerate the ACL.
	Luminum::MQTT::on_register($EPID, $secret, passwd_file => $MQTTPASSWD, pid_file => $MQTTPIDFILE);
	eval { Luminum::MQTT::regen_acl($dbh, sid => $SID, server_user => $MQTTUSER, acl_file => $MQTTACL, pid_file => $MQTTPIDFILE); };
	if ($@) { Broker::debugout(2,"Unable to regenerate the MQTT ACL file: $@"); }
	Broker::debugout(0,"Registered Client ID $EPID\: $EPNAME ($EPADDR)");

	sendresponse($cs,$env,"OK",undef,{
		uid => "$EPID",
		sid => $SID,
		mqtthost => $MADDR,
		mqttport => "$MPORT",
		mqttsecret => $secret,
		serverpubkey => $srvpubspki
		});
	}

# Client De-Registration (protocol 3.1): the record is deactivated,
# not deleted, so the fingerprint cannot be silently re-registered.
#
# 1 = Success
# 2 = Failure
# 3 = Error
#
sub dereg {
	my $cs = shift;
	my $env = shift;
	my $EPID = shift;
	my $EPADDR = shift;

	if ($EPID =~ /^[0-9]+$/) {
		my $dbh = dbconnect("CLIENTS");
		my $sth = $dbh->prepare("update STATUS set CSTATE = 'DEACT' where ID = $EPID");
		$sth->execute();
		# MQTT: remove the client's secret from the password_file and reload
		# the broker so it can no longer authenticate (protocol 3.1).
		Luminum::MQTT::on_deactivate($EPID, passwd_file => $MQTTPASSWD, pid_file => $MQTTPIDFILE);
		Broker::debugout(1,"Deactivated client ID $EPID on $EPADDR");
		sendresponse($cs,$env,"OK",undef,undef);
		}
	else {
		Broker::debugout(2,"Malformed UID in deregistration request from $EPADDR");
		sendresponse($cs,$env,"ERR","MALFORMED_UID",undef);
		}
	}

# Client Registration Check
#
# isreg("cfd346d21ef5690deb109beef");
#
# 0 = Not Registered
# 451 = Registered Endpoint ID
#
sub isreg {
	my $EPFPNT = shift;
	my $registered;

	if ($EPFPNT =~ /^[a-f0-9]+$/) {
		my $dbh = dbconnect("CLIENTS");
		my $sth = $dbh->prepare("select count(ID),ID from AUTH where FINGERPRINT = '$EPFPNT'");
		$sth->execute();
		while (my @row = $sth->fetchrow_array()) {
			if ($row[0] == 0) { $registered = 0; }
			else { $registered = $row[1]; }
			}
		return $registered;
		}
	else { Broker::debugout(2,"Invalid fingerprint provided for registration check."); }
	}

# Record Client Check-In (protocol 7.2). Identity is established by
# the per-message signature against the stored public key for the
# claimed UID, so no fingerprint is carried in the message.
#
sub checkin {
	my $cs = shift;
	my $env = shift;
	my $EPID = shift;
	my $ipv4 = shift;
	my $EPNAME = shift;
	my $osplat = shift;
	my $osrel = shift;
	my $clientver = shift;
	my $EPADDR = shift;

	if ($EPID =~ /^[0-9]+$/) {
		my $dbh = dbconnect("CLIENTS");
		my $sth;
		if (defined $ipv4) {
			$sth = $dbh->prepare("update STATUS set HOSTNAME = '$EPNAME', IPV4 = '$ipv4', OSPLATFORM = '$osplat', OSRELEASE = '$osrel', CLIENTVER = '$clientver', CSTATE = 'OK', LASTSEEN = now() where ID = $EPID");
			}
		else {
			$sth = $dbh->prepare("update STATUS set HOSTNAME = '$EPNAME', OSPLATFORM = '$osplat', OSRELEASE = '$osrel', CLIENTVER = '$clientver', CSTATE = 'OK', LASTSEEN = now() where ID = $EPID");
			}
		$sth->execute();
		Broker::debugout(0,"Received check-in from client on $EPADDR (ID $EPID)");
		sendresponse($cs,$env,"OK",undef,undef);
		}
	else {
		Broker::debugout(2,"Malformed UID in check-in from $EPADDR");
		sendresponse($cs,$env,"ERR","MALFORMED_UID",undef);
		}
	}

# Break Handler
#
sub catchbreak {
	$suerror = 0;
	if ($broken == 0) {
		Broker::debugout (2,"Caught SIGINT! Shutting down...");
		$broken = 1;
		if ($workerpid) { kill("TERM", $workerpid); }
		stopweb();
		stoplistener();
		stopserver();
		exit 0;
		}
	}

# HUP Handler
#
sub catchhup {
	if ($hupped == 0) {
		Broker::debugout (2,"Caught SIGHUP! Reloading Server...");
		$hupped = 1;
		undef($SID);
		undef($SKEY);
		undef($SHOST);
		undef($LADDR);
		undef($LPORT);
		undef($MADDR);
		undef($MPORT);
		undef($CMDTIMEOUT);
		undef($DEPLTIMEOUT);
		undef($sslcert);
		undef($sslprvkey);
		undef($sslpubkey);
		undef($srvseed);
		undef($srvpub);
		undef($srvpubspki);
		%seenid = ();
		stoplistener();
		getbrokerconf();
		readconfig();
		sleep 1;
		lumyload();
		setuplistener();
		startlistener();
		}
	}

package Broker;

use POSIX qw(strftime);
use Term::ANSIColor;

# Debugging Output
#
sub debugout {
	my $DBOUT;
	my $DBFLAG;
	my $DBCFLAG;
	my $DBLVL = $_[0];
	my $DBMSG = $_[1];
	my $DBTIME = strftime('%Y-%m-%d %H:%M:%S',localtime);

	if ($DBLVL eq "0") {
		$DBFLAG = "INFO";
		$DBCFLAG = colored("INFO","cyan");
		}
	elsif ($DBLVL eq "1") {
		$DBFLAG = " OK ";
		$DBCFLAG = colored(" OK ","green");
		}
	elsif ($DBLVL eq "2") {
		$DBFLAG = "WARN";
		$DBCFLAG = colored("WARN","yellow");
		}
	elsif ($DBLVL eq "3") {
		$DBFLAG = "FAIL";
		$DBCFLAG = colored("FAIL","red");
		}

	if ($main::writelog == 1) {
		open (BLOG, "+>>", $main::brokerlog);
		print BLOG "[$DBTIME] [$DBFLAG] $DBMSG\n";
		close (BLOG);
		}

	# Break signals are usually caused by a CTRL+C. This is here to
	# print a newline to stdout after the break to keep the debug
	# stream output tidy.
	if ($main::debug == 1) {
		if ($DBMSG =~ /SIGINT/) { print "\n"; }
		print "[$DBTIME] [$DBCFLAG] $DBMSG\n";
		}
	}
