package DBIx::Class::Schema::Loader;

use strict;
use warnings;
use Carp;

use vars qw($VERSION @ISA);
use UNIVERSAL::require;

# Always remember to do all digits for the version even if they're 0
# i.e. first release of 0.XX *must* be 0.XX000. This avoids fBSD ports
# brain damage and presumably various other packaging systems too

$VERSION = '0.01000';

=head1 NAME

DBIx::Class::Schema::Loader - Dynamic definition of a DBIx::Class::Schema

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->load_from_connection(
    dsn                     => "dbi:mysql:dbname",
    user                    => "root",
    password                => "",
    additional_classes      => [qw/DBIx::Class::Foo/],
    additional_base_classes => [qw/My::Stuff/],
    left_base_classes       => [qw/DBIx::Class::Bar/],
    constraint              => '^foo.*',
    relationships           => 1,
    options                 => { AutoCommit => 1 }, 
    inflect                 => { child => 'children' },
    debug                   => 1,
  );

  # in seperate application code ...

  use My::Schema;

  my $schema1 = My::Schema->connect( $dsn, $user, $password, $attrs);
  # -or-
  my $schema1 = "My::Schema";
  # ^^ defaults to dsn/user/pass from load_from_connection()

=head1 DESCRIPTION

DBIx::Class::Schema::Loader automates the definition of a
DBIx::Class::Schema by scanning table schemas and setting up
columns and primary keys.

DBIx::Class::Schema::Loader supports MySQL, Postgres, SQLite and DB2.  See
L<DBIx::Class::Schema::Loader::Generic> for more, and
L<DBIx::Class::Schema::Loader::Writing> for notes on writing your own
db-specific subclass for an unsupported db.

This module requires DBIx::Class::Loader 0.5 or later, and obsoletes
L<DBIx::Class::Loader> for L<DBIx::Class> version 0.5 and later.

=cut

=head1 METHODS

=head2 load_from_connection

Example in Synopsis above demonstrates the available arguments.  For
detailed information on the arguments, see the
L<DBIx::Class::Schema::Loader::Generic> documentation.

=cut

sub load_from_connection {
    my ( $class, %args ) = @_;

    croak 'dsn argument is required' if ! $args{dsn};

    my $dsn = $args{dsn};
    my ($driver) = $dsn =~ m/^dbi:(\w*?)(?:\((.*?)\))?:/i;
    $driver = 'SQLite' if $driver eq 'SQLite2';
    my $impl = "DBIx::Class::Schema::Loader::" . $driver;

    $impl->require or
      croak qq/Couldn't require loader class "$impl",/ .
            qq/"$UNIVERSAL::require::ERROR"/;

    push(@ISA, $impl);
    $class->_load_from_connection(%args);
}

=head1 AUTHOR

Brandon Black, C<bblack@gmail.com>

Sebastian Riedel, C<sri@oook.de> (DBIx::Class::Loader, which this module is branched from)

Based upon the work of IKEBE Tomohiro

=head1 THANK YOU

Adam Anderson, Andy Grundman, Autrijus Tang, Dan Kubb, David Naughton,
Randal Schwartz, Simon Flack and all the others who've helped.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

L<DBIx::Class>

=cut

1;
