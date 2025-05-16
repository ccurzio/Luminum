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
use threads;
use Socket;
use IO::Socket;
use IO::Socket::SSL;
use IO::Select;
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
my $sslkey;

$suerror = 0;

my $broken = 0;
$SIG{INT} = \&catchbreak;

# Establish Filesystem Location
#
my $brokerpath = abs_path($0);
my $brokername = $brokerpath;
$brokername =~ s/^(\/.*\/)//;
$brokerpath =~ s/\/$brokername//;

# Read Broker Config
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

debugout(0,"Starting Network Listener...");
my $sock = IO::Socket::SSL->new(
	LocalAddr => $LADDR,
	LocalPort => $LPORT,
	Proto => 'tcp',
	Listen => 20,
	SSL_hostname => $SHOST,
	SSL_cert_file => $sslcert,
	SSL_key_file => $sslkey
	)
or do {
	debugout(3,"Network Listener could not be started: $SSL_ERROR");
	$suerror = 1;
	stopserver();
	exit 1;
	};
if ($sock) { debugout(1,"Network Listener started successfully."); }

debugout(1,"Server startup complete.");
debugout(0,"- Luminum Server ID: $SID");
debugout(0,"- Broker Log: $brokerlog");
debugout(0,"- Listening on $LADDR:$LPORT");

my $buf = "";
my $rc;
my $client_data = "";
while(1) {
	my $client_socket = $sock->accept() or do {
		debugout(2,"Client connection failed: $!");
		};
	my $client_address = $client_socket->peerhost();
	my $client_port = $client_socket->peerport();
	debugout(0,"Inbound connection from $client_address:$client_port");
	do { $rc = sysread($client_socket, $client_data, 65*1024, length($client_data)); } while ($rc);
	parsedata($client_address,$client_data);
	debugout(0,"Connection with $client_address closed.");
	}

