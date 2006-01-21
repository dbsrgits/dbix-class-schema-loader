package DBIx::Class::Loader::DB2;

use strict;
use base 'DBIx::Class::Loader::Generic';
use DBI;
use Carp;

=head1 NAME

DBIx::Class::Loader::DB2 - DBIx::Class::Loader DB2 Implementation.

=head1 SYNOPSIS

  use DBIx::Class::Loader;

  # $loader is a DBIx::Class::Loader::DB2
  my $loader = DBIx::Class::Loader->new(
    dsn       => "dbi:DB2:dbname",
    user      => "myuser",
    password  => "",
    namespace => "Data",
    schema    => "MYSCHEMA",
    dropschema  => 0,
  );
  my $class = $loader->find_class('film'); # $class => Data::Film
  my $obj = $class->retrieve(1);

=head1 DESCRIPTION

See L<DBIx::Class::Loader>.

=cut

sub _db_classes {
   return ();
}

sub _tables {
    my $self = shift;
    my %args = @_; 
    my $schema = uc ($args{schema} || '');
    my $dbh = DBI->connect( @{ $self->{_datasource} } ) or croak($DBI::errstr);

    # this is split out to avoid version parsing errors...
    my $is_dbd_db2_gte_114 = ( $DBD::DB2::VERSION >= 1.14 );
    my @tables = $is_dbd_db2_gte_114 ? 
    $dbh->tables( { TABLE_SCHEM => '%', TABLE_TYPE => 'TABLE,VIEW' } )
        : $dbh->tables;
    $dbh->disconnect;
    # People who use table or schema names that aren't identifiers deserve
    # what they get.  Still, FIXME?
    s/\"//g for @tables;
    @tables = grep {!/^SYSIBM\./ and !/^SYSCAT\./ and !/^SYSSTAT\./} @tables;
    @tables = grep {/^$schema\./} @tables if($schema);
    return @tables;
}

sub _table_info {
    my ( $self, $table ) = @_;
#    $|=1;
#    print "_table_info($table)\n";
    my ($schema, $tabname) = split /\./, $table, 2;
    # print "Schema: $schema, Table: $tabname\n";
    
    # FIXME: Horribly inefficient and just plain evil. (JMM)
    my $dbh = DBI->connect( @{ $self->{_datasource} } ) or croak($DBI::errstr);
    $dbh->{RaiseError} = 1;

    my $sth = $dbh->prepare(<<'SQL') or die;
SELECT c.COLNAME
FROM SYSCAT.COLUMNS as c
WHERE c.TABSCHEMA = ? and c.TABNAME = ?
SQL

    $sth->execute($schema, $tabname) or die;
    my @cols = map { @$_ } @{$sth->fetchall_arrayref};

    $sth = $dbh->prepare(<<'SQL') or die;
SELECT kcu.COLNAME
FROM SYSCAT.TABCONST as tc
JOIN SYSCAT.KEYCOLUSE as kcu ON tc.constname = kcu.constname
WHERE tc.TABSCHEMA = ? and tc.TABNAME = ? and tc.TYPE = 'P'
SQL

    $sth->execute($schema, $tabname) or die;
    $dbh->disconnect;

    my @pri = map { @$_ } @{$sth->fetchall_arrayref};
    
    return ( \@cols, \@pri );
}

=head1 SEE ALSO

L<DBIx::Class::Loader>

=cut

1;
