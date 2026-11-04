#!/usr/bin/perl -w
#
# Luminum Server Setup Wizard
# by Christopher R. Curzio (ccurzio@luminum.net)
#
# Drives the Luminum::Setup installer backend. Three interfaces:
#   - curses (default, requires Curses::UI)
#   - text   (--textonly, or automatic when Curses::UI is unavailable)
#   - non-interactive (--noninteractive plus parameter flags, for
#     unattended installs and testing)
#
# Non-interactive example:
#   perl setup.pl --noninteractive --yes \
#       --shost luminum.example.com --laddr 192.0.2.10 --lport 10465 \
#       --install-root /opt/Luminum/LuminumServer

use strict;
use POSIX ();
use Term::ANSIColor;
use Text::Wrap;
use FindBin qw($Bin);
use lib "$Bin/lib";
use Luminum::Setup;

# Term::ReadKey is only needed for no-echo password entry in text mode.
eval { require Term::ReadKey; Term::ReadKey->import(); };
my $have_readkey = !$@;

my $text = 0;
my $lang;
my $win;
my $label;
my $wizard;
my $wizlabel;
my $wizbuttons;
my $wizaction;
my $path = "/opt/Luminum/LuminumServer";

my $mainlabel;
my $breaklabel;
my $introlabel;
my $abortlabel;
my $existlabel;
my $rconflabel;
my $badoplabel;
my $nextbutton;
my $backbutton;
my $exitbutton;
my $nextbsc;
my $backbsc;
my $exitbsc;
my $reconfsc;
my $newconfsc;
my $reconfbutton;
my $newconfbutton;
my $nocurseslabel;
my $changed = 0;
my $cancelwarnlabel;
my $yesbutton;
my $nobutton;
my $yesbsc;
my $nobsc;

if ($ENV{LANG} =~ /en_/ || $ENV{LANG} eq "") {
	$lang = "EN";
	$mainlabel = "Luminum Server Setup\n";
	$mainlabel .= "-" x length($mainlabel);
	chop($mainlabel);
	$nextbutton = " Next > ";
	$backbutton = " < Back ";
	$exitbutton = " Cancel ";
	$nextbsc = "N";
	$backbsc = "B";
	$exitbsc = "C";
	$breaklabel = "NOTE: Use CTRL+C to cancel setup at any time. Unsaved changes will be lost.";
	$introlabel = "Welcome to the Luminum Server setup wizard. This tool will guide you through the steps to install Luminum Server on this system.";
	$existlabel = "An existing Luminum Server configuration was found:";
	$rconflabel = "Do you want to [r]econfigure the system, or [c]reate a new configuration?";
	$reconfsc = "R";
	$newconfsc = "C";
	$badoplabel = "Invalid option";
	$reconfbutton = " Reconfigure ";
	$newconfbutton = " New Config ";
	$nocurseslabel = "Curses::UI is not available. Run setup with --textonly for a text-based interface.";
	$cancelwarnlabel = "Unsaved changes will be lost. Are you sure you want to cancel?";
	$yesbutton = " Yes ";
	$nobutton = " No ";
	$yesbsc = "Y";
	$nobsc = "N";
	}
elsif ($ENV{LANG} =~ /de_/) {
	$lang = "DE";
	$mainlabel = "Luminum Server Aufstellen";
	$mainlabel .= "-" x length($mainlabel);
	chop($mainlabel);
	$nextbutton = " Nächste > ";
	$backbutton = "< Zurück ";
	$exitbutton = " Stornieren ";
	$nextbsc = "N";
	$backbsc = "Z";
	$exitbsc = "S";
	$breaklabel = "HINWEIS: Mit STRG+C können Sie das Setup jederzeit abbrechen. Nicht gespeicherte Änderungen gehen verloren.";
	$introlabel = "Willkommen beim Luminum Server-Setup-Assistenten. Dieses Tool führt Sie durch die einzelnen Schritte zur Installation von Luminum Server auf diesem System.";
	$existlabel = "Es wurde eine vorhandene Luminum-Serverkonfiguration gefunden:";
	$rconflabel = "Möchten Sie das System neu [k]onfigurieren oder eine [n]eue Konfiguration erstellen?";
	$reconfsc = "K";
	$newconfsc = "N";
	$badoplabel = "Ungültige option";
	$reconfbutton = " Neukonfigurieren ";
	$newconfbutton = " Neue Konfig. ";
	$nocurseslabel = "Curses::UI ist nicht verfügbar. Führen Sie das Setup mit --textonly für eine textbasierte Oberfläche aus.";
	$cancelwarnlabel = "Nicht gespeicherte Änderungen gehen verloren. Möchten Sie den Vorgang wirklich abbrechen?";
	$yesbutton = " Ja ";
	$nobutton = " Nein ";
	$yesbsc = "J";
	$nobsc = "N";
	}
