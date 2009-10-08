package DBIx::Class::Schema::Loader::DBI::Sybase::Microsoft_SQL_Server;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI::MSSQL';
use Carp::Clan qw/^DBIx::Class/;
use Class::C3;

our $VERSION = '0.04999_09';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::Sybase::Microsoft_SQL_Server - Subclass for
using MSSQL through DBD::Sybase

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader::Base>.

Subclasses L<DBIx::Class::Schema::Loader::DBI::MSSQL>.

=cut

# Returns an array of table names
sub _tables_list { 
    my $self = shift;

    my ($table, $type) = @_ ? @_ : ('%', '%');

    my $dbh = $self->schema->storage->dbh;
    my @tables = $dbh->tables(undef, $self->db_schema, $table, $type);

    return @tables;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader::DBI::Sybase>,
L<DBIx::Class::Schema::Loader::DBI::MSSQL>,
L<DBIx::Class::Schema::Loader::DBI>
L<DBIx::Class::Schema::Loader>, L<DBIx::Class::Schema::Loader::Base>,

=head1 AUTHOR

Rafael Kitover <rkitover@cpan.org>

=cut

1;
