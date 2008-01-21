#!/usr/bin/perl -w

use strict;

use ExtUtils::MakeMaker;

WriteMakefile(
	NAME         => 'Prompt::ReadKey',
	VERSION_FROM => 'lib/Prompt/ReadKey.pm',
	INSTALLDIRS  => 'site',
	SIGN         => 1,
	PL_FILES     => { },
	PREREQ_PM    => {
		'Test::use::ok' => 0,
		'Moose' => '0.33',
		'Text::Table' => 0,
		'Term::ReadKey' => 0,
		'Scalar::Util' => 0,
		'List::Util' => 0,
		'Text::Sprintf::Named' => 0,
		'Set::Object' => 0,
	},
);