elsif ($ENV{LANG} =~ /it_/) {
	$lang = "IT";
	$mainlabel = "Luminum Server Impostare";
	$mainlabel .= "-" x length($mainlabel);
	chop($mainlabel);
	$nextbutton = " Prossimo > ";
	$backbutton = "< Precedente ";
	$exitbutton = " Cancellare ";
	$nextbsc = "P";
	$backbsc = "r";
	$exitbsc = "C";
	$breaklabel = "NOTA: Utilizzare CTRL+C per annullare la configurazione in qualsiasi momento. Le modifiche non salvate andranno perse.";
	$introlabel = "Benvenuti alla procedura guidata di installazione di Luminum Server. Questo strumento vi guiderà attraverso i passaggi necessari per installare Luminum Server su questo sistema.";
	$existlabel = "È stata trovata una configurazione esistente del server Luminum:";
	$rconflabel = "Vuoi [r]iconfigurare il sistema o [c]reare una nuova configurazione?";
	$reconfsc = "R";
	$newconfsc = "C";
	$badoplabel = "Opzione non valida";
	$reconfbutton = " Riconfigurà ";
	$newconfbutton = " Nuova Conf. ";
	$nocurseslabel = "Curses::UI non è disponibile. Eseguire il setup con --textonly per un'interfaccia testuale.";
	$cancelwarnlabel = "Le modifiche non salvate andranno perse. Sei sicuro di voler annullare?";
	$yesbutton = " Sì ";
	$nobutton = " No ";
	$yesbsc = "S";
	$nobsc = "N";
	}
elsif ($ENV{LANG} =~ /fr_/) {
	$lang = "FR";
	$mainlabel = "Luminum Server Installation";
	$mainlabel .= "-" x length($mainlabel);
	chop($mainlabel);
	$nextbutton = " Suivant > ";
	$backbutton = "< Précédent ";
	$exitbutton = " Annuler ";
	$nextbsc = "S";
	$backbsc = "P";
	$exitbsc = "A";
	$breaklabel = "REMARQUE : Utilisez Ctrl+C pour annuler l'installation à tout moment. Les modifications non enregistrées seront perdues.";
	$introlabel = "Bienvenue dans l'assistant d'installation de Luminum Server. Cet outil vous guidera pas à pas pour installer Luminum Server sur votre système.";
	$existlabel = "Une configuration de serveur Luminum existante a été trouvée :";
	$rconflabel = "Voulez-vous [r]econfigurer le système ou [c]réer une nouvelle configuration ?";
	$reconfsc = "R";
	$newconfsc = "C";
	$badoplabel = "Option invalide";
	$reconfbutton = " Reconfigurer ";
	$newconfbutton = " Nouvelle Conf. ";
	$nocurseslabel = "Curses::UI n'est pas disponible. Lancez l'installation avec --textonly pour une interface en mode texte.";
	$cancelwarnlabel = "Les modifications non enregistrées seront perdues. Voulez-vous vraiment annuler ?";
	$yesbutton = " Oui ";
	$nobutton = " Non ";
	$yesbsc = "O";
	$nobsc = "N";
	}
elsif ($ENV{LANG} =~ /es_/) {
	$lang = "ES";
	$mainlabel = "Luminum Server Configuración";
	$mainlabel .= "-" x length($mainlabel);
	chop($mainlabel);
	$nextbutton = " Próximo >";
	$backbutton = "< Previo ";
	$exitbutton = " Cancelar ";
	$nextbsc = "P";
	$backbsc = "v";
	$exitbsc = "C";
	$breaklabel = "NOTA: Use CTRL+C para cancelar la configuración en cualquier momento. Los cambios no guardados se perderán.";
	$introlabel = "Bienvenido al asistente de configuración de Luminum Server. Esta herramienta le guiará por los pasos para instalar Luminum Server en este sistema.";
	$existlabel = "Se encontró una configuración de servidor Luminum existente:";
	$rconflabel = "¿Desea [r]econfigurar el sistema o [c]rear una nueva configuración?";
	$reconfsc = "R";
	$newconfsc = "C";
	$badoplabel = "Opción no válida";
	$reconfbutton = " Reconfigurar ";
	$newconfbutton = " Nueva Conf. ";
	$nocurseslabel = "Curses::UI no está disponible. Ejecute la configuración con --textonly para una interfaz de texto.";
	$cancelwarnlabel = "Los cambios no guardados se perderán. ¿Está seguro de que desea cancelar?";
	$yesbutton = " Sí ";
	$nobutton = " No ";
	$yesbsc = "S";
	$nobsc = "N";
	}
