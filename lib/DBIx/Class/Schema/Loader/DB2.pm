package DBIx::Class::Schema::Loader::DB2;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::Generic';
use Class::C3;

=head1 NAME

DBIx::Class::Schema::Loader::DB2 - DBIx::Class::Schema::Loader DB2 Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->load_from_connection(
    dsn         => "dbi:DB2:dbname",
    user        => "myuser",
    password    => "",
    db_schema   => "MYSCHEMA",
    drop_schema => 1,
  );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader>.

=cut

sub _db_classes {
    return qw/PK::Auto::DB2/;
}

sub _tables {
    my $self = shift;
    my %args = @_; 
    my $db_schema = uc $self->db_schema;
    my $dbh = $self->schema->storage->dbh;
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

sub _table_info {
    my ( $self, $table ) = @_;
#    $|=1;
#    print "_table_info($table)\n";
    my ($db_schema, $tabname) = split /\./, $table, 2;
    # print "DB_Schema: $db_schema, Table: $tabname\n";
    
    # FIXME: Horribly inefficient and just plain evil. (JMM)
    my $dbh = $self->schema->storage->dbh;
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
sub _load_relationships {
    my $self = shift;

    my $dbh = $self->schema->storage->dbh;

    my $sth = $dbh->prepare(<<'SQL') or die;
SELECT SR.COLCOUNT, SR.REFTBNAME, SR.PKCOLNAMES, SR.FKCOLNAMES
FROM SYSIBM.SYSRELS SR WHERE SR.TBNAME = ?
SQL

    foreach my $table ( $self->tables ) {
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

            eval { $self->_make_cond_rel ($table, $other, \%cond); };
            warn qq/\# belongs_to_many failed "$@"\n\n/
              if $@ && $self->debug;
        }
    }

    $sth->finish;
    $dbh->disconnect;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
