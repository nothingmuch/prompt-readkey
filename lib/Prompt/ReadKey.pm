#!/usr/bin/perl

package Prompt::ReadKey;
use Moose;

use Moose::Util::TypeConstraints;

use Carp qw(croak);
use Term::ReadKey;
use List::Util qw(first);
use Text::Table;

our $VERSION = "0.01";

has default_prompt => (
	isa => "Str",
	is  => "rw",
);

has additional_options => (
	isa => "ArrayRef[HashRef]",
	is  => "rw",
	auto_deref => 1,
);

has auto_help => (
	isa => "Bool",
	is  => "rw",
	default => 1,
);

has help_headings => (
	isa => "ArrayRef[HashRef[Str]]",
	is  => "rw",
	default => sub {[
		{ name => "keys", heading => "Key" },
		{ name => "name", heading => "Name" },
		{ name => "doc",  heading => "Description" },
	]},
);

has help_header => (
	isa => "Str",
	is  => "rw",
	default => "The list of available commands is:",
);

has help_footer => (
	isa => "Str",
	is  => "rw",
);

subtype Char => as Str => where { length == 1 };

has help_keys => (
	isa => "ArrayRef[Char]",
	is  => "rw",
	auto_deref => 1,
	default => sub { [qw(h ?)] },
);

has default_options => (
	isa => "ArrayRef[HashRef]",
	is  => "rw",
	auto_deref => 1,
);

has allow_duplicate_names => (
	isa => "Bool",
	is  => "rw",
	default => 0,
);

has readkey_mode => (
	isa => "Int",
	is  => "rw",
	default => 0, # normal getc, change to get timed
);

has readmode => (
	isa => "Int",
	is  => "rw",
	default => 3, # cbreak mode
);

has echo_key => (
	isa => "Bool",
	is  => "rw",
	default => 1,
);

has auto_newline => (
	isa => "Bool",
	is  => "rw",
	default => 1,
);

has return_name => (
	isa => "Bool",
	is  => "rw",
	default => 1,
);

has case_insensitive => (
	isa => "Bool",
	is  => "rw",
	default => 1,
);

has repeat_until_valid => (
	isa => "Bool",
	is  => "rw",
	default => 1,
);

sub _deref ($) {
	my $ret = shift;

	if ( wantarray and (ref($ret)||'') eq 'ARRAY' ) {
		return @$ret;
	} else {
		return $ret;
	}
}

sub _get_arg ($\%) {
	my ( $name, $args ) = @_;
	_deref( __get_arg( $name, $args ) );
}

sub _get_arg_or_default {
	my ( $self, $name, %args ) = @_;

	if ( exists $args{$name} ) {
		_get_arg($name, %args);
	} else {
		my $method = ( ( $name =~ m/^(?: prompt | options )$/x ) ? "default_$name" : $name );
		if ( $self->can($method) ) {
			return _deref($self->$method());
		}
	}
}

sub __get_arg  {
	my ( $name, $args ) = @_;
	$args->{$name};
}

sub prompt {
	my ( $self, %args ) = @_;

	my @options = $self->prepare_options(%args);

	$self->do_prompt(
		%args,
		options => \@options,
		prompt  => $self->format_prompt( %args, options => \@options ),
	);
}

sub do_prompt {
	my ( $self, %args ) = @_;

	my $repeat = $self->_get_arg_or_default( repeat_until_valid => %args );

	prompt: {
		if ( my $opt = $self->prompt_once(%args) ) {

			if ( $opt->{reprompt_after} ) { # help, etc
				$self->option_to_return_value(%args, option => $opt); # trigger callback
				redo prompt;
			}

			return $self->option_to_return_value(%args, option => $opt);
		}

		redo prompt if $repeat;
	}

	return;
}

sub prompt_once {
	my ( $self, %args ) = @_;

	$self->print_prompt(%args);
	$self->read_option(%args);
}

sub print_prompt {
	my ( $self, %args ) = @_;
	$self->print($self->_get_arg_or_default( prompt => %args ));
}

sub print {
	my ( $self, @args ) = @_;
	local $| = 1;
	print @args;
}

sub prepare_options {
	my ( $self, %args ) = @_;

	$self->filter_options(
		%args,
		options => [
			$self->sort_options(
				%args,
				options => [
					$self->process_options(
						%args,
						options => [ $self->gather_options(%args) ]
					),
				],
			),
		],
	);
}

sub process_options {
	my ( $self, %args ) = @_;
	map { $self->process_option( %args, option => $_ ) } $self->_get_arg_or_default(options => %args);
}

sub process_option {
	my ( $self, %args ) = @_;
	my $opt = $args{option};

	my @keys = $opt->{key} ? $opt->{key} : @{ $opt->{keys} || [] };

	unless ( @keys ) {
		croak "either 'key', 'keys', or 'name' is a required option" unless $opt->{name};
		@keys = ( substr $opt->{name}, 0, 1 );
	}

	return {
		%$opt,
		keys => \@keys,
	};
}

sub gather_options {
	my ( $self, @args ) = @_;

	return (
		$self->_get_arg_or_default(options => @args),
		$self->additional_options(),
		$self->create_help_option(@args),
	);
}

sub get_help_keys {
	my ( $self, @args ) = @_;

	if ( $self->_get_arg_or_default( auto_help => @args ) ) {
		return $self->_get_arg_or_default( help_keys => @args );
	}
}