else {
	$lang = "EN";
	$mainlabel = "Luminum Server Setup\n";
	$nextbutton = " Next > ";
	$backbutton = " < Back ";
	$exitbutton = " Cancel ";
	$nextbsc = "N";
	$backbsc = "B";
	$exitbsc = "C";
	$breaklabel = "NOTE: Use CTRL+C to cancel setup at any time. Unsaved changes will be lost.";
	$introlabel = "Welcome to the Luminum Server setup wizard. This tool will guide you through the steps to install Luminum Server on this system.";
	$existlabel = "An existing Luminum Server configuration was found:";
	$rconflabel = "Do you want to [r]econfigure the system, or [c]reate a new configuration?";
	$reconfsc = "R";
	$newconfsc = "C";
	$badoplabel = "Invalid option";
	$reconfbutton = " Reconfigure ";
	$newconfbutton = " New Config ";
	$nocurseslabel = "Curses::UI is not available. Run setup with --textonly for a text-based interface.";
	$cancelwarnlabel = "Unsaved changes will be lost. Are you sure you want to cancel?";
	$yesbutton = " Yes ";
	$nobutton = " No ";
	$yesbsc = "Y";
	$nobsc = "N";
	}

# ---------------------------------------------------------------------------
# Command-line options
# ---------------------------------------------------------------------------

my %opt = (
	textonly       => 0,
	noninteractive => 0,
	yes            => 0,
	start          => 1,
	install_root   => $path,
	);
my @valueopts = qw(shost laddr lport waddr wport dbpass dbsocket dbhost dbuser adminuser adminpass adminemail perl5lib srcdir);

my $i = 0;
while ($i < scalar(@ARGV)) {
	my $arg = $ARGV[$i];
	if ($arg eq "--textonly") { $opt{textonly} = 1; }
	elsif ($arg eq "--noninteractive") { $opt{noninteractive} = 1; }
	elsif ($arg eq "--yes") { $opt{yes} = 1; }
	elsif ($arg eq "--no-start") { $opt{start} = 0; }
	elsif ($arg eq "--help" || $arg eq "-h") { usage(); exit 0; }
	elsif ($arg =~ /^--([a-z0-9-]+)$/) {
		my $name = $1;
		if (grep(/^$name$/, @valueopts) || $name eq "install-root") {
			$i++;
			unless ($i < scalar(@ARGV)) { die "Missing value for --$name\n"; }
			$name = "install_root" if $name eq "install-root";
			$opt{$name} = $ARGV[$i];
			}
		else { die "Unknown option: --$name (see --help)\n"; }
		}
	elsif ($arg =~ /^--([a-z0-9-]+)=(.*)$/) {
		my ($name, $val) = ($1, $2);
		$name = "install_root" if $name eq "install-root";
		if (grep(/^$name$/, @valueopts) || $name eq "install_root") { $opt{$name} = $val; }
		else { die "Unknown option: --$name (see --help)\n"; }
		}
	else { die "Unknown argument: $arg (see --help)\n"; }
	$i++;
	}

sub usage {
	print <<EOF;
Luminum Server Setup

Options:
  --noninteractive   run without prompts (requires --shost and --laddr)
  --yes              do not ask for final confirmation
  --no-start         install without starting services
  --textonly         use the text interface instead of curses
  --install-root P   installation directory (default /opt/Luminum/LuminumServer)
  --shost NAME       server hostname (certificate name; required)
  --laddr ADDR       broker listener address (required)
  --lport N          broker listener port (default 10465)
  --waddr ADDR       web console address (default 0.0.0.0)
  --wport N          web console port (default 443)
  --dbuser NAME      database user (default luminum)
  --dbpass PASS      database password (default: generated)
  --dbhost HOST      database host (default: local socket)
  --dbsocket PATH    database socket (default /var/run/mysqld/mysqld.sock)
  --adminuser NAME   console admin username (default lumadmin)
  --adminpass PASS   console admin password (default: generated)
  --adminemail ADDR  email for the admin account (set at creation)
  --perl5lib PATH    PERL5LIB for the broker start script
  --srcdir PATH      source tree to install from (default: this directory)
EOF
	}

# ---------------------------------------------------------------------------
# Run the installer with a parameter set
# ---------------------------------------------------------------------------

