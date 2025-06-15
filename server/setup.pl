#!/usr/bin/perl -w
#
# Luminum Server Setup Wizard
# by Christopher R. Curzio (ccurzio@luminum.net)

use strict;
use Curses::UI;

my $text = 0;
my $cancel = 0;
my $wizback = " Cancel ";
my $wizbs = "C";
my $wiznext = " Next ";
my $wizns = "N";
my $path = "/opt/Luminum/LuminumServer";
my $LADDR;
my $LPORT;
my $WADDR;
my $WPORT;

my $cui = new Curses::UI(-color_support => 1, -intellidraw => 1);
$cui->set_binding(sub { exit(0); }, "\cC");

foreach (@ARGV) {
	if ($_ =~ /--textonly/) { $text = 1; }
	}

if ($text == 0) {
	my $win = $cui->add('base', 'Window');
	my $label = $win->add('setuplabel', 'Label',
		-bg	=> "blue",
		-text	=> "Luminum Server Setup\n--------------------",
		-bold	=> 1,
		-width	=> -1,
		-height	=> -1,
		);
	$label->draw;

	my $wizard = $win->add('welcdialog','Window',
		-centered	=> 1,
		-width		=> 78,
		-height		=> 30,
		-bg		=> 'white',
		-fg		=> 'black',
		);

	my $wizbuttons = $wizard->add('wizbuttons','Buttonbox',
		-buttons => [ {
			-label		=> "$wizback",
			-value		=> "back",
			-shortcut	=> "$wizbs",
			},
		{
			-label		=> $wiznext,
			-value		=> "next",
			-shortcut	=> "$wizns",
			} ],
		-fg		=> "black",
		-buttonalignment=> "right",
		-ipadright	=> 3,
		-ipadtop	=> 28
		-width		=> 20,
		-selected	=> 1,
		);

	$wizbuttons->focus();
	my $wizcancel = $wizbuttons->get();

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