# Server Initialization
#
sub startserver {
	if (`/usr/bin/systemctl status mysqld | /usr/bin/grep Active` =~ /inactive/) {
		debugout(0,"Initializing Database...");
		system("/usr/bin/systemctl start mysqld");
		if (`/usr/bin/systemctl status mysqld | /usr/bin/grep Active` =~ /inactive/) {
			debugout(3,"Database initialization failed: Unable to start service.");
			exit 1;
			}
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

# Stop Server
#
sub stopserver {
	if (1 == 0) { stoplistener(); }
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

sub stopweb {
	debugout(0,"Stopping webserver...");
	system("/usr/bin/systemctl stop nginx");
	if (`/usr/bin/systemctl status nginx | /usr/bin/grep Active` =~ /inactive/) { debugout(1,"Webserver stopped successfully."); }
	else {
		$suerror = 1;
		debugout(2,"Clean stop of webserver failed!");
		}
	}

# Stop Network Listener
#
sub stoplistener {
	debugout(0,"Stopping Network Listener...");
	close($sock);
	debugout(1,"Network Listener stopped successfully.");
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
			elsif ($row[0] eq "SSLKEY") { $sslkey = $row[1]; }
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
	if (!$sslkey || $sslkey eq "") {
		debugout(3,"Server key file is not configured! (Run with --setup)");
		$suerror = 1;
		stopserver();
		exit 1;
		}
	elsif (!-e $sslkey) {
		debugout(3,"Server key file is missing: $sslcert");
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
	debugout(0,"- SSL Key File: $sslkey");
	}

# Set Server Configuration Options
#
sub setconfig {
	my $ckey = $_[0];
	my $cval = $_[1];

	if ($ckey =~ /^[A-Z]+$/ && $cval =~ /^[A-Za-z0-9_\.\/]+$/) {
		my $dbh = DBI->connect("DBI:mysql:SYSTEM",$dbuser,$dbpass,\%attr);
		my $sth = $dbh->prepare("update CONFIG set CVAL = '$cval' where CKEY = '$ckey'");
		$sth->execute();
		}
	}

# Handle Client Connections
#
sub parsedata {
	my $ihost = $_[0];
	my $input = $_[1];
	my $message;
	my $EPID;
	my $EPNAME;
	my $EPFPNT;
	my $function;
	my $data;
	my $osplat;
	my $osrel;
	my $epkey;
	my $clientver;

	eval { decode_json($input) };
	if ($@) { debugout(2,"Malformed message received from $ihost"); }
	else { $message = decode_json($input); }
	$client_data = "";

	for my $mkey (keys %$message) {
		if ($mkey eq "info") {
			if ($message->{$mkey}{'ID'} =~ /^[0-9]+$/) { $EPID = $message->{$mkey}{'ID'}; }
			if ($message->{$mkey}{'name'} =~ /^[A-Za-z0-9_\.]+$/) { $EPNAME = $message->{$mkey}{'name'}; }
			if ($message->{$mkey}{'fingerprint'} =~ /^[a-f0-9]+$/) { $EPFPNT = $message->{$mkey}{'fingerprint'}; }
			}
		elsif ($mkey eq "function") {
			if ($message->{$mkey} =~ /^[A-Za-z]+$/) { $function = $message->{$mkey}; }
			}
		elsif ($mkey eq "data") {
			# REPLACE WITH BASE64 VALIDATION
			if (1 == 1) { $data = $message->{'data'}; }
			}
		}

	if ($EPFPNT ne "") {
		if (!$EPID || $EPID eq "") {
			if ($function eq "register") {
				if ($message->{'info'}{'osplat'} =~ /^[A-Za-z]+$/) { $osplat = $message->{'info'}{'osplat'}; }
				if ($message->{'info'}{'osrel'} =~ /^[A-Za-z0-9\s\.]+$/) { $osrel = $message->{'info'}{'osrel'}; }
				if ($message->{'info'}{'clientver'} =~ /^[0-9][0-9]?\.[0-9][0-9]\.[0-9][0-9]$/) { $clientver = $message->{'info'}{'clientver'}; }

				if ($EPFPNT && $epkey && $ihost && $EPNAME && $osplat && $osrel && $clientver) {
					newreg($EPNAME,$EPFPNT,$epkey,$ihost,$osplat,$osrel,$clientver);
					}
				}
			else {
				debugout(2,"Message from unregistered client at $ihost\.");
				}
			}
		else {
			if ($function eq "answer") {
				}
			elsif ($function eq "update") {
				}
			elsif ($function eq "ping") {
				my $osplat;
				my $osrel;
				my $clientver;
				if ($message->{'info'}{'osplat'} =~ /^[A-Za-z]+$/) { $osplat = $message->{'info'}{'osplat'}; }
				if ($message->{'info'}{'osrel'} =~ /^[A-Za-z0-9\s\.]+$/) { $osrel = $message->{'info'}{'osrel'}; }
				if ($message->{'info'}{'clientver'} =~ /^[0-9][0-9]?\.[0-9][0-9]\.[0-9][0-9]$/) { $clientver = $message->{'info'}{'clientver'}; }

				if ($EPID && $EPFPNT && $ihost && $EPNAME && $osplat && $osrel && $clientver) {
					checkin($EPID,$EPFPNT,$ihost,$EPNAME,$osplat,$osrel,$clientver);
					}
				}
			}
		}
	else {
		debugout(2,"Fingerprint missing in message from $ihost\.");
		}
	}

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

	if ($reg eq "false") {
		my $dbh = DBI->connect("DBI:mysql:CLIENTS",$dbuser,$dbpass,\%attr);
		my $sth = $dbh->prepare("insert into AUTH (NAME,FINGERPRINT,PUBKEY) values ('$EPNAME','$EPFPNT','$EPPKEY')");
		$sth->execute();
		$sth = $dbh->prepare("select ID from AUTH where FINGERPRINT = '$EPFPNT'");
		$sth->execute();
		while (my @regdata = $sth->fetchrow()) { $EPID = $regdata[0]; }
		$sth = $dbh->prepare("insert into STATUS (ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,REGDATE,LASTSEEN) values ($EPID,'$EPNAME','$EPADDR','$osplat','$osrel','$clientver','OK',now(),now())");
		$sth->execute();
		debugout(0,"New client registration (ID $EPID)");
		}
	else {
		debugout(2,"Attempted registration from existing client (ID $reg)");
		}
	}

sub isreg {
	my $EPFPNT = shift;
	my $registered;

	if ($EPFPNT =~ /^[a-f0-9]+$/) {
		my $dbh = DBI->connect("DBI:mysql:CLIENTS",$dbuser,$dbpass,\%attr);
		my $sth = $dbh->prepare("select count(ID),ID from AUTH where FINGERPRINT = '$EPFPNT'");
		$sth->execute();
		while (my @row = $sth->fetchrow_array()) {
			if ($row[0] == 0) { $registered = "false"; }
			else { $registered = $row[1]; }
			}
		return $registered;
		}
	}

# Client Check-In
#
sub checkin {
	my $EPID = $_[0];
	my $EPFPNT = $_[1];
	my $EPADDR = $_[2];
	my $EPNAME = $_[3];
	my $osplat = $_[4];
	my $osrel = $_[5];
	my $clientver = $_[6];

	if (isreg($EPFPNT) eq $EPID) {
		my $dbh = DBI->connect("DBI:mysql:CLIENTS",$dbuser,$dbpass,\%attr);
		my $sth = $dbh->prepare("update STATUS set HOSTNAME = '$EPNAME', IPV4 = '$EPADDR', OSPLAT = '$osplat', OSRELEASE = '$osrel', CLIENTVER = '$clientver', CSTATE = 'OK', LASTSEEN = now() where ID = $EPID");
		$sth->execute();
		debugout(0,"Received check-in from client on $EPADDR (ID $EPID)");
		}
	else {
		debugout(2,"Attempted check-in from unregistered client on $EPADDR");
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
	if ($debug == 1) {
		if ($DBMSG =~ /SIGINT/) { print "\n"; }
		print "[$DBTIME] [$DBCFLAG] $DBMSG\n";
		}
	close (BLOG);
	}

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
