package DBIx::Class::Schema::Loader::Pg;

use strict;
use warnings;
use Class::C3;
use base 'DBIx::Class::Schema::Loader::Generic';

=head1 NAME

DBIx::Class::Schema::Loader::Pg - DBIx::Class::Schema::Loader Postgres Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->load_from_connection(
    dsn       => "dbi:Pg:dbname=dbname",
    user      => "postgres",
    password  => "",
  );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader>.

=head1 METHODS

=head2 new

Overrides L<DBIx::Class::Schema::Loader::Generic>'s C<new()> to default the postgres
schema to C<public> rather than blank.

=cut

sub new {
    my ($class, %args) = @_;

    my $self = $class->next::method(%args);
    $self->{db_schema} ||= 'public';

    $self;
}

sub _db_classes {
    return qw/PK::Auto::Pg/;
}

sub _tables {
    my $self = shift;
    my $dbh = $self->schema->storage->dbh;
    my $quoter = $dbh->get_info(29) || q{"};

    # This is split out to avoid version parsing errors...
    my $is_dbd_pg_gte_131 = ( $DBD::Pg::VERSION >= 1.31 );
    my @tables = $is_dbd_pg_gte_131
        ?  $dbh->tables( undef, $self->db_schema, "",
                         "table", { noprefix => 1, pg_noprefix => 1 } )
        : $dbh->tables;

    s/$quoter//g for @tables;
    return @tables;
}

sub _table_info {
    my ( $self, $table ) = @_;
    my $dbh = $self->schema->storage->dbh;
    my $quoter = $dbh->get_info(29) || q{"};

    my $sth = $dbh->column_info(undef, $self->db_schema, $table, undef);
    my @cols = map { $_->[3] } @{ $sth->fetchall_arrayref };
    s/$quoter//g for @cols;
    
    my @primary = $dbh->primary_key(undef, $self->db_schema, $table);

    s/$quoter//g for @primary;

    return ( \@cols, \@primary );
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