sub create_help_option {
	my ( $self, @args ) = @_;

	if ( my @keys = $self->get_help_keys(@args) ) {
		return {
			reprompt_after => 1,
			doc            => "List available commands",
			name           => "help",
			keys           => \@keys,
			callback       => "display_help",
			is_help        => 1,
		}
	}

	return;
}

sub display_help {
	my ( $self, @args ) = @_;

	my @options = $self->_get_arg_or_default(options => @args);

	my $help = join("\n\n", grep { defined }
		$self->_get_arg_or_default(help_header => @args),
		$self->tabulate_help_text( @args, help_table => [ map { $self->option_to_help_text(@args, option => $_) } @options ] ),
		$self->_get_arg_or_default(help_footer => @args),
	);

	$self->print("\n$help\n\n");
}

sub tabulate_help_text {
	my ( $self, %args ) = @_;

	my @headings = $self->_get_arg_or_default( help_headings => %args );

	my $table = Text::Table->new( map { $_->{heading}, \"   " } @headings );

	my @rows = _get_arg( help_table => %args );

	$table->load( map {
		my $row = $_;
		[ map { $row->{ $_->{name} } } @headings ];
	} @rows );

	$table->body_rule("   ");

	return $table;
}

sub option_to_help_text {
	my ( $self, %args ) = @_;
	my $opt = $args{option};

	return {
		keys => join(", ", @{ $opt->{keys} } ),
		name => $opt->{name} || "",
		doc => $opt->{doc}  || "",
	};
}

sub sort_options {
	my ( $self, @args ) = @_;
	$self->_get_arg_or_default(options => @args);
}

sub filter_options {
	my ( $self, %args ) = @_;

	my @options = $self->_get_arg_or_default(options => %args);

	croak "No more than one default is allowed" if 1 < scalar grep { $_->{default} } @options;

	foreach my $field ( "keys", ( $self->_get_arg_or_default( allow_duplicate_names => %args ) ? "name" : () ) ) {
		my %idx;

		foreach my $option ( @options ) {
			my $value = $option->{$field};
			my @values = ref($value) ? @$value : $value;
			push @{ $idx{$_} ||= [] }, $option for grep { defined } @values;
		}

		foreach my $key ( keys %idx ) {
			delete $idx{$key} if @{ $idx{$key} } == 1;
		}

		if ( keys %idx ) {
			# FIXME this error sucks
			require Data::Dumper;
			croak "duplicate value for '$field': " . Dumper(\%idx);
		}
	}

	return @options;
}

sub prompt_string {
	my ( $self, %args ) = @_;
	$self->_get_arg_or_default(prompt => %args) || croak "'prompt' argument is required";
}

sub format_options {
	my ( $self, %args ) = @_;

	my @options = grep { not $_->{is_help} } $self->_get_arg_or_default(options => %args);

	if ( $self->_get_arg_or_default( case_insensitive => %args ) ) {
		return join "", map {
			my $default = $_->{default};
			map { $default ? uc : lc } @{ $_->{keys} };
		} @options;
	} else {
		return join "", map { @{ $_->{keys} } } @options;
	}
}

sub format_prompt {
	my ( $self, %args ) = @_;

	sprintf "%s [%s] ", $self->prompt_string(%args), $self->format_options(%args);
}

sub read_option {
	my ( $self, %args ) = @_;

	my @options = $self->_get_arg_or_default(options => %args);

	my %by_key = map {
		my $opt = $_;
		map { $_ => $opt } @{ $_->{keys} };
	} @options;

	my $c = $self->process_char( %args, char => $self->read_key(%args) );

	if ( defined $c ) {
		if ( exists $by_key{$c} ) {
			return $by_key{$c};
		} elsif ( $c =~ /^\s+$/ ) {
			return first { $_->{default} } @options;
		}
	}

	$self->invalid_choice(%args, char => $c);

	return;
}

sub invalid_choice {
	my ( $self, %args ) = @_;

	my $output;

	if ( defined ( my $c = $args{char} ) ) {
		$output = "'$c' is not a valid choice, please select one of the options.";
	} else {
		$output = "Invalid input, please select one of the options.";
	}

	if ( my @keys = $self->get_help_keys(%args) ) {
		$output .= " Enter '$keys[0]' for help.";
	}

	$self->print($output);
}

sub option_to_return_value {
	my ( $self, %args ) = @_;

	my $opt = $args{option};

	if ( my $cb = $opt->{callback} ) {
		return $self->$cb(%args);
	} else {
		return (
			$self->return_name
				? $opt->{name}
				: $opt
		);
	}
}

sub read_key {
	my ( $self, %args ) = @_;

    ReadMode( $self->_get_arg_or_default( readmode => %args ) );

	my $sigint = $SIG{INT} || sub { exit 1 };

    local $SIG{INT} = sub {
		ReadMode(0);
		print "\n" if $self->_get_arg_or_default( auto_newline => %args );
		$sigint->();
	};

    my $c = ReadKey( $self->_get_arg_or_default( readkey_mode => %args ) );

    ReadMode(0);

    die "Error reading key from user: $!" unless defined($c);

    print $c if $self->_get_arg_or_default( echo_key => %args );

    print "\n" if $c ne "\n" and $self->_get_arg_or_default( auto_newline => %args );

    return $c;
}

sub process_char {
	my ( $self, %args ) = @_;

	my $c = $args{char};

	if ( $self->_get_arg_or_default( case_insensitive => %args ) ) {
		return lc($c);
	} else {
		return $c;
	}
}

__PACKAGE__

__END__
