#!/usr/bin/perl -w
#
# Luminum Server Setup Wizard
# by Christopher R. Curzio (ccurzio@luminum.net)

use strict;
use Term::ReadKey;
use Term::ANSIColor;
use Text::Wrap;

my $text = 0;
my $step = 0;
my $lang;
my $win;
my $label;
my $wizard;
my $wizlabel;
my $wizbuttons;
my $wizaction;
my $path = "/opt/Luminum/LuminumServer";
my $LADDR;
my $LPORT;
my $WADDR;
my $WPORT;

my $mainlabel;
my $breaklabel;
my $introlabel;
my $abortlabel;
my $existlabel;
my $iconflabel;
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
	$iconflabel = "Importing Configuration";
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
	$iconflabel = "Konfiguration importieren";
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
	$iconflabel = "Importazione della configurazione";
	$badoplabel = "Opzione non valida";
	$reconfbutton = " Riconfigura ";
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
	$breaklabel = "REMARQUE : Utilisez Ctrl+C pour annuler la configuration à tout moment. Les modifications non enregistrées seront perdues.";
	$introlabel = "Bienvenue dans l'assistant d'installation de Luminum Server. Cet outil vous guidera pas à pas pour installer Luminum Server sur votre système.";
	$existlabel = "Une configuration de serveur Luminum existante a été trouvée:";
	$rconflabel = "Voulez-vous [r]econfigurer le système ou [c]réer une nouvelle configuration?";
	$reconfsc = "R";
	$newconfsc = "C";
	$iconflabel = "Importation de la configuration";
	$badoplabel = "Option invalide";
	$reconfbutton = " Reconfigurer ";
	$newconfbutton = " Nouvelle Conf. ";
	$nocurseslabel = "Curses::UI n'est pas disponible. Lancez l'installation avec --textonly pour une interface en mode texte.";
	$cancelwarnlabel = "Les modifications non enregistrées seront perdues. Voulez-vous vraiment annuler?";
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
	$iconflabel = "Importación de configuración";
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

foreach (@ARGV) {
	if ($_ =~ /--textonly/) { $text = 1; }
	}

if ($text == 0) {
	eval { require Curses::UI; Curses::UI->import() };
	if ($@) {
		print "$nocurseslabel\n";
		exit(1);
		}
	}

if ($text == 0) {
	$Text::Wrap::columns = 70;
	my $cui = new Curses::UI(-color_support => 1, -intellidraw => 1);
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
				-ipadtop	=> 8,
				-selected	=> 0,
				);
			$warnbuttons->focus();
			}
		else {
			print "\e[?25h"; exit(0);
			}
		};

	$wizard = $win->add('welcdialog','Window',
		-centered	=> 1,
		-width		=> 76,
		-height		=> 28,
		-bg		=> 'white',
		-fg		=> 'black',
		-border		=> 1,
		-bfg		=> 'black',
		-bbg		=> 'white',
		);

	$wizlabel = $wizard->add('wizlabel', 'Label',
		-width		=> -1,
		-height		=> -1,
		-fg		=> 'black',
		-padleft	=> 2,
		-padright	=> 2,
		-padtop		=> 1,
		-text		=> wrap('', '', $introlabel) . "\n\n" . wrap('', '', $breaklabel)
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
				if (-e "$path/config/server.conf.db") {
					my $confwin = $win->add('confdialog', 'Window',
						-centered	=> 1,
						-width		=> 76,
						-height		=> 28,
						-bg		=> 'white',
						-fg		=> 'black',
						-border		=> 1,
						-bfg		=> 'black',
						-bbg		=> 'white',
						);
					$confwin->add('conflabel', 'Label',
						-width		=> -1,
						-height		=> -1,
						-fg		=> 'black',
						-padleft	=> 2,
						-padright	=> 2,
						-padtop		=> 1,
						-text		=> "$existlabel\n\n  $path/config/server.conf.db\n\n$rconflabel",
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
							-onpress	=> sub { },
							},
						{
							-label		=> $reconfbutton,
							-value		=> "reconf",
							-shortcut	=> $reconfsc,
							-onpress	=> sub { },
							} ],
						-fg		=> "black",
						-buttonalignment=> "right",
						-x		=> 2,
						-ipadright	=> 3,
						-ipadtop	=> 22,
						-selected	=> 2,
						);
					$confbuttons->focus();
					}
				else {
					}
				},
			} ],
		-fg		=> "black",
		-buttonalignment=> "right",
		-x		=> 2,
		-ipadright	=> 3,
		-ipadtop	=> 24,
		-width		=> 20,
		-selected	=> 1,
		);

	$wizbuttons->focus();

	$cui->mainloop();
	}
else {
	$nextbutton =~ s/ \>//;
	$SIG{INT} = sub {
		ReadMode ('normal');
		print "\e[?25h";
		system(`/usr/bin/which clear`);
		print "Luminum Server setup aborted.\n\n";
		exit(0);
		};
	print "\e[?25l";
	system(`/usr/bin/which clear`);
	print "$mainlabel\n\n";
	print "$introlabel\n\n";
	print "$breaklabel\n\n";
	print "[$nextbutton]";
	ReadMode ('noecho');
	my $wiznext = <STDIN>;

	print "\e[?25h";
	ReadMode ('normal');
	system(`/usr/bin/which clear`);
	print "$mainlabel\n\n";

	if (-e "/opt/Luminum/LuminumServer/config/server.conf.db") {
		my $prompt = 0;
		my $useconf = "";
		print "$existlabel\n";
		print "- ";
		print color('bold blue');
		print "/opt/Luminum/LuminumServer/config/server.conf.db\n\n";
		print color('reset');
		print "$rconflabel\n\n";
		while (lc($useconf) ne lc($reconfsc) && lc($useconf) ne lc($newconfsc)) {
			if ($prompt == 1) { print "$badoplabel\: $useconf\n\n"; $useconf = ""; }
			$prompt = 1;
			print "[$reconfsc|$newconfsc]: ";
			$useconf = <STDIN>;
			chomp($useconf);
			}
		$prompt = 0;
		if (lc($useconf) eq lc($reconfsc)) {
			print "$iconflabel\...";
			}

		print "\e[?25h";
		ReadMode ('normal');
		system(`/usr/bin/which clear`);
		print "$mainlabel\n\n";
		}
	}

sub createCert {
	}

sub createPrvKey {
	}

sub createPubKey {
	}

exit;
