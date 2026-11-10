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
use Socket qw(inet_aton AF_INET);
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
my $okbutton;
my $emailreqlabel;
my $genpasslabel;
my $certtitle;
my $certgen;
my $certgenkey;
my $certimport;
my $certfilel;
my $keyfilel;
my $keypassl;
my $certerr;
my $certerrkey;
my $certnonsel;
my $certkeyprompt;
my $certpassprompt;
my $certcertprompt;

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
	$okbutton = " OK ";
	$emailreqlabel = "The admin email field must be populated before continuing.";
	$genpasslabel = "If an admin password is not provided one will be generated automatically. Do you want to continue?";
	$certtitle = "Certificate Configuration";
	$certgen = "Generate a new self-signed certificate (new private key)";
	$certgenkey = "Generate a new certificate (existing private key)";
	$certimport = "Import an existing certificate and private key";
	$certfilel = "Certificate File";
	$keyfilel = "Private Key File";
	$keypassl = "Key Passphrase";
	$certerr = "Certificate and private key paths are required for import.";
	$certerrkey = "Private key path is required.";
	$certnonsel = "Please select a certificate option.";
	$certkeyprompt = "Path to existing private key";
	$certpassprompt = "Key passphrase (blank if none)";
	$certcertprompt = "Path to certificate";
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
	$okbutton = " OK ";
	$emailreqlabel = "Das Feld für die Administrator-E-Mail-Adresse muss ausgefüllt werden, um fortzufahren.";
	$genpasslabel = "Wenn kein Administrator-Kennwort angegeben wird, wird automatisch eines generiert. Möchten Sie fortfahren?";
	$certtitle = "Zertifikatskonfiguration";
	$certgen = "Neues selbstsigniertes Zertifikat erstellen (neuer privater Schlüssel)";
	$certgenkey = "Neues Zertifikat erstellen (vorhandener privater Schlüssel)";
	$certimport = "Vorhandenes Zertifikat und privaten Schlüssel importieren";
	$certfilel = "Zertifikatsdatei";
	$keyfilel = "Private Schlüsseldatei";
	$keypassl = "Schlüsselkennwort";
	$certerr = "Für den Import sind Zertifikats- und Schlüsselpfad erforderlich.";
	$certerrkey = "Der Pfad zum privaten Schlüssel ist erforderlich.";
	$certnonsel = "Bitte wählen Sie eine Zertifikatsoption.";
	$certkeyprompt = "Pfad zum vorhandenen privaten Schlüssel";
	$certpassprompt = "Schlüsselkennwort (leer, wenn keines)";
	$certcertprompt = "Pfad zum Zertifikat";
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
	$okbutton = " OK ";
	$emailreqlabel = "Il campo e-mail dell'amministratore deve essere compilato per continuare.";
	$genpasslabel = "Se non viene fornita una password amministratore, ne verrà generata una automaticamente. Vuoi continuare?";
	$certtitle = "Configurazione Certificato";
	$certgen = "Genera un nuovo certificato autofirmato (nuova chiave privata)";
	$certgenkey = "Genera un nuovo certificato (chiave privata esistente)";
	$certimport = "Importa un certificato e una chiave privata esistenti";
	$certfilel = "File Certificato";
	$keyfilel = "File Chiave Privata";
	$keypassl = "Passphrase Chiave";
	$certerr = "Per l'importazione sono richiesti i percorsi di certificato e chiave.";
	$certerrkey = "Il percorso della chiave privata è richiesto.";
	$certnonsel = "Selezionare un'opzione del certificato.";
	$certkeyprompt = "Percorso della chiave privata esistente";
	$certpassprompt = "Passphrase della chiave (vuoto se assente)";
	$certcertprompt = "Percorso del certificato";
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
	$okbutton = " OK ";
	$emailreqlabel = "Le champ e-mail de l'administrateur doit être rempli pour continuer.";
	$genpasslabel = "Si aucun mot de passe d'administrateur n'est fourni, un mot de passe sera généré automatiquement. Voulez-vous continuer ?";
	$certtitle = "Configuration du Certificat";
	$certgen = "Générer un nouveau certificat auto-signé (nouvelle clé privée)";
	$certgenkey = "Générer un nouveau certificat (clé privée existante)";
	$certimport = "Importer un certificat et une clé privée existants";
	$certfilel = "Fichier Certificat";
	$keyfilel = "Fichier Clé Privée";
	$keypassl = "Passphrase de Clé";
	$certerr = "Les chemins du certificat et de la clé sont requis pour l'importation.";
	$certerrkey = "Le chemin de la clé privée est requis.";
	$certnonsel = "Veuillez sélectionner une option de certificat.";
	$certkeyprompt = "Chemin de la clé privée existante";
	$certpassprompt = "Passphrase de la clé (vide si aucune)";
	$certcertprompt = "Chemin du certificat";
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
	$okbutton = " OK ";
	$emailreqlabel = "El campo de correo electrónico del administrador debe estar rellenado para continuar.";
	$genpasslabel = "Si no se proporciona una contraseña de administrador, se generará una automáticamente. ¿Desea continuar?";
	$certtitle = "Configuración del Certificado";
	$certgen = "Generar un nuevo certificado autofirmado (nueva clave privada)";
	$certgenkey = "Generar un nuevo certificado (clave privada existente)";
	$certimport = "Importar un certificado y una clave privada existentes";
	$certfilel = "Archivo de Certificado";
	$keyfilel = "Archivo de Clave Privada";
	$keypassl = "Passphrase de Clave";
	$certerr = "Los caminos del certificado y de la clave son necesarios para importar.";
	$certerrkey = "El camino de la clave privada es necesario.";
	$certnonsel = "Seleccione una opción de certificado.";
	$certkeyprompt = "Camino a la clave privada existente";
	$certpassprompt = "Passphrase de la clave (vacío si no tiene)";
	$certcertprompt = "Camino al certificado";
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
	$okbutton = " OK ";
	$emailreqlabel = "The admin email field must be populated before continuing.";
	$genpasslabel = "If an admin password is not provided one will be generated automatically. Do you want to continue?";
	$certtitle = "Certificate Configuration";
	$certgen = "Generate a new self-signed certificate (new private key)";
	$certgenkey = "Generate a new certificate (existing private key)";
	$certimport = "Import an existing certificate and private key";
	$certfilel = "Certificate File";
	$keyfilel = "Private Key File";
	$keypassl = "Key Passphrase";
	$certerr = "Certificate and private key paths are required for import.";
	$certerrkey = "Private key path is required.";
	$certnonsel = "Please select a certificate option.";
	$certkeyprompt = "Path to existing private key";
	$certpassprompt = "Key passphrase (blank if none)";
	$certcertprompt = "Path to certificate";
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
my @valueopts = qw(shost laddr lport waddr wport dbpass dbsocket dbhost dbuser dbadmin dbadminpass adminuser adminpass adminemail perl5lib srcdir certmode keymode cert key keypass);

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
  --dbadmin NAME     database admin user for schema setup (default root)
  --dbadminpass PASS database admin password (default: none)
  --adminuser NAME   console admin username (default lumadmin)
  --adminpass PASS   console admin password (default: generated)
  --adminemail ADDR  email for the admin account (set at creation)
  --perl5lib PATH    PERL5LIB for the broker start script
  --srcdir PATH      source tree to install from (default: this directory)
  --certmode M       certificate mode: generate (default) or import
  --keymode M        key mode for generate: new (default) or existing
  --cert PATH        existing certificate to import
  --key PATH         existing private key (import, or keymode existing)
  --keypass PASS     passphrase for an encrypted private key
