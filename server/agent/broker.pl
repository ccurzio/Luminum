#!/usr/bin/perl -w
#
# Luminum Server Broker v0.0.1
# by Christopher R. Curzio (ccurzio@luminum.net)

use strict;
use Getopt::Long;
use Cwd qw(abs_path);
use FindBin qw($Bin);
use POSIX qw(strftime);
use Time::HiRes ("usleep");
use Term::ANSIColor;
use DBI;
use Data::UUID;
use MIME::Base64;
#use threads;
#use Socket;
#use IO::Socket;
use IO::Socket::SSL;
#use IO::Select;
use Crypt::OpenSSL::RSA;
use Crypt::Mode::CBC;
use JSON;
use Data::Dumper;

#$| = 1;

my $debug;
my $suerror;
my $logdir;
my $brokerlog;
my $dbuser;
my $dbpass;
my %attr;
my $SID;
my $SHOST;
my $LADDR;
my $LPORT;
my $SKEY;
my $sslcert;
my $sslprvkey;
my $sslpubkey;
my $privatekey;
my $sock;

my $listen = 1;
my $client_data = "";

$suerror = 0;

my $broken = 0;
my $hupped = 0;
$SIG{INT} = \&catchbreak;
$SIG{HUP} = \&catchhup;

# Where Am I? (Establish Filesystem Location)
#
my $brokerpath = abs_path($0);
my $brokername = $brokerpath;
$brokername =~ s/^(\/.*\/)//;
$brokerpath =~ s/\/$brokername//;