sub runinstaller {
	my (%p) = @_;
	my $rc = Luminum::Setup::run(%p);
	if ($text == 1 || $opt{noninteractive}) {
		exit($rc ? 1 : 0);
		}
	return $rc;
	}

# Locate the @INC directories that provide the broker's non-core modules
# (DBI, IO::Socket::SSL, Crypt::Perl) and return them as a colon-joined
# PERL5LIB value. Empty string if none are found (the broker will then
# rely on the default @INC alone).
#
sub detect_perl5lib {
	my @mods = (
		"DBI.pm",
		"IO/Socket/SSL.pm",
		"Crypt/Perl/Ed25519/PrivateKey.pm",
		);
	my %dirs;
	for my $mod (@mods) {
		for my $dir (@INC) {
			next unless defined $dir && length $dir;
			if (-f "$dir/$mod") {
				$dirs{$dir} = 1;
				last;
				}
		}
	}
	return join(":", sort keys %dirs);
	}

# Build the Setup::run parameter list from collected values.
#
sub buildparams {
	my (%v) = @_;
	my %p = (
		install_root => $v{install_root} || $opt{install_root},
		shost        => $v{shost},
		laddr        => $v{laddr},
		lport        => $v{lport} || 10465,
		waddr        => $v{waddr},
		wport        => $v{wport} || 443,
		dbuser       => $v{dbuser},
		dbpass       => $v{dbpass},
		dbhost       => $v{dbhost},
		dbsocket     => $v{dbsocket},
		adminuser    => $v{adminuser},
		adminpass    => $v{adminpass},
		adminemail   => $v{adminemail},
		perl5lib     => $v{perl5lib},
		start        => $opt{start},
		);
	$p{srcdir} = $v{srcdir} if $v{srcdir};
	# Drop empty optionals so Setup defaults apply.
	for my $k (qw(waddr dbuser dbpass dbhost dbsocket adminuser adminpass adminemail perl5lib)) {
		delete $p{$k} unless defined $p{$k} && $p{$k} ne "";
		}
	# The broker needs non-core modules; if the operator didn't supply a
	# perl5lib, use the directories detected above so the generated start
	# scripts export a working PERL5LIB.
	$p{perl5lib} ||= detect_perl5lib();
	return %p;
	}

# ---------------------------------------------------------------------------
# Non-interactive mode
# ---------------------------------------------------------------------------

if ($opt{noninteractive}) {
	unless (defined $opt{shost} && defined $opt{laddr}) {
		die "Non-interactive setup requires --shost and --laddr (see --help)\n";
		}
	my %params = buildparams(map { $_ => $opt{$_} } qw(shost laddr lport waddr wport dbuser dbpass dbhost dbsocket adminuser adminpass adminemail perl5lib srcdir));
	print "Luminum Server non-interactive setup\n";
	my $waddr = $params{waddr} || "0.0.0.0";
	print "  Install root:  $params{install_root}\n";
	print "  Server host:   $params{shost}\n";
	print "  Broker:        $params{laddr}:$params{lport}\n";
	print "  Web console:   $waddr:$params{wport}\n";
	print "  Start services:" . ($opt{start} ? " yes\n" : " no\n");
	unless ($opt{yes}) {
		print "Proceed? [y/N]: ";
		my $ans = <STDIN>;
		chomp($ans);
		exit 0 unless lc($ans) eq "y" || lc($ans) eq "yes";
		}
	runinstaller(%params);
	exit 0;
	}

# ---------------------------------------------------------------------------
# Text mode parameter collection
# ---------------------------------------------------------------------------

sub textprompt {
	my ($prompt, $default) = @_;
	print $prompt;
	print " [$default]" if defined $default && $default ne "";
	print ": ";
	my $ans = <STDIN>;
	chomp($ans) if defined $ans;
	return (defined $ans && $ans ne "") ? $ans : $default;
	}

sub textpromptpass {
	my ($prompt, $default) = @_;
	print $prompt;
	print " [blank = keep/generate]" unless defined $default && $default ne "";
	print ": ";
	my $ans;
	if ($have_readkey) {
		ReadMode("noecho");
		$ans = <STDIN>;
		ReadMode("normal");
		print "\n";
		}
	else { $ans = <STDIN>; }
	chomp($ans) if defined $ans;
	return (defined $ans && $ans ne "") ? $ans : $default;
	}