EOF
	}

# ---------------------------------------------------------------------------
# Run the installer with a parameter set
# ---------------------------------------------------------------------------

sub runinstaller {
	my (%p) = @_;
	if ($text == 1) {
		# Offer to install missing dependencies before the installer
		# fails (Setup.pm detects them before any file is written).
		$p{deps_offer} = sub {
			my ($missing) = @_;
			print "\nThe following dependencies are missing:\n";
			print "  $_\n" for @$missing;
			print "\nInstall them now with the system package manager? [y/N] ";
			my $ans = <STDIN>;
			chomp($ans) if defined $ans;
			return (defined $ans && $ans =~ /^[yY]/) ? 1 : 0;
			};
		}
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
	my %modname = (
		"DBI.pm" => "DBI",
		"IO/Socket/SSL.pm" => "IO::Socket::SSL",
		"Crypt/Perl/Ed25519/PrivateKey.pm" => "Crypt::Perl::Ed25519",
		);
	my %dirs;
	my @missing;
	for my $mod (@mods) {
		my $found = 0;
		for my $dir (@INC) {
			next unless defined $dir && length $dir;
			if (-f "$dir/$mod") {
				$dirs{$dir} = 1;
				$found = 1;
				last;
				}
		}
		push @missing, $modname{$mod} unless $found;
	}
	# Warn early in the text / non-interactive interfaces. In the curses UI
	# this would corrupt the screen; the broker compile check in
	# Luminum::Setup::install_service still catches a missing module there
	# and reports it in the failure dialog.
	if (@missing && ($text == 1 || $opt{noninteractive})) {
		warn "[setup] warning: could not find " . join(", ", @missing)
			. " in \@INC (PERL5LIB=" . ($ENV{PERL5LIB} || "(unset)") . ").\n";
		warn "[setup]           The generated broker start script may lack module paths and the broker may fail to start. Set PERL5LIB to include their directories before running setup.\n";
	}
	return join(":", sort keys %dirs);
	}

