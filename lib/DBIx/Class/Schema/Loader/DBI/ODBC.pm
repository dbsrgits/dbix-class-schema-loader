package DBIx::Class::Schema::Loader::DBI::ODBC;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI';
use Carp::Clan qw/^DBIx::Class/;
use Class::C3;

our $VERSION = '0.04999_06';

sub _rebless {
  my $self = shift;
  my $dbh  = $self->schema->storage->dbh;

# stolen from DBIC ODBC driver for MSSQL
  my $dbtype = eval { $dbh->get_info(17) };
  unless ( $@ ) {
    # Translate the backend name into a perl identifier
    $dbtype =~ s/\W/_/gi;
    my $class = "DBIx::Class::Schema::Loader::DBI::ODBC::${dbtype}";
    eval "require $class";
    bless $self, $class unless $@;
  }
}

1;
