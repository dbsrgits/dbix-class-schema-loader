package DBIx::Class::Schema::Loader::DBI::ODBC::Microsoft_SQL_Server;

use base 'DBIx::Class::Schema::Loader::DBI::MSSQL';

sub _tables_list { 
    my $self = shift;

    my $dbh = $self->schema->storage->dbh;
    my @tables = $dbh->tables(undef, $self->db_schema);
    s/\Q$self->{_quoter}\E//g for @tables;
    s/^.*\Q$self->{_namesep}\E// for @tables;

    return @tables;
}

1;