# Short human-readable description of a certificate spec (review/summary).
#
sub certdescription {
	my ($c) = @_;
	return "import existing" if $c->{mode} eq "import";
	return "generate (existing key)" if $c->{keymode} eq "existing";
	return "generate new";
	}

# Build the Setup::run parameter list from collected values.
# Callers pass the certificate spec (or undef) as the LAST argument;
# pop it before the hash assignment, since a hash in a list
# assignment would greedily consume the rest of the argument list.
#
sub buildparams {
	my $cs = pop @_;
	my %v = @_;
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
		dbadmin      => $v{dbadmin},
		dbadminpass  => $v{dbadminpass},
		adminuser    => $v{adminuser},
		adminpass    => $v{adminpass},
		adminemail   => $v{adminemail},
		perl5lib     => $v{perl5lib},
		start        => $opt{start},
		);
	$p{srcdir} = $v{srcdir} if $v{srcdir};
	# Drop empty optionals so Setup defaults apply.
	for my $k (qw(waddr dbuser dbpass dbhost dbsocket dbadmin dbadminpass adminuser adminpass adminemail perl5lib)) {
		delete $p{$k} unless defined $p{$k} && $p{$k} ne "";
		}
	# The broker needs non-core modules; if the operator didn't supply a
	# perl5lib, use the directories detected above so the generated start
	# scripts export a working PERL5LIB.
	$p{perl5lib} ||= detect_perl5lib();
	$p{ssl} = $cs if $cs;
	return %p;
	}

# ---------------------------------------------------------------------------
# Non-interactive mode
# ---------------------------------------------------------------------------