# Read Broker Configuration
#
if (-e "$brokerpath\/config") {
	# Check for Broker Configuration
	if (-e "$brokerpath\/config\/broker.conf") {
		open (BCONF, "$brokerpath\/config\/broker.conf");
		foreach (<BCONF>) {
			next if ($_ =~ /^#.*$/);
			if ($_ =~ /^LOGDIR[\s|\t]?+\=[\s|\t]?+(.*)$/) {
				mkdir($1, 0700) unless(-d $1 );
				$brokerlog = "$1\/broker.log";
				}
			elsif ($_ =~ /^DEBUG[\s|\t]?+\=[\s|\t]?+([0|1])$/) { $debug = $1; }
			elsif ($_ =~ /^DBUSER[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbuser = $1; }
			elsif ($_ =~ /^DBPASS[\s|\t]?+\=[\s|\t]?+(.*)$/) { $dbpass = $1; }
			}
		close (BCONF);
		}
	else { die "FATAL: Broker Configuration Missing: $brokerpath\/config\/broker.conf"; }
	}
else { die "FATAL: Configuration Directory Missing: $brokerpath\/config\n"; }

if (!$dbuser || $dbuser eq "") { die "FATAL: Database user not specified in config.\n"; }

debugout(0,"Server Startup");
startserver();
startweb();
dereg("c26346ed3e2e4964ac45c22afa7ea342");
setuplistener();

debugout(1,"Server startup complete.");
debugout(0,"- Luminum Server ID: $SID");
debugout(0,"- Web Console: https://$SHOST");
debugout(0,"- Broker Log: $brokerlog");
debugout(0,"- Listening on $LADDR:$LPORT");

startlistener();

# Luminum Server Initialization
#
sub startserver {
	my $dbstat = `/usr/bin/systemctl status mysqld | /usr/bin/grep Active`;
	if ($dbstat =~ /inactive/) {
		debugout(0,"Initializing Database...");
		system("/usr/bin/systemctl start mysqld");
		if (`/usr/bin/systemctl status mysqld | /usr/bin/grep Active` =~ /inactive/) {
			debugout(3,"Database initialization failed: Unable to start service.");
			exit 1;
			}
		}
	elsif ($dbstat =~ /running/) { debugout(0,"Database service is already running. Validating..."); }
	else {
		debugout(3,"Unable to determine database service state. Aborting.");
		exit 1;
		}

	my $dbsock = `/usr/bin/grep socket /etc/mysql/my.cnf | /usr/bin/grep -v "#" | /usr/bin/sed -e 's/^socket.*= \\\//\\\//'`;
	chomp($dbsock);
	if (!-e $dbsock || $dbsock eq "") {
		debugout(3,"Database initialization failed: Unable to validate local socket.");
		exit 1;
		}
	else { debugout(0,"Validated local database socket: $dbsock"); }

	%attr = (
		PrintError=>0,
		RaiseError=>1
		);

	my $dbpid = `/usr/bin/cat /var/run/mysqld/mysqld.pid`;
	chomp ($dbpid);
	debugout(1,"Database initialized successfully. (PID $dbpid)");
	readconfig();
	}

# Luminum Server Shutdown
#
sub stopserver {
	debugout(0,"Stopping database...");
	system("/usr/bin/systemctl stop mysqld");
	if (`/usr/bin/systemctl status mysqld | /usr/bin/grep Active` =~ /inactive/) { debugout(1,"Database stopped successfully."); }
	else {
		$suerror = 1;
		debugout(2,"Clean stop of database failed!");
		}
	if ($suerror == 0) { debugout(1,"Server shutdown complete."); }
	else { debugout(2,"Server shutdown completed with errors."); }
	}

# Start Web Server
#
sub startweb {
	if (`/usr/bin/systemctl status nginx | /usr/bin/grep Active` =~ /inactive/) {
		debugout(0,"Initializing webserver...");
		system("/usr/bin/systemctl start nginx");
		if (`/usr/bin/systemctl status nginx | /usr/bin/grep Active` =~ /inactive/) {
			debugout(3,"Webserver initialization failed: Unable to start service.");
			}
		else {
			my $wspid = `/usr/bin/cat /var/run/nginx.pid`;
			chomp ($wspid);
			debugout(1,"Webserver initialized successfully. (PID $wspid)");
			}
		}
	}

# Stop Web Server
#
sub stopweb {
	debugout(0,"Stopping webserver...");
	system("/usr/bin/systemctl stop nginx");
	if (`/usr/bin/systemctl status nginx | /usr/bin/grep Active` =~ /inactive/) { debugout(1,"Webserver stopped successfully."); }
	else {
		$suerror = 1;
		debugout(2,"Unable to stop webserver.");
		}
	}

# Set Up Network Listener
#
sub setuplistener {
	debugout(0,"Initializing Network Listener...");
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
		debugout(3,"Network Listener could not be initialized: $SSL_ERROR");
		$suerror = 1;
		stopserver();
		exit 1;
		};
	if ($sock) { debugout(1,"Network Listener initialized successfully."); }
	if ($hupped == 1) {
		debugout(1,"Reload Complete.");
		$hupped = 0;
		}
	}

# Start Network Listener
#
sub startlistener {
	$listen = 1;
	my $buf = "";
	my $rc;
	while($listen == 1) {
		my $client_socket = $sock->accept() or do { debugout(2,"Client connection failed: $!"); };
		my $client_address = $client_socket->peerhost();
		my $client_port = $client_socket->peerport();
		debugout(0,"Inbound connection from $client_address:$client_port");
		do { $rc = sysread($client_socket, $client_data, 65*1024, length($client_data)); } while ($rc);
		parsedata($client_address,$client_data);
		debugout(0,"Connection with $client_address closed.");
		}
	}

# Stop Network Listener
#
sub stoplistener {
	debugout(0,"Stopping Network Listener...");
	$listen = 0;
	close($sock);
	undef($sock);
	if (!$sock) { debugout(1,"Network Listener stopped successfully."); }
	else {
		debugout(3,"Unable to stop Network Listener. Retrying in 3 seconds...");
		sleep(3);
		close($sock);
		if (!$sock) { debugout(1,"Network Listener stopped successfully."); }
		else { debugout(3,"Retry failed. Forcing shutdown."); }
		}
	}

# Read Server Configuration
#
sub readconfig {
	debugout(0,"Reading Server Configuration...");
	my $dbh = DBI->connect("DBI:mysql:SYSTEM",$dbuser,$dbpass,\%attr);
	my $sth = $dbh->prepare("select table_name from information_schema.tables where table_schema = 'SYSTEM' and table_name = 'CONFIG'");
	$sth->execute();
	if ($sth->rows == 0) {
		debugout(3,"Server configuration does not exist! (Run with --setup)");
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
			elsif ($row[0] eq "SSLCERT") { $sslcert = $row[1]; }
			elsif ($row[0] eq "SSLPRVKEY") { $sslprvkey = $row[1]; }
			elsif ($row[0] eq "SSLPUBKEY") { $sslpubkey = $row[1]; }
			}
		}

	if (!$SID || $SID eq "") {
		debugout(3,"Undefined Server ID! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$SKEY || $SKEY eq "") {
		debugout(3,"Undefined Server Key! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$SID || $SID eq "") {
		debugout(3,"Undefined Server Key! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$SHOST || $SHOST eq "") {
		debugout(3,"Undefined Server Hostname! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$LADDR || $LADDR eq "") {
		debugout(3,"Undefined Network Listener Address! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$LPORT || $LPORT eq "") {
		debugout(3,"Undefined Network Listener Port! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	elsif($LPORT !~ /^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$/) {
		debugout(3,"Invalid Network Listener Port: $LPORT");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$sslprvkey || $sslprvkey eq "") {
		debugout(3,"Server private key file is not configured! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	elsif (!-e $sslprvkey) {
		debugout(3,"Server private key file is missing: $sslprvkey");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	else {
		my $readkey;
		open(PK, $sslprvkey) or do {
			debugout(3,"Failure reading private key from: $sslprvkey");
			$suerror = 1;
			stopserver();
			exit 1;
			};
		while(<PK>) { $readkey .= $_; }
		close(PK);
		$privatekey = Crypt::OpenSSL::RSA->new_private_key($readkey);
		}
	if (!$sslpubkey || $sslpubkey eq "") {
		debugout(3,"Server public key file is not configured! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	elsif (!-e $sslpubkey) {
		debugout(3,"Server public key file is missing: $sslpubkey");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	if (!$sslcert || $sslcert eq "") {
		debugout(3,"Server certificate is not configured! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	elsif (!-e $sslcert) {
		debugout(3,"Server certificate is missing: $sslcert");
		$suerror = 1;
		stopserver();
		exit 1;
		}

	debugout(1,"Configuration Successfully Imported.");
	debugout(0,"- SSL Certificate: $sslcert");
	debugout(0,"- SSL Private Key File: $sslprvkey");
	debugout(0,"- SSL Public Key File: $sslpubkey");
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

	if ($ckey =~ /^[A-Z]+$/ && $cval =~ /^[A-Za-z0-9_\.\/]+$/) {
		if ($ckey eq "LPORT" && $cval !~ /^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$/) {
			debugout(2,"Invalid value specified for configuration change to LPORT: \"$cval\"");
			$scstat = 2;
			}
		else {
			my $dbh = DBI->connect("DBI:mysql:SYSTEM",$dbuser,$dbpass,\%attr);
			my $sth = $dbh->prepare("update CONFIG set CVAL = '$cval' where CKEY = '$ckey'");
			$sth->execute();
			}
		}
	return $scstat;
	}

# Endpoint Fingerprint Validation
# iafis("451","cfd346d21ef5690deb109beef");
#
# 1 = Match
# 2 = Mismatch
# 3 = Error
#
sub iafis {
	my $EPID = $_[0];
	my $EPFPNT = $_[1];
	my $fvstat;

	if ($EPID =~ /^[0-9]+$/) {
		if ($EPFPNT =~ /^[a-f0-9]+$/) {
			my $dbh = DBI->connect("DBI:mysql:CLIENTS",$dbuser,$dbpass,\%attr);
			my $sth = $dbh->prepare("select FINGERPRINT from AUTH where ID = '$EPID'");
			$sth->execute();
			if ($sth->rows > 0) {
				my @result = $sth->fetchrow_array();
				if ($EPFPNT eq $result[0]) { $fvstat = 1; }
				else { $fvstat = 2; }
				}
			else { $fvstat = 2; }
			}
		else { $fvstat = 3; }
		}
	else { $fvstat = 3; }

	return $fvstat;
	}

# Client Data Handling
#
sub parsedata {
	my $EPADDR = $_[0];
	my $input = $_[1];
	my $message;
	my $EPID;
	my $EPNAME;
	my $EPFPNT;
	my $action;
	my $data;
	my $osplat;
	my $osrel;
	my $EPKEY;
	my $clientver;

	eval { decode_json($input) };
	if ($@) { debugout(2,"Malformed message received from $EPADDR"); }
	#else { $message = decode_json(decode_base64($input)); }
	else {
		my $decpkg = decode_json($input);
		my $aeskey = $privatekey->decrypt(decode_base64($decpkg->{'key'}));
		my $iv = $decpkg->{'spins'};
		my $c = Crypt::Mode::CBC->new('AES');
		my $dcmessage = $c->decrypt(decode_base64($decpkg->{'contents'}),$aeskey,$iv);
		$message = decode_json(decode_base64($dcmessage));
		}
	$client_data = "";

	for my $mkey (keys %$message) {
		if ($mkey eq "info") {
			if ($message->{$mkey}{'ID'} == 0) { $EPID = 0; }
			elsif ($message->{$mkey}{'ID'} =~ /^[1-9]([0-9]+)?$/) { $EPID = $message->{$mkey}{'ID'}; }
			if ($message->{$mkey}{'name'} =~ /^[A-Za-z0-9_\.]+$/) { $EPNAME = $message->{$mkey}{'name'}; }
			if ($message->{$mkey}{'fingerprint'} =~ /^[a-f0-9]+$/) { $EPFPNT = $message->{$mkey}{'fingerprint'}; }
			}
		elsif ($mkey eq "action") {
			if ($message->{$mkey} =~ /^[A-Za-z]+$/) { $action = $message->{$mkey}; }
			}
		elsif ($mkey eq "data") {
			##############################################
			####### REPLACE WITH BASE64 VALIDATION #######
			if (1 == 1) { $data = $message->{'data'}; }
			##############################################
			}
		}

	if ($EPFPNT && $EPFPNT ne "") {
		if ($EPID == 0) {
			if ($action eq "register") {
				my $svrkey;
				if ($message->{'info'}{'serverkey'} =~ /^[A-Za-z0-9]+$/) { $svrkey = $message->{'info'}{'serverkey'}; }
				if ($message->{'info'}{'osplat'} =~ /^[A-Za-z]+$/) { $osplat = $message->{'info'}{'osplat'}; }
				if ($message->{'info'}{'osrel'} =~ /^[A-Za-z0-9\s\.]+$/) { $osrel = $message->{'info'}{'osrel'}; }
				if ($message->{'info'}{'clientver'} =~ /^[0-9][0-9]?\.[0-9][0-9]?\.[0-9][0-9]?[ab]?$/) { $clientver = $message->{'info'}{'clientver'}; }
				else { $clientver = "Unknown"; }
				if ($message->{'info'}{'pubkey'} =~ /^[A-Za-z0-9\-\/\+\s\n]+$/) { $EPKEY = $message->{'info'}{'pubkey'}; }

				if (serverkey($svrkey) == 1) {
					if ($EPFPNT && $EPKEY && $EPADDR && $EPNAME && $osplat && $osrel && $clientver) {
						newreg($EPNAME,$EPFPNT,$EPKEY,$EPADDR,$osplat,$osrel,$clientver);
						}
					else { debugout(2,"Attempted registration with missing data from $EPADDR\."); }
					}
				else { debugout(2,"Attempted registration with invalid server key from $EPADDR\."); }
				}
			else { debugout(2,"Message from unregistered client at $EPADDR\."); }
			}
		else {
			my $fpval = iafis($EPID,$EPFPNT);
			if ($fpval == 1) {
				if ($action eq "ping") {
					if ($message->{'info'}{'osplat'} && $message->{'info'}{'osrel'} && $message->{'info'}{'clientver'}) {
						my $osplat;
						my $osrel;
						my $clientver;
						if ($message->{'info'}{'osplat'} =~ /^[A-Za-z]+$/) { $osplat = $message->{'info'}{'osplat'}; }
						if ($message->{'info'}{'osrel'} =~ /^[A-Za-z0-9\s\.]+$/) { $osrel = $message->{'info'}{'osrel'}; }
						if ($message->{'info'}{'clientver'} =~ /^[0-9][0-9]?\.[0-9][0-9]?\.[0-9][0-9]?[ab]?$/) { $clientver = $message->{'info'}{'clientver'}; }
						else { $clientver = "Unknown"; }

						if ($EPID && $EPFPNT && $EPADDR && $EPNAME && $osplat && $osrel && $clientver) {
							checkin($EPID,$EPFPNT,$EPADDR,$EPNAME,$osplat,$osrel,$clientver);
							}
						else { debugout(2,"Malformed data in check-in from $EPADDR\."); }
						}
					else { debugout(2,"Attempted check-in with missing data from $EPADDR\."); }
					}
				elsif ($action eq "register") { debugout(2,"Attempted registration from client with nonzero ID on $EPADDR\."); }
				elsif ($action eq "unregister") {
					debugout(0,"Received deregistration request from client ID $EPID\.");
					dereg($EPFPNT);
					}
				elsif ($action eq "answer") {
					}
				elsif ($action eq "report") {
					}
				else { debugout(2,"Malformed message received from $EPADDR"); }
				}
			elsif ($fpval == 2) {
				debugout(2,"Fingerprint validation failed for client on $EPADDR\: Mismatch");
				}
			elsif ($fpval == 3) {
				debugout(2,"Fingerprint validation failed for client on $EPADDR\: Malformed Fingerprint");
				}
			else { debugout(2,"Unknown error during fingerprint validation for client on $EPADDR\."); }
			}
		}
	else { debugout(2,"Fingerprint missing in message from $EPADDR\."); }
	}

# Check Server Key
#
# serverkey("X4U33MpgySchn5btKVUqTedO1bCn80LK");
#
sub serverkey {
	my $check = shift;
	my $goodkey;

	if ($check =~ /^[A-Za-z0-9]+$/) {
		my $dbh = DBI->connect("DBI:mysql:SYSTEM",$dbuser,$dbpass,\%attr);
		my $sth = $dbh->prepare("select CVAL from CONFIG where CKEY = 'SKEY'");
		$sth->execute();
		my @result = $sth->fetchrow_array();
		if ($check eq $result[0]) { $goodkey = 1; }
		else { $goodkey = 0; }
		}
	return $goodkey;
	}

# New Client Registration
#
# newreg("tango","cfd346d21ef5690deb109beef",<KEYDATA>,"172.16.0.1","Linux","Debian 12.10","0.0.1");
#
# 1 = Success
# 2 = Already Registered
# 3 = Error
#
sub newreg {
	my $EPNAME = $_[0];
	my $EPFPNT = $_[1];
	my $EPPKEY = $_[2];
	my $EPADDR = $_[3];
	my $osplat = $_[4];
	my $osrel = $_[5];
	my $clientver = $_[6];
	my $EPID;
	my $reg = isreg($EPFPNT);

	if ($reg == 0) {
		my $dbh = DBI->connect("DBI:mysql:CLIENTS",$dbuser,$dbpass,\%attr);
		my $sth = $dbh->prepare("insert into AUTH (NAME,FINGERPRINT,PUBKEY) values ('$EPNAME','$EPFPNT','$EPPKEY')");
		$sth->execute();
		$sth = $dbh->prepare("select ID from AUTH where FINGERPRINT = '$EPFPNT'");
		$sth->execute();
		while (my @regdata = $sth->fetchrow()) { $EPID = $regdata[0]; }
		$sth = $dbh->prepare("insert into STATUS (ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,REGDATE,LASTSEEN) values ($EPID,'$EPNAME','$EPADDR','$osplat','$osrel','$clientver','OK',now(),now())");
		$sth->execute();
		debugout(0,"Registered Client ID $EPID\: $EPNAME ($EPADDR)");
		}
	else {
		debugout(2,"Attempted registration from existing client on $EPADDR (ID $reg)");
		}
	}

# Client De-Registration
#
# dereg("cfd346d21ef5690deb109beef");
#
# 1 = Success
# 2 = Failure
# 3 = Error
#
sub dereg {
	my $EPFPNT = shift;
	my $deregistered;

	if ($EPFPNT =~ /^[a-f0-9]+$/) {
		my $cid = isreg($EPFPNT);
		if ($cid > 0) {
			my $dbh = DBI->connect("DBI:mysql:CLIENTS",$dbuser,$dbpass,\%attr);
			my $sth = $dbh->prepare("delete CA, CS from AUTH CA join STATUS CS on CS.ID = CA.ID where CS.ID = $cid");
			$sth->execute();
			if (isreg($EPFPNT) == 0) {
				debugout(1,"Successfully unregistered client ID $cid\.");
				$deregistered = 1;
				}
			else {
				debugout(2,"Failure while attempting to unregister client ID $cid\.");
				$deregistered = 2;
				}
			}
		else {
			debugout(2,"Request to delete unregistered client with fingerprint $EPFPNT");
			$deregistered = 3;
			}
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
		my $dbh = DBI->connect("DBI:mysql:CLIENTS",$dbuser,$dbpass,\%attr);
		my $sth = $dbh->prepare("select count(ID),ID from AUTH where FINGERPRINT = '$EPFPNT'");
		$sth->execute();
		while (my @row = $sth->fetchrow_array()) {
			if ($row[0] == 0) { $registered = 0; }
			else { $registered = $row[1]; }
			}
		return $registered;
		}
	else { debugout(2,"Invalid fingerprint provided for registration check."); }
	}

# Record Client Check-In
#
sub checkin {
	my $EPID = $_[0];
	my $EPFPNT = $_[1];
	my $EPADDR = $_[2];
	my $EPNAME = $_[3];
	my $osplat = $_[4];
	my $osrel = $_[5];
	my $clientver = $_[6];

	if ($EPID =~ /^[0-9]+$/) {
		if (isreg($EPFPNT) eq $EPID) {
			my $dbh = DBI->connect("DBI:mysql:CLIENTS",$dbuser,$dbpass,\%attr);
			my $sth = $dbh->prepare("update STATUS set HOSTNAME = '$EPNAME', IPV4 = '$EPADDR', OSPLATFORM = '$osplat', OSRELEASE = '$osrel', CLIENTVER = '$clientver', CSTATE = 'OK', LASTSEEN = now() where ID = $EPID");
			$sth->execute();
			debugout(0,"Received check-in from client on $EPADDR (ID $EPID)");
			}
		else {
			debugout(2,"Attempted check-in from unregistered client at $EPADDR");
			}
		}
	}

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

	open (BLOG, "+>>", $brokerlog);
	print BLOG "[$DBTIME] [$DBFLAG] $DBMSG\n";

	# Break signals are usually caused by a CTRL+C. This is here to
	# print a newline to stdout after the break to keep the debug
	# stream output tidy.
	#
	# This will probably need to eventually be changed from == 1
	# to > 0 to handle debug levels.
	if ($debug == 1) {
		if ($DBMSG =~ /SIGINT/) { print "\n"; }
		print "[$DBTIME] [$DBCFLAG] $DBMSG\n";
		}
	close (BLOG);
	}

# Break Handler
#
sub catchbreak {
	$suerror = 0;
	if ($broken == 0) {
		debugout (2,"Caught SIGINT! Shutting down...");
		$broken = 1;
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
		debugout (2,"Caught SIGHUP!");
		$hupped = 1;
		undef($SID);
		undef($SKEY);
		undef($SHOST);
		undef($LADDR);
		undef($LPORT);
		undef($sslcert);
		undef($sslprvkey);
		undef($sslpubkey);
		readconfig();
		stoplistener();
		sleep 1;
		setuplistener();
		startlistener();
		}
	}
