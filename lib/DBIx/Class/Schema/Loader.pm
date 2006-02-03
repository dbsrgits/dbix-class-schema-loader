package DBIx::Class::Schema::Loader;

use strict;
use warnings;
use Carp;
use UNIVERSAL::require;

use base qw/DBIx::Class::Schema/;
use base qw/Class::Data::Accessor/;

__PACKAGE__->mk_classaccessor('loader');

use vars qw($VERSION);

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

  # Get a list of the original (database) names of the tables that
  #  were loaded
  my @tables = $schema1->loader->tables;

  # Get a hashref of table_name => 'TableName' table-to-moniker
  #   mappings.
  my $monikers = $schema1->loader->monikers;

  # Get a hashref of table_name => 'My::Schema::TableName'
  #   table-to-classname mappings.
  my $classes = $schema1->loader->classes;

  # Use the schema as per normal for L<DBIx::Class::Schema>
  my $rs = $schema1->resultset($monikers->{table_table})->search(...);

=head1 DESCRIPTION

THIS IS A DEVELOPMENT RELEASE.  This is 0.01000, the first public
release.  Expect things to be broken in various ways.  Expect the
entire design to be fatally flawed.  Expect the interfaces to change if
it becomes neccessary.  It's mostly here for people to poke at it and
find the flaws in it.  0.02 will hopefully have some sanity when we get
there.

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

    $args{schema} = $class;

    $class->loader($impl->new(%args));
    $class->loader->load;
}

=head1 AUTHOR

Brandon Black, C<bblack@gmail.com>

Based on L<DBIx::Class::Loader> by Sebastian Riedel

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
