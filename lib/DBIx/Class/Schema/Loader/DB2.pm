package DBIx::Class::Schema::Loader::DB2;

use strict;
use base 'DBIx::Class::Schema::Loader::Generic';
use Carp;

=head1 NAME

DBIx::Class::Schema::Loader::DB2 - DBIx::Class::Schema::Loader DB2 Implementation.

=head1 SYNOPSIS

  use DBIx::Schema::Class::Loader;

  # $loader is a DBIx::Class::Schema::Loader::DB2
  my $loader = DBIx::Class::Schema::Loader->new(
    dsn         => "dbi:DB2:dbname",
    user        => "myuser",
    password    => "",
    db_schema   => "MYSCHEMA",
    drop_schema => 1,
  );

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader>.

=cut

sub _loader_db_classes {
    return qw/DBIx::Class::PK::Auto::DB2/;
}

sub _loader_tables {
    my $class = shift;
    my %args = @_; 
    my $db_schema = uc $class->_loader_db_schema;
    my $dbh = $class->storage->dbh;
    my $quoter = $dbh->get_info(29) || q{"};

    # this is split out to avoid version parsing errors...
    my $is_dbd_db2_gte_114 = ( $DBD::DB2::VERSION >= 1.14 );
    my @tables = $is_dbd_db2_gte_114 ? 
    $dbh->tables( { TABLE_SCHEM => '%', TABLE_TYPE => 'TABLE,VIEW' } )
        : $dbh->tables;
    # People who use table or schema names that aren't identifiers deserve
    # what they get.  Still, FIXME?
    s/$quoter//g for @tables;
    @tables = grep {!/^SYSIBM\./ and !/^SYSCAT\./ and !/^SYSSTAT\./} @tables;
    @tables = grep {/^$db_schema\./} @tables if($db_schema);
    return @tables;
}

sub _loader_table_info {
    my ( $class, $table ) = @_;
#    $|=1;
#    print "_loader_table_info($table)\n";
    my ($db_schema, $tabname) = split /\./, $table, 2;
    # print "DB_Schema: $db_schema, Table: $tabname\n";
    
    # FIXME: Horribly inefficient and just plain evil. (JMM)
    my $dbh = $class->storage->dbh;
    $dbh->{RaiseError} = 1;

    my $sth = $dbh->prepare(<<'SQL') or die;
SELECT c.COLNAME
FROM SYSCAT.COLUMNS as c
WHERE c.TABSCHEMA = ? and c.TABNAME = ?
SQL

    $sth->execute($db_schema, $tabname) or die;
    my @cols = map { lc } map { @$_ } @{$sth->fetchall_arrayref};

    undef $sth;

    $sth = $dbh->prepare(<<'SQL') or die;
SELECT kcu.COLNAME
FROM SYSCAT.TABCONST as tc
JOIN SYSCAT.KEYCOLUSE as kcu ON tc.constname = kcu.constname
WHERE tc.TABSCHEMA = ? and tc.TABNAME = ? and tc.TYPE = 'P'
SQL

    $sth->execute($db_schema, $tabname) or die;

    my @pri = map { lc } map { @$_ } @{$sth->fetchall_arrayref};

    return ( \@cols, \@pri );
}

# Find and setup relationships
sub _loader_relationships {
    my $class = shift;

    my $dbh = $class->storage->dbh;

    my $sth = $dbh->prepare(<<'SQL') or die;
SELECT SR.COLCOUNT, SR.REFTBNAME, SR.PKCOLNAMES, SR.FKCOLNAMES
FROM SYSIBM.SYSRELS SR WHERE SR.TBNAME = ?
SQL

    foreach my $table ( $class->tables ) {
        next if ! $sth->execute(uc $table);
        while(my $res = $sth->fetchrow_arrayref()) {
            my ($colcount, $other, $other_column, $column) =
                map { lc } @$res;

            my @self_cols = split(' ',$column);
            my @other_cols = split(' ',$other_column);
            if(@self_cols != $colcount || @other_cols != $colcount) {
                die "Column count discrepancy while getting rel info";
            }

            my %cond;
            for(my $i = 0; $i < @self_cols; $i++) {
                $cond{$other_cols[$i]} = $self_cols[$i];
            }

            eval { $class->_loader_make_relations ($table, $other, \%cond); };
            warn qq/\# belongs_to_many failed "$@"\n\n/
              if $@ && $class->_loader_debug;
        }
    }

    $sth->finish;
    $dbh->disconnect;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
