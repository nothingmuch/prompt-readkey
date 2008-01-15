#!/usr/bin/perl

use strict;
use warnings;

use Test::More 'no_plan';

use ok 'Prompt::ReadKey';

our ( @read_ret, $print_ret );
our ( @read_called, @print_called );

{
	package MockPrompter;
	use Moose;

	extends qw(Prompt::ReadKey);

	sub read_key {
		push @read_called, [@_];
		shift @read_ret;
	}

	sub _print {
		push @print_called, [@_];
		$print_ret;
	}
}

my $t = MockPrompter->new(
	default_prompt => "foo",
	default_options => [
		{ name => "one", default => 1 },
		{ name => "two" },
	],
);

$print_ret = 1;

{
	local @read_ret = ( 'o' );
	local @read_called;
	local @print_called;

	is( $t->prompt, "one", "option one" );

	is( @read_called, 1, "read once" );

	is( @print_called, 1, "printed once" );
	is_deeply( \@print_called, [ [ $t, "foo [Ot] " ] ], "print arguments" );
}

{
	local @read_ret = ( 't' );
	local @read_called;
	local @print_called;

	is( $t->prompt, "two", "option one" );

	is( @read_called, 1, "read once" );
	is( @print_called, 1, "printed once" );
}

{
	local @read_ret = ( 'o' );
	local @read_called;
	local @print_called;

	is( $t->prompt( case_insensitive => 0 ), "one", "option one" );

	is( @read_called, 1, "read once" );

	is( @print_called, 1, "printed once" );
	is_deeply( \@print_called, [ [ $t, "foo [ot] " ] ], "print arguments" );
}

{
	local @read_ret = ( "\n" );
	local @read_called;
	local @print_called;

	is( $t->prompt, "one", "option one (the default)" );

	is( @read_called, 1, "read once" );

	is( @print_called, 1, "printed once" );
	is_deeply( \@print_called, [ [ $t, "foo [Ot] " ] ], "print arguments" );
}

{
	local @read_ret = ( 'x', 'o' );
	local @read_called;
	local @print_called;

	is( $t->prompt, "one", "option one" );

	is( @read_called, 2, "read twice" );

	is( @print_called, 3, "printed three times" );
	is_deeply(
		\@print_called,
		[
			[ $t, "foo [Ot] " ],
			[ $t, "'x' is not a valid choice, please select one of the options. Enter 'h' for help." ],
			[ $t, "foo [Ot] " ],
		],
		"print arguments",
	);
}

{
	local @read_ret = ( 'h', 'o' );
	local @read_called;
	local @print_called;

	is( $t->prompt, "one", "option one" );

	is( @read_called, 2, "read twice" );

	is( @print_called, 3, "printed three times" );
	is_deeply(
		\@print_called,
		[
			[ $t, "foo [Ot] " ],
			[ $t, "FIXME help message" ],
			[ $t, "foo [Ot] " ],
		],
		"print arguments",
	);
}