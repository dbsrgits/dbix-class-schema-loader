package DBIx::Class::Schema::Loader::DBI::ODBC;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI';
use Carp::Clan qw/^DBIx::Class/;
use Class::C3;

our $VERSION = '0.04999_09';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::ODBC - L<DBD::ODBC> proxy, currently only for
Microsoft SQL Server

=head1 DESCRIPTION

Reblesses into L<DBIx::Class::Schema::Loader::DBI::ODBC::Microsoft_SQL_Server>,
which is a proxy for L<DBIx::Class::Schema::Loader::DBI::MSSQL> when using the
L<DBD::ODBC> driver with Microsoft SQL Server.

Code stolen from the L<DBIx::Class> ODBC storage.

See L<DBIx::Class::Schema::Loader::Base> for usage information.

=cut

sub _rebless {
  my $self = shift;
  my $dbh  = $self->schema->storage->dbh;

# stolen from DBIC ODBC storage
  my $dbtype = eval { $dbh->get_info(17) };
  unless ( $@ ) {
    # Translate the backend name into a perl identifier
    $dbtype =~ s/\W/_/gi;
    my $class = "DBIx::Class::Schema::Loader::DBI::ODBC::${dbtype}";
    if ($self->load_optional_class($class) && !$self->isa($class)) {
        bless $self, $class;
        $self->_rebless;
    }
  }
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader::DBI::ODBC::Microsoft_SQL_Server>,
L<DBIx::Class::Schema::Loader::DBI::MSSQL>,
L<DBIx::Class::Schema::Loader>, L<DBIx::Class::Schema::Loader::Base>,
L<DBIx::Class::Schema::Loader::DBI>

=head1 AUTHOR

Rafael Kitover C<rkitover@cpan.org>

=cut

1;