if ($opt{noninteractive}) {
	unless (defined $opt{shost} && defined $opt{laddr}) {
		die "Non-interactive setup requires --shost and --laddr (see --help)\n";
		}
	my $certmode = $opt{certmode} || "generate";
	my $keymode  = $opt{keymode} || "new";
	die "Invalid --certmode (generate|import)\n" unless $certmode =~ /^(generate|import)$/;
	die "Invalid --keymode (new|existing)\n" unless $keymode =~ /^(new|existing)$/;
	my %ssl = (mode => $certmode, keymode => $keymode);
	$ssl{cert} = $opt{cert} if defined $opt{cert};
	$ssl{key} = $opt{key} if defined $opt{key};
	$ssl{keypass} = $opt{keypass} if defined $opt{keypass};
	if ($certmode eq "import") {
		die "Import mode requires --cert and --key\n" unless $ssl{cert} && $ssl{key};
		}
	if ($keymode eq "existing") {
		die "Existing-key mode requires --key\n" unless $ssl{key};
		}
	# Parenthesize the map: without them its LIST would swallow \%ssl
	# as a final iteration and the cert spec would never be passed.
	my %params = buildparams((map { $_ => $opt{$_} } qw(shost laddr lport waddr wport dbuser dbpass dbhost dbsocket dbadmin dbadminpass adminuser adminpass adminemail perl5lib srcdir)), \%ssl);
	print "Luminum Server non-interactive setup\n";
	my $waddr = $params{waddr} || "0.0.0.0";
	print "  Install root:  $params{install_root}\n";
	print "  Server host:   $params{shost}\n";
	print "  Broker:        $params{laddr}:$params{lport}\n";
	print "  Web console:   $waddr:$params{wport}\n";
	print "  Certificate:   " . certdescription(\%ssl) . "\n";
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
	my ($prompt, $default, $hint) = @_;
	print $prompt;
	if (defined $default && $default ne "") { print " [$default]"; }
	elsif (defined $hint) { print " [$hint]"; }
	else { print " [blank = keep/generate]"; }
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
	$v{dbadmin}      = textprompt("Database admin user", $opt{dbadmin} || "root");
	$v{dbadminpass}  = textpromptpass("Database admin password", $opt{dbadminpass}, "blank = no password");
	$v{dbuser}       = textprompt("Database user", $opt{dbuser} || "luminum");
	$v{dbpass}       = textpromptpass("DB App Password", $opt{dbpass});
	$v{adminuser}    = textprompt("Console admin username", $opt{adminuser} || "lumadmin");
	$v{adminpass}    = textpromptpass("Console admin password", $opt{adminpass});
	$v{adminemail}   = textprompt("Admin Email", $opt{adminemail});
	return %v;
	}