sub collect_params_text {
	print "\nInstallation Parameters\n\n";
	my %v;
	$v{install_root} = textprompt("Installation root", $opt{install_root});
	$v{shost}        = textprompt("Server hostname (certificate name)", $opt{shost});
	$v{laddr}        = textprompt("Broker listener address", $opt{laddr});
	$v{lport}        = textprompt("Broker listener port", $opt{lport} || "10465");
	$v{wport}        = textprompt("Web console port", $opt{wport} || "443");
	$v{dbsocket}     = textprompt("Database socket", $opt{dbsocket} || "/var/run/mysqld/mysqld.sock");
	$v{dbuser}       = textprompt("Database user", $opt{dbuser} || "luminum");
	$v{dbpass}       = textpromptpass("Database password", $opt{dbpass});
	$v{adminuser}    = textprompt("Console admin username", $opt{adminuser} || "lumadmin");
	$v{adminpass}    = textpromptpass("Console admin password", $opt{adminpass});
	$v{adminemail}   = textprompt("Admin Email", $opt{adminemail});
	return %v;
	}

# ---------------------------------------------------------------------------
# Default detection (interactive wizards)
# ---------------------------------------------------------------------------

# First non-loopback IPv4 address of an interface (broker listener default).
# Returns undef when nothing is found.
#
sub detect_laddr {
	my $out = `ip -4 -o addr show 2>/dev/null`;
	for my $line (split /\n/, $out) {
		if ($line =~ /^\d+:\s+(\S+)\s+inet\s+(\d+\.\d+\.\d+\.\d+)/) {
			my ($if, $ip) = ($1, $2);
			next if $if eq "lo" || $ip =~ /^127\./;
			return $ip;
		}
	}
	return undef;
	}

# First existing MariaDB/MySQL socket among the usual locations.
#
sub detect_dbsocket {
	for my $cand ("/var/run/mysqld/mysqld.sock", "/run/mysqld/mysqld.sock",
			"/var/lib/mysql/mysql.sock", "/var/run/mysql/mysql.sock",
			"/tmp/mysqld.sock") {
		return $cand if -S $cand;
	}
	return "/var/run/mysqld/mysqld.sock";   # Debian default
	}

# System hostname (certificate name default).
#
sub detect_shost {
	my $h = `hostname 2>/dev/null`;
	chomp($h);
	return ($h =~ /^[A-Za-z0-9_\.\-]+$/) ? $h : undef;
	}

# Populate wizard defaults that can be detected on this system.
#
sub apply_detected_defaults {
	$opt{shost}    ||= detect_shost();
	$opt{laddr}    ||= detect_laddr();
	$opt{dbsocket} ||= detect_dbsocket();
	}

# ---------------------------------------------------------------------------
# Interface selection
# ---------------------------------------------------------------------------

if ($text == 0) {
	if ($opt{textonly}) {
		# --textonly forces the text interface even when Curses::UI is
		# available, so skip loading it.
		$text = 1;
		}
	else {
		eval { require Curses::UI; Curses::UI->import() };
		if ($@) {
			print "$nocurseslabel\n";
			exit(1);
			}
		}
	}

if ($text == 1) {
	$SIG{INT} = sub {
		if ($have_readkey) { ReadMode('normal'); }
		print "\e[?25h\n";
		print "Luminum Server setup aborted.\n\n";
		exit(0);
		};
	apply_detected_defaults();
	print "\e[?25l";
	system("clear");
	print "$mainlabel\n\n";
	print "$introlabel\n\n";
	print "$breaklabel\n\n";
	print "Press ENTER to continue...";
	<STDIN>;

	print "\e[?25h";
	system("clear");
	print "$mainlabel\n\n";

	if (-e "$opt{install_root}/config/broker.conf") {
		print "$existlabel\n";
		print "- ";
		print color('bold blue');
		print "$opt{install_root}/config/broker.conf\n\n";
		print color('reset');
		print "$rconflabel\n\n";
		my $useconf = "";
		while (lc($useconf) ne lc($reconfsc) && lc($useconf) ne lc($newconfsc)) {
			print "$badoplabel: $useconf\n\n" if $useconf ne "";
			$useconf = "";
			print "[$reconfsc|$newconfsc]: ";
			$useconf = <STDIN>;
			chomp($useconf);
			}
		}

	my %v = collect_params_text();
	print "\nReview:\n";
	print "  Install root:  $v{install_root}\n";
	print "  Server host:   $v{shost}\n";
	print "  Broker:        $v{laddr}:$v{lport}\n";
	print "  Web console:   port $v{wport}\n";
	print "Proceed with installation? [y/N]: ";
	my $ans = <STDIN>;
	chomp($ans);
	exit 0 unless lc($ans) eq "y" || lc($ans) eq "yes";
	print "\e[?25l";
	runinstaller(buildparams(%v));
	exit 0;
	}

