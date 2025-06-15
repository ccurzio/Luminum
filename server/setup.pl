#!/usr/bin/perl -w
#
# Luminum Server Setup Wizard
# by Christopher R. Curzio (ccurzio@luminum.net)

use strict;
use Curses::UI;

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

my $introlabel;
my $nextbutton;
my $backbutton;
my $exitbutton;
my $nextbsc;
my $backbsc;
my $exitbsc;

if ($ENV{LANG} =~ /en_/ || $ENV{LANG} eq "") {
	$lang = "EN";
	$nextbutton = " Next > ";
	$backbutton = " < Back ";
	$exitbutton = " Cancel ";
	$nextbsc = "N";
	$backbsc = "B";
	$exitbsc = "C";
	$introlabel = "Welcome to the Luminum Server setup wizard. This tool will guide you\nthrough the steps to install Luminum Server on this system.";
	}
elsif ($ENV{LANG} =~ /de_/) {
	$lang = "DE";
	$nextbutton = " Nächste > ";
	$backbutton = "< Zurück ";
	$exitbutton = " Stornieren ";
	$nextbsc = "N";
	$backbsc = "Z";
	$exitbsc = "S";
	$introlabel = "Willkommen beim Luminum Server-Setup-Assistenten. Dieses Tool führt\nSie durch die einzelnen Schritte zur Installation von Luminum Server\nauf diesem System.";
	}
elsif ($ENV{LANG} =~ /it_/) {
	$lang = "IT";
	$nextbutton = " Prossimo > ";
	$backbutton = "< Precedente ";
	$exitbutton = " Cancellare ";
	$nextbsc = "P";
	$backbsc = "r";
	$exitbsc = "C";
	$introlabel = "Benvenuti alla procedura guidata di installazione di Luminum Server.\nQuesto strumento vi guiderà attraverso i passaggi necessari per\ninstallare Luminum Server su questo sistema.";
	}
elsif ($ENV{LANG} =~ /fr_/) {
	$lang = "FR";
	$nextbutton = " Suivant > ";
	$backbutton = "< Précédent ";
	$exitbutton = " Annuler ";
	$nextbsc = "S";
	$backbsc = "P";
	$exitbsc = "A";
	$introlabel = "Bienvenue dans l'assistant d'installation de Luminum Server. Cet\noutil vous guidera pas à pas pour installer Luminum Server\nsur votre système.";
	}
elsif ($ENV{LANG} =~ /es_/) {
	$lang = "ES";
	$nextbutton = " Próximo >";
	$backbutton = "< Previo ";
	$exitbutton = " Cancelar ";
	$nextbsc = "P";
	$backbsc = "v";
	$exitbsc = "C";
	$introlabel = "Bienvenido al asistente de configuración de Luminum Server. Esta\nherramienta le guiará por los pasos para instalar Luminum\nServer en este sistema.";
	}

my $cui = new Curses::UI(-color_support => 1, -intellidraw => 1);
$cui->set_binding(sub { exit(0); }, "\cC");

foreach (@ARGV) {
	if ($_ =~ /--textonly/) { $text = 1; }
	}

if ($text == 0) {
	$win = $cui->add('base', 'Window');
	$label = $win->add('setuplabel', 'Label',
		-bg	=> "blue",
		-text	=> "Luminum Server Setup\n--------------------",
		-bold	=> 1,
		-width	=> -1,
		-height	=> -1,
		);
	$label->draw;

	$wizard = $win->add('welcdialog','Window',
		-centered	=> 1,
		-width		=> 78,
		-height		=> 30,
		-bg		=> 'white',
		-fg		=> 'black',
		);

	$wizlabel = $wizard->add('wizlabel', 'Label',
		-width		=> -1,
		-height		=> -1,
		-fg		=> 'black',
		-padleft	=> 2,
		-padright	=> 2,
		-padtop		=> 1,
		-text		=> $introlabel
		);

	$wizbuttons = $wizard->add('wizbuttons','Buttonbox',
		-buttons => [ {
			-label		=> $exitbutton,
			-value		=> "exit",
			-shortcut	=> $exitbsc,
			},
		{
			-label		=> $nextbutton,
			-value		=> "next",
			-shortcut	=> $nextbsc,
			} ],
		-fg		=> "black",
		-buttonalignment=> "right",
		-ipadright	=> 3,
		-ipadtop	=> 28
		-width		=> 20,
		-selected	=> 1,
		);

	my $wizaction = $wizbuttons->get();
	$wizbuttons->focus();

	$cui->mainloop();
	}
else {
	}

sub createCert {
	}

sub createPrvKey {
	}

sub createPubKey {
	}

exit;