# Text-mode certificate configuration. Returns a spec hash for
# Luminum::Setup (mode/keymode/cert/key/keypass).
#
sub collect_cert_text {
	print "\n$certtitle\n\n";
	print "[1] $certgen\n";
	print "[2] $certgenkey\n";
	print "[3] $certimport\n";
	my $sel = "";
	while ($sel ne "1" && $sel ne "2" && $sel ne "3") {
		print "$badoplabel: $sel\n\n" if $sel ne "";
		print "[1|2|3] (1): ";
		$sel = <STDIN>;
		$sel = "" unless defined $sel;
		chomp($sel);
		}
	my %s = (mode => "generate", keymode => "new");
	if ($sel eq "2") {
		$s{keymode} = "existing";
		my $k = "";
		while ($k eq "" || !-e $k) {
			$k = textprompt($certkeyprompt) || "";
			print "File not found: $k\n\n" if $k ne "" && !-e $k;
			}
		$s{key} = $k;
		$s{keypass} = textpromptpass($certpassprompt, undef, "blank if none");
		}
	elsif ($sel eq "3") {
		$s{mode} = "import";
		my $c = "";
		while ($c eq "" || !-e $c) {
			$c = textprompt($certcertprompt) || "";
			print "File not found: $c\n\n" if $c ne "" && !-e $c;
			}
		$s{cert} = $c;
		my $k = "";
		while ($k eq "" || !-e $k) {
			$k = textprompt($keyfilel) || "";
			print "File not found: $k\n\n" if $k ne "" && !-e $k;
			}
		$s{key} = $k;
		$s{keypass} = textpromptpass($certpassprompt, undef, "blank if none");
		}
	return %s;
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

# Server FQDN (certificate name default). Tries the system FQDN first,
# then a reverse DNS lookup of the primary non-loopback address, and
# finally falls back to the short hostname.
#
sub detect_shost {
	my $h = `hostname 2>/dev/null`;
	chomp($h);
	$h = "" unless defined $h;
	my $fq;
	if ($h ne "") {
		my $f = `hostname -f 2>/dev/null`;
		chomp($f);
		$fq = $f if defined $f && $f ne $h && $f =~ /\./
			&& $f =~ /^[A-Za-z0-9_\.\-]+$/;
		}
	if (!defined $fq) {
		my $ip = detect_laddr();
		if (defined $ip) {
			my $packed = inet_aton($ip);
			if (defined $packed) {
				my $name = gethostbyaddr($packed, AF_INET);
				$fq = $name if defined $name && $name ne $h
					&& $name =~ /\./
					&& $name =~ /^[A-Za-z0-9_\.\-]+$/;
				}
			}
		}
	return $fq if defined $fq;
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
	my %c = collect_cert_text();
	print "\nReview:\n";
	print "  Install root:  $v{install_root}\n";
	print "  Server host:   $v{shost}\n";
	print "  Broker:        $v{laddr}:$v{lport}\n";
	print "  Web console:   port $v{wport}\n";
	print "  Certificate:   " . certdescription(\%c) . "\n";
	print "Proceed with installation? [y/N]: ";
	my $ans = <STDIN>;
	chomp($ans);
	exit 0 unless lc($ans) eq "y" || lc($ans) eq "yes";
	print "\e[?25l";
	runinstaller(buildparams(%v, \%c));
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
			-y		=> 8,
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
my $showCertDialog;

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
	if ($v{adminemail} eq "") {
		my $w = $win->add('emailwarndialog', 'Window',
			-centered	=> 1,
			-width		=> 68,
			-height		=> 12,
			-bg		=> 'white',
			-fg		=> 'black',
			-border		=> 1,
			-bfg		=> 'black',
			-bbg		=> 'white',
			);
		$w->add('emailwarnlabel', 'Label',
			-width		=> -1,
			-height		=> -1,
			-fg		=> 'black',
			-padleft	=> 2,
			-padright	=> 2,
			-padtop		=> 1,
			-text		=> wrap('', '', $emailreqlabel),
			);
		my $wb = $w->add('emailwarnbuttons', 'Buttonbox',
			-buttons => [ {
				-label		=> $okbutton,
				-value		=> "ok",
				-shortcut	=> "O",
				-onpress	=> sub { $win->delete('emailwarndialog'); $win->draw(); },
				} ],
			-fg		=> "black",
			-buttonalignment=> "right",
			-x		=> 2,
			-ipadright	=> 3,
			-y		=> 8,
			-selected	=> 1,
			);
		$wb->focus();
		return;
		}
	if ($v{adminpass} eq "") {
		my $w = $win->add('passwarndialog', 'Window',
			-centered	=> 1,
			-width		=> 68,
			-height		=> 12,
			-bg		=> 'white',
			-fg		=> 'black',
			-border		=> 1,
			-bfg		=> 'black',
			-bbg		=> 'white',
			);
		$w->add('passwarnlabel', 'Label',
			-width		=> -1,
			-height		=> -1,
			-fg		=> 'black',
			-padleft	=> 2,
			-padright	=> 2,
			-padtop		=> 1,
			-text		=> wrap('', '', $genpasslabel),
			);
		my $wb = $w->add('passwarnbuttons', 'Buttonbox',
			-buttons => [ {
				-label		=> $nobutton,
				-value		=> "no",
				-shortcut	=> $nobsc,
				-onpress	=> sub { $win->delete('passwarndialog'); $win->draw(); },
				},
			{
				-label		=> $yesbutton,
				-value		=> "yes",
				-shortcut	=> $yesbsc,
				-onpress	=> sub {
					$win->delete('passwarndialog');
					$paramsref = \%v;
					$win->delete('paramdialog');
					$win->draw();
					$showCertDialog->();
					},
				} ],
			-fg		=> "black",
			-buttonalignment=> "right",
			-x		=> 2,
			-ipadright	=> 3,
			-y		=> 8,
			-selected	=> 0,
			);
		$wb->focus();
		return;
		}
	$paramsref = \%v;
	$win->delete('paramdialog');
	$win->draw();
	$showCertDialog->();
	};

my $showParamDialog = sub {
	my ($defaults) = @_;
	$defaults ||= {};
	$changed = 1;
	my $dlg = $win->add('paramdialog', 'Window',
		-centered	=> 1,
		-width		=> 78,
		-height		=> 21,
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
		['dbadmin',      "DB Admin User",     $defaults->{dbadmin}      // $opt{dbadmin} // "root"],
		['dbadminpass',  "DB Admin Password", $defaults->{dbadminpass}  // $opt{dbadminpass} // ""],
		['dbpass',       "DB App Password",   $defaults->{dbpass}       // ""],
		['adminpass',    "Lumadmin Password", $defaults->{adminpass} // ""],
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
			-homeonblur => 0,
			);
		my $wtype = $f->[0] =~ /pass$/ ? 'PasswordEntry' : 'TextEntry';
		$pentry{$f->[0]} = $dlg->add($f->[0], $wtype, %eopts);
		$pentry{$f->[0]}->cursor_to_end() if length $eopts{-text};
		$y++;
		}
	$perr = $dlg->add('p_err', 'Label',
		-text => "", -fg => 'red', -width => -1, -height => 1,
		-x => 2, -y => 14,
		);
	my $buttons = $dlg->add('p_buttons', 'Buttonbox',
		-buttons => [ {
			-label		=> $exitbutton,
			-value		=> "cancel",
			-shortcut	=> $exitbsc,
			-onpress	=> $cancelAction,
			},
		{
			-label		=> $nextbutton,
			-value		=> "next",
			-shortcut	=> $nextbsc,
			-onpress	=> $paramAction,
			} ],
		-fg		=> "black",
		-buttonalignment => "right",
		-x		=> 2,
		-ipadright	=> 3,
		-y		=> 17,
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
	my %params = @_;
	# Offer to install missing dependencies before the installer fails
	# (Setup.pm detects them before any file is written). The callback
	# runs inside the installer, which blocks the mainloop, so the
	# dialog pumps events itself until a button is pressed.
	$params{deps_offer} = sub {
		my ($missing) = @_;
		my $text = "The following dependencies are missing:\n\n";
		$text .= "  $_\n" for @$missing;
		$text .= "\nInstall them now with the system package manager (I), or cancel the installation (C)?";
		local $Text::Wrap::columns = 64;
		$text = wrap('', '', $text);
		my $dlg = $win->add('depsdialog', 'Window',
			-centered => 1, -width => 74, -height => 18,
			-bg => 'white', -fg => 'black', -border => 1,
			-bfg => 'black', -bbg => 'white',
			);
		$dlg->add('depslabel', 'Label',
			-text => $text, -width => -1, -height => -1,
			-x => 2, -y => 2,
			);
		my $choice;
		$dlg->add('depsbuttons', 'Buttonbox',
			-buttons => [ {
				-label => " Cancel ", -value => "cancel",
				-onpress => sub { $choice = 0; $win->delete('depsdialog'); $win->draw(); },
				},
			{
				-label => " Install ", -value => "install",
				-onpress => sub { $choice = 1; $win->delete('depsdialog'); $win->draw(); },
				} ],
			-fg => "black", -buttonalignment => "right",
			-x => 2, -ipadright => 3, -y => 14, -selected => 1,
			);
		$dlg->get('depsbuttons')->focus();
		$win->draw();
		while (!defined $choice) {
			if ($win->can("handle_event")) {
				$win->handle_event();
				}
			else {
				require Curses;
				my $key = Curses::getch();
				if (defined $key && ($key eq "i" || $key eq "I" || $key == 10 || $key == 13)) {
					$choice = 1;
					$win->delete('depsdialog');
					$win->draw();
					}
				elsif (defined $key && ($key eq "c" || $key eq "C" || $key == 27)) {
					$choice = 0;
					$win->delete('depsdialog');
					$win->draw();
					}
				}
			}
		return $choice;
		};
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
	my $summary = "";
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
				my ($s, $r) = eval { Luminum::Setup::run(%params) };
				$summary = $s if defined $s;
				$rc = $r;
				$runerr = $@ if $@;
				POSIX::dup2(fileno($saveout), 1);
				POSIX::dup2(fileno($saveerr), 2);
				}
			close($saveout) if defined fileno($saveout);
			close($saveerr) if defined fileno($saveerr);
			close($fh);
			}
		else {
			my ($s, $r) = eval { Luminum::Setup::run(%params) };
			$summary = $s if defined $s;
			$rc = $r;
			$runerr = $@ if $@;
			}
		}
	$rc = 1 unless defined $rc;
	my $output = "";
	if (open(my $rfh, "<", $tmpout)) { $output = do { local $/; <$rfh> }; close($rfh); }
	unlink($tmpout);

	$status->delete('statuslabel');
	my $msg = $rc == 0
		? $summary
		: "Installation FAILED."
		  . ($runerr ne "" ? "\n\nError: $runerr" : "")
		  . ($output ne "" ? "\n\n" . substr($output, -1000) : "");
	{
		local $Text::Wrap::columns = 68;
		$msg = wrap('', '', $msg);
		}
	$status->add('statuslabel', 'Label',
		-text => $msg,
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
		-x => 2, -y => 19,
		-ipadright => 3,
		-selected => 0,
		);
	$status->draw;
	$status->getobj('statusbuttons')->focus();
	};

# Certificate dialogs: the first screen chooses how the server
# certificate/key are obtained; if the choice needs existing files
# (generate from an existing key, or import) a second screen collects
# the paths and passphrase.
#
my $cradio;
my $cerr;
my $cfsel;
my $cfcert;
my $cfkey;
my $cfpass;
my $cferr;
my $showCertFilesDialog;

my $certNextAction = sub {
	my $sel = $cradio->get();
	unless (defined $sel && $sel ne "") {
		$cerr->text($certnonsel);
		return;
		}
	$win->delete('certdialog');
	$win->draw();
	if ($sel eq "gen") {
		$doInstall->(buildparams(%$paramsref,
			{ mode => "generate", keymode => "new" }));
		}
	else {
		$showCertFilesDialog->($sel);
		}
	};

my $certBackAction = sub {
	$win->delete('certdialog');
	$win->draw();
	$showParamDialog->($paramsref);
	};

$showCertFilesDialog = sub {
	my ($sel) = @_;
	$cfsel = $sel;
	$changed = 1;
	my $dlg = $win->add('certfiledialog', 'Window',
		-centered	=> 1,
		-width		=> 78,
		-height	=> 13,
		-bg		=> 'white',
		-fg		=> 'black',
		-border		=> 1,
		-bfg		=> 'black',
		-bbg		=> 'white',
		);
	$dlg->add('cf_title', 'Label',
		-text => $certtitle, -bold => 1,
		-x => 2, -y => 1,
		);
	my @fields = $sel eq "import"
		? ( ['cfcert', $certfilel, 'TextEntry',     3],
			['cfkey',  $keyfilel,  'TextEntry',     4],
			['cfpass', $keypassl,  'PasswordEntry', 5] )
		: ( ['cfkey',  $keyfilel,  'TextEntry',     3],
			['cfpass', $keypassl,  'PasswordEntry', 4] );
	for my $f (@fields) {
		$dlg->add($f->[0] . "_l", 'Label',
			-text => $f->[1], -width => 20, -height => 1,
			-x => 2, -y => $f->[3],
			);
		$dlg->add($f->[0], $f->[2],
			-text => "", -width => 46,
			-x => 24, -y => $f->[3],
			-fg => 'white', -bg => 'darkgray',
			-homeonblur => 0,
			);
		}
	$cfcert = $dlg->getobj('cfcert');
	$cfkey  = $dlg->getobj('cfkey');
	$cfpass = $dlg->getobj('cfpass');
	$cferr = $dlg->add('cf_err', 'Label',
		-text => "", -fg => 'red', -width => -1, -height => 1,
		-x => 2, -y => 7,
		);
	my $cfaction = sub {
		my %s = (mode => "generate", keymode => "new");
		if ($cfsel eq "import") {
			$s{mode} = "import";
			$s{cert} = $cfcert->get() || "";
			$s{key}  = $cfkey->get() || "";
			$s{keypass} = $cfpass->get() || "";
			unless ($s{cert} ne "" && $s{key} ne "") {
				$cferr->text($certerr);
				return;
				}
			}
		else {
			$s{keymode} = "existing";
			$s{key} = $cfkey->get() || "";
			$s{keypass} = $cfpass->get() || "";
			unless ($s{key} ne "") {
				$cferr->text($certerrkey);
				return;
				}
			}
		$cferr->text("");
		$win->delete('certfiledialog');
		$win->draw();
		$doInstall->(buildparams(%$paramsref, \%s));
		};
	my $cfbackaction = sub {
		$win->delete('certfiledialog');
		$win->draw();
		$showCertDialog->();
		};
	my $buttons = $dlg->add('cf_buttons', 'Buttonbox',
		-buttons => [ {
			-label		=> $exitbutton,
			-value		=> "cancel",
			-shortcut	=> $exitbsc,
			-onpress	=> $cancelAction,
			},
		{
			-label		=> $backbutton,
			-value		=> "back",
			-shortcut	=> $backbsc,
			-onpress	=> $cfbackaction,
			},
		{
			-label		=> " Install ",
			-value		=> "install",
			-shortcut	=> "I",
			-onpress	=> $cfaction,
			} ],
		-fg		=> "black",
		-buttonalignment => "right",
		-x		=> 2,
		-ipadright	=> 3,
		-y		=> 9,
		-selected	=> 1,
		);
	($cfcert || $cfkey)->focus();
	};

$showCertDialog = sub {
	$changed = 1;
	my $dlg = $win->add('certdialog', 'Window',
		-centered	=> 1,
		-width		=> 78,
		-height	=> 13,
		-bg		=> 'white',
		-fg		=> 'black',
		-border		=> 1,
		-bfg		=> 'black',
		-bbg		=> 'white',
		);
	$dlg->add('c_title', 'Label',
		-text => $certtitle, -bold => 1,
		-x => 2, -y => 1,
		);
	# -height is mandatory: an auto-height listbox takes ALL remaining
	# parent rows, so its window would overlap the button row and erase
	# the buttons whenever the listbox is redrawn (i.e. while focused).
	$cradio = $dlg->add('c_radio', 'Radiobuttonbox',
		-values => ["gen", "genkey", "import"],
		-labels => {
			gen    => $certgen,
			genkey => $certgenkey,
			import => $certimport,
			},
		-selected => 0,
		-x => 2, -y => 3, -height => 3,
		);
	$cerr = $dlg->add('c_err', 'Label',
		-text => "", -fg => 'red', -width => -1, -height => 1,
		-x => 2, -y => 7,
		);
	my $buttons = $dlg->add('c_buttons', 'Buttonbox',
		-buttons => [ {
			-label		=> $exitbutton,
			-value		=> "cancel",
			-shortcut	=> $exitbsc,
			-onpress	=> $cancelAction,
			},
		{
			-label		=> $backbutton,
			-value		=> "back",
			-shortcut	=> $backbsc,
			-onpress	=> $certBackAction,
			},
		{
			-label		=> $nextbutton,
			-value		=> "next",
			-shortcut	=> $nextbsc,
			-onpress	=> $certNextAction,
			} ],
		-fg		=> "black",
		-buttonalignment => "right",
		-x		=> 2,
		-ipadright	=> 3,
		-y		=> 9,
		-selected	=> 1,
		);
	$cradio->focus();
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
					-y		=> 12,
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
	-y		=> 14,
	-selected	=> 1,
	);

$wizbuttons->focus();

$cui->mainloop();

exit 0;