# ---------------------------------------------------------------------------
# Curses mode
# ---------------------------------------------------------------------------

$Text::Wrap::columns = 70;
apply_detected_defaults();
my $cui = new Curses::UI(-color_support => 1, -intellidraw => 1);
# Input fields are drawn on a dark gray background so they stand out from
# the white dialog; the terminal's default foreground is a light gray that
# blends into the white. define_color allocates a custom palette slot (needs
# a >8-color terminal; on an 8-color terminal ncurses maps the RGB value to
# the nearest available color). If color support is off the name simply
# resolves to the default color.
if (my $co = $cui->color) {
	# Curses::UI::Color seeds its custom-color counter at 7, which is the
	# built-in white slot, so the first define_color would clobber white.
	# Bump it to 8 so darkgray gets a fresh palette slot.
	$co->{ccount} = 8 if ($co->{ccount} // 0) < 8;
	$co->define_color('darkgray', 400, 400, 400);
	}
$cui->set_binding(sub { print "\e[?25h"; exit(0); }, "\cC");

$win = $cui->add('base', 'Window');
$label = $win->add('setuplabel', 'Label',
	-bg	=> "blue",
	-text	=> "$mainlabel",
	-bold	=> 1,
	-width	=> -1,
	-height	=> -1,
	);
$label->draw;

my $cancelAction = sub {
	if ($changed == 1) {
		my $warnwin = $win->add('warndialog', 'Window',
			-centered	=> 1,
			-width		=> 68,
			-height		=> 12,
			-bg		=> 'white',
			-fg		=> 'black',
			-border		=> 1,
			-bfg		=> 'black',
			-bbg		=> 'white',
			);
		$warnwin->add('warnlabel', 'Label',
			-width		=> -1,
			-height		=> -1,
			-fg		=> 'black',
			-padleft	=> 2,
			-padright	=> 2,
			-padtop		=> 1,
			-text		=> wrap('', '', $cancelwarnlabel),
			);
		my $warnbuttons = $warnwin->add('warnbuttons', 'Buttonbox',
			-buttons => [ {
				-label		=> $nobutton,
				-value		=> "no",
				-shortcut	=> $nobsc,
				-onpress	=> sub { $win->delete('warndialog'); $win->draw(); },
				},
			{
				-label		=> $yesbutton,
				-value		=> "yes",
				-shortcut	=> $yesbsc,
				-onpress	=> sub { print "\e[?25h"; exit(0); },
				} ],
			-fg		=> "black",
			-buttonalignment=> "right",
			-x		=> 2,
			-ipadright	=> 3,
			-y		=> 7,
			-selected	=> 0,
			);
		$warnbuttons->focus();
		}
	else {
		print "\e[?25h"; exit(0);
		}
	};

# Parameter dialog: collects install values. Field widgets are kept in
# %pentry (name => TextEntry) so the Install handler can read them with
# ->get(). An optional $defaults hash pre-fills the entries (used when
# retrying after a failed install).
#
my %pentry;
my $perr;
my $paramsref;
my $doInstall;

my $paramAction = sub {
	# The pressed button is passed in as the argument; the field values
	# come from the widgets stored in %pentry.
	my %v;
	for my $name (keys %pentry) {
		my $val = $pentry{$name}->get();
		$v{$name} = defined $val ? $val : "";
	}
	$perr->text("") if $perr;
	unless ($v{shost} ne "" && $v{laddr} ne "") {
		$perr->text("Server hostname and listener address are required.") if $perr;
		return;
	}
	$paramsref = \%v;
	$win->delete('paramdialog');
	$win->draw();
	$doInstall->();
	};

my $showParamDialog = sub {
	my ($defaults) = @_;
	$defaults ||= {};
	$changed = 1;
	my $dlg = $win->add('paramdialog', 'Window',
		-centered	=> 1,
		-width		=> 78,
		-height		=> 19,
		-bg		=> 'white',
		-fg		=> 'black',
		-border		=> 1,
		-bfg		=> 'black',
		-bbg		=> 'white',
		);
	$dlg->add('p_title', 'Label',
		-text => "Installation Parameters", -bold => 1,
		-x => 2, -y => 1,
		);
	my @fields = (
		['install_root', "Installation Root", $defaults->{install_root} // $opt{install_root}],
		['shost',        "Server Hostname",   $defaults->{shost}        // $opt{shost}],
		['laddr',        "Listener Address",  $defaults->{laddr}        // $opt{laddr}],
		['lport',        "Listener Port",     $defaults->{lport}        // ($opt{lport} || "10465")],
		['wport',        "Web Console Port",  $defaults->{wport}        // ($opt{wport} || "443")],
		['dbsocket',     "Database Socket",   $defaults->{dbsocket}     // $opt{dbsocket}],
		['dbpass',       "Database Password", $defaults->{dbpass}       // ""],
		['adminpass',    "Admin Password",    $defaults->{adminpass}    // ""],
		['adminemail',   "Admin Email",       $defaults->{adminemail}   // $opt{adminemail}],
	);
	my $y = 3;
	for my $f (@fields) {
		$dlg->add($f->[0] . "_l", 'Label',
			-text => $f->[1], -width => 20, -height => 1,
			-x => 2, -y => $y,
			);
		my %eopts = (
			-text => (defined $f->[2] ? $f->[2] : ""),
			-width => 46,
			-x => 24, -y => $y,
			-fg => 'white',
			-bg => 'darkgray',
			);
		my $wtype = $f->[0] =~ /pass$/ ? 'PasswordEntry' : 'TextEntry';
		$pentry{$f->[0]} = $dlg->add($f->[0], $wtype, %eopts);
		$y++;
		}
	$perr = $dlg->add('p_err', 'Label',
		-text => "", -fg => 'red', -width => -1, -height => 1,
		-x => 2, -y => 12,
		);
	my $buttons = $dlg->add('p_buttons', 'Buttonbox',
		-buttons => [ {
			-label		=> $exitbutton,
			-value		=> "cancel",
			-shortcut	=> $exitbsc,
			-onpress	=> $cancelAction,
			},
		{
			-label		=> " Install ",
			-value		=> "install",
			-shortcut	=> "I",
			-onpress	=> $paramAction,
			} ],
		-fg		=> "black",
		-buttonalignment => "right",
		-x		=> 2,
		-ipadright	=> 3,
		-y		=> 14,
		-selected	=> 1,
		);
	$pentry{install_root}->focus();
	};

# Run the installer and report the result in a dialog. Called from within
# the main mainloop; the status dialog is drawn, the installer runs
# (blocking, output captured), then the result replaces the status text.
# Any failure - including an unexpected die from the installer - is shown
# in the dialog instead of killing the wizard.
#
$doInstall = sub {
	my %params = buildparams(%$paramsref);
	my $status = $win->add('statusdialog', 'Window',
		-centered => 1, -width => 74, -height => 24,
		-bg => 'white', -fg => 'black', -border => 1,
		-bfg => 'black', -bbg => 'white',
		);
	$status->add('statuslabel', 'Label',
		-text => "Running installation...\n(this may take a moment)",
		-width => -1, -height => -1,
		-x => 2, -y => 2,
		);
	$status->draw;

	# Capture installer output (raw stdout/stderr would corrupt the
	# curses screen).
	my $tmpout = "/tmp/luminum-setup-out.$$";
	my $rc;
	my $runerr = "";
	{
		my $fh;
		open($fh, ">", $tmpout) or $runerr = "open $tmpout: $!";
		if (!$runerr) {
			# Redirect at the file-descriptor level, not just via
			# select(): child processes (the start/stop scripts, openssl,
			# systemctl, ...) inherit fd 1/2 and would otherwise paint
			# over the curses screen. The original fds are saved with
			# dup2 onto explicitly free fds - open(FH, "<&=", 1) cannot
			# be used: it aliases fd 1 itself instead of copying it, so
			# the "saved" handle would follow the redirect.
			my $saveout;
			my $saveerr;
			if (open($saveout, "+<", "/dev/null")
				&& open($saveerr, "+<", "/dev/null")
				&& fileno($saveout) > 2
				&& fileno($saveerr) > 2
				&& POSIX::dup2(1, fileno($saveout)) == fileno($saveout)
				&& POSIX::dup2(2, fileno($saveerr)) == fileno($saveerr)
				&& POSIX::dup2(fileno($fh), 1) == 1
				&& POSIX::dup2(fileno($fh), 2) == 2) {
				$rc = eval { Luminum::Setup::run(%params) };
				$runerr = $@ if $@;
				POSIX::dup2(fileno($saveout), 1);
				POSIX::dup2(fileno($saveerr), 2);
				}
			close($saveout) if defined fileno($saveout);
			close($saveerr) if defined fileno($saveerr);
			close($fh);
			}
		else {
			$rc = eval { Luminum::Setup::run(%params) };
			$runerr = $@ if $@;
			}
		}
	$rc = 1 unless defined $rc;
	my $output = "";
	if (open(my $rfh, "<", $tmpout)) { $output = do { local $/; <$rfh> }; close($rfh); }
	unlink($tmpout);

	$status->delete('statuslabel');
	my $msg = $rc == 0
		? "Installation completed successfully.\n\nThe server is running."
		: "Installation FAILED."
		  . ($runerr ne "" ? "\n\nError: $runerr" : "")
		  . ($output ne "" ? "\n\n" . substr($output, -1000) : "");
	$status->add('statuslabel', 'Label',
		-text => wrap('', '', $msg),
		-width => -1, -height => -1,
		-fg => ($rc == 0 ? 'black' : 'red'),
		-x => 2, -y => 2,
		);
	my @sbuttons = ($rc == 0
		? ( { -label => " OK ", -value => "ok",
			-onpress => sub { print "\e[?25h"; exit(0); } } )
		: ( { -label => " Retry ", -value => "retry",
			-onpress => sub {
				my %again = %$paramsref;
				$win->delete('statusdialog');
				$win->draw();
				$showParamDialog->(\%again);
				} },
		  { -label => " Exit ", -value => "exitfail",
			-onpress => sub { print "\e[?25h"; exit(1); } } ));
	$status->add('statusbuttons', 'Buttonbox',
		-buttons => \@sbuttons,
		-fg => "black",
		-buttonalignment => "right",
		-x => 2, -y => 18,
		-ipadright => 3,
		-selected => 0,
		);
	$status->draw;
	$status->getobj('statusbuttons')->focus();
	};

$wizard = $win->add('welcdialog','Window',
	-centered	=> 1,
	-width		=> 76,
	-height		=> 18,
	-bg		=> 'white',
	-fg		=> 'black',
	-border		=> 1,
	-bfg		=> 'black',
	-bbg		=> 'white',
	);

$wizlabel = $wizard->add('wizlabel', 'Label',
	-width	=> -1,
	-height	=> -1,
	-fg		=> 'black',
	-padleft	=> 2,
	-padright	=> 2,
	-padtop		=> 1,
	-text	=> wrap('', '', $introlabel) . "\n\n" . wrap('', '', $breaklabel)
	);

$wizbuttons = $wizard->add('wizbuttons','Buttonbox',
	-buttons => [ {
		-label		=> $exitbutton,
		-value		=> "exit",
		-shortcut	=> $exitbsc,
		-onpress	=> $cancelAction,
		},
	{
		-label		=> $nextbutton,
		-value		=> "next",
		-shortcut	=> $nextbsc,
		-onpress	=> sub {
			$win->delete('welcdialog');
			$win->draw();
			if (-e "$opt{install_root}/config/broker.conf") {
				my $confwin = $win->add('confdialog', 'Window',
					-centered	=> 1,
					-width		=> 76,
					-height		=> 16,
					-bg		=> 'white',
					-fg		=> 'black',
					-border		=> 1,
					-bfg		=> 'black',
					-bbg		=> 'white',
					);
				$confwin->add('conflabel', 'Label',
					-width	=> -1,
					-height	=> -1,
					-fg		=> 'black',
					-padleft	=> 2,
					-padright	=> 2,
					-padtop		=> 1,
					-text	=> wrap('', '', "$existlabel\n\n  $opt{install_root}/config/broker.conf\n\n$rconflabel"),
					);
				my $confbuttons = $confwin->add('confbuttons', 'Buttonbox',
					-buttons => [ {
						-label		=> $exitbutton,
						-value		=> "exit",
						-shortcut	=> $exitbsc,
						-onpress	=> $cancelAction,
						},
					{
						-label		=> $newconfbutton,
						-value		=> "newconf",
						-shortcut	=> $newconfsc,
						-onpress	=> sub {
							$win->delete('confdialog');
							$win->draw();
							$showParamDialog->();
							},
						},
					{
						-label		=> $reconfbutton,
						-value		=> "reconf",
						-shortcut	=> $reconfsc,
						-onpress	=> sub {
							$win->delete('confdialog');
							$win->draw();
							$showParamDialog->();
							},
						} ],
					-fg		=> "black",
					-buttonalignment=> "right",
					-x		=> 2,
					-ipadright	=> 3,
					-y		=> 11,
					-selected	=> 2,
					);
				$confbuttons->focus();
				}
			else {
				$showParamDialog->();
				}
			},
		} ],
	-fg		=> "black",
	-buttonalignment=> "right",
	-x		=> 2,
	-ipadright	=> 3,
	-y		=> 13,
	-selected	=> 1,
	);

$wizbuttons->focus();

$cui->mainloop();

exit 0;
