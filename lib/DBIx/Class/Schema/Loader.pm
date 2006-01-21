package DBIx::Class::Schema::Loader;

use strict;
use warnings;

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
    namespace               => "My",
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
  my $schema1 = My::Schema->connect();
  # ^^ defaults to dsn/user/pass from load_from_connection()

=head1 DESCRIPTION

DBIx::Class::Schema::Loader automate the definition of a
DBIx::Class::Schema by scanning table schemas and setting up
columns and primary keys.

DBIx::Class::Schema::Loader supports MySQL, Postgres, SQLite and DB2.  See
L<DBIx::Class::Schema::Loader::Generic> for more, and
L<DBIx::Class::Schema::Loader::Writing> for notes on writing your own
db-specific subclass for an unsupported db.

L<Class::DBI::Loader>, L<Class::DBI>, and L<DBIx::Class::Loader> are now
obsolete, use L<DBIx::Class> and this module instead. ;)

=cut

=head1 METHODS

=head2 new

Example in Synopsis above demonstrates the available arguments.  For
detailed information on the arguments, see the
L<DBIx::Class::Schema::Loader::Generic> documentation.

=cut

sub load_from_connection {
    my ( $class, %args ) = @_;

    foreach (qw/namespace dsn/) {
       die qq/Argument $_ is required/ if ! $args{$_};
    }

    $args{namespace} =~ s/(.*)::$/$1/;

    my $dsn = $args{dsn};
    my ($driver) = $dsn =~ m/^dbi:(\w*?)(?:\((.*?)\))?:/i;
    $driver = 'SQLite' if $driver eq 'SQLite2';
    my $impl = "DBIx::Class::Schema::Loader::" . $driver;

    $impl->require or
    die qq/Couldn't require loader class "$impl", "$UNIVERSAL::require::ERROR"/;

    push(@ISA, $impl);
    $class->_load_from_connection(%args);
}

=head1 AUTHOR

Sebastian Riedel, C<sri@oook.de>

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
