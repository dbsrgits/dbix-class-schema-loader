package DBIx::Class::Loader::Pg;

use strict;
use base 'DBIx::Class::Loader::Generic';
use DBI;
use Carp;

our $SCHEMA = 'public';

=head1 NAME

DBIx::Class::Loader::Pg - DBIx::Class::Loader Postgres Implementation.

=head1 SYNOPSIS

  use DBIx::Class::Loader;

  # $loader is a DBIx::Class::Loader::Pg
  my $loader = DBIx::Class::Loader->new(
    dsn       => "dbi:Pg:dbname=dbname",
    user      => "postgres",
    password  => "",
    namespace => "Data",
  );
  my $class = $loader->find_class('film'); # $class => Data::Film
  my $obj = $class->retrieve(1);

=head1 DESCRIPTION

See L<DBIx::Class::Loader>.

=cut

sub _db_classes {
    return qw/DBIx::Class::PK::Auto::Pg/;
}

sub _tables {
    my $self = shift;
    my $dbh = DBI->connect( @{ $self->{_datasource} } ) or croak($DBI::errstr);

    # This is split out to avoid version parsing errors...
    my $is_dbd_pg_gte_131 = ( $DBD::Pg::VERSION >= 1.31 );
    my @tables = $is_dbd_pg_gte_131 ? 
        $dbh->tables( undef, $SCHEMA, "", "table", { noprefix => 1, pg_noprefix => 1 } )
        : $dbh->tables;

    $dbh->disconnect;
    s/"//g for @tables;
    return @tables;
}

sub _table_info {
    my ( $self, $table ) = @_;
    my $dbh = DBI->connect( @{ $self->{_datasource} } ) or croak($DBI::errstr);

    my $sth = $dbh->column_info(undef, $SCHEMA, $table, undef);
    my @cols = map { $_->[3] } @{ $sth->fetchall_arrayref };
    s/"//g for @cols;
    
    my @primary = $dbh->primary_key(undef, $SCHEMA, $table);

    $dbh->disconnect;

    s/"//g for @primary;

    return ( \@cols, \@primary );
}

=head1 SEE ALSO

L<DBIx::Class::Loader>

=cut

1;
