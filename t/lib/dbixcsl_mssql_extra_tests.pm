package dbixcsl_mssql_extra_tests;

use strict;
use warnings;
use Test::More;
use Test::Exception;

sub extra { +{
    create => [
        q{
            CREATE TABLE [mssql_loader_test1.dot] (
                id INT IDENTITY NOT NULL PRIMARY KEY,
                dat VARCHAR(8)
            )
        },
        q{
            CREATE TABLE mssql_loader_test3 (
                id INT IDENTITY NOT NULL PRIMARY KEY
            )
        },
        q{
            CREATE VIEW mssql_loader_test4 AS
            SELECT * FROM mssql_loader_test3
        },
    ],
    pre_drop_ddl => [
        'CREATE TABLE mssql_loader_test3 (id INT IDENTITY NOT NULL PRIMARY KEY)',
        'DROP VIEW mssql_loader_test4',
    ],
    drop   => [
        '[mssql_loader_test1.dot]',
        'mssql_loader_test3'
    ],
    count  => 8,
    run    => sub {
        my ($schema, $monikers, $classes) = @_;

# Test that the table above (with '.' in name) gets loaded correctly.
        ok((my $rs = eval {
            $schema->resultset($monikers->{'[mssql_loader_test1.dot]'}) }),
            'got a resultset for table with dot in name');

        ok((my $from = eval { $rs->result_source->from }),
            'got an $rsrc->from for table with dot in name');

        is ref($from), 'SCALAR', '->table with dot in name is a scalar ref';

        is eval { $$from }, "[mssql_loader_test1.dot]",
            '->table with dot in name has correct name';

# Test that identity columns do not have 'identity' in the data_type, and do
# have is_auto_increment.
        my $identity_col_info = $schema->resultset($monikers->{loader_test10})
            ->result_source->column_info('id10');

        is $identity_col_info->{data_type}, 'int',
            q{'INT IDENTITY' column has data_type => 'int'};

        is $identity_col_info->{is_auto_increment}, 1,
            q{'INT IDENTITY' column has is_auto_increment => 1};

# Test that a bad view (where underlying table is gone) is ignored.
        my $dbh = $schema->storage->dbh;
        $dbh->do("DROP TABLE mssql_loader_test3");

        my @warnings;
        {
            local $SIG{__WARN__} = sub { push @warnings, $_[0] };
            $schema->rescan;
        }
        ok ((grep /^Bad table or view 'mssql_loader_test4'/, @warnings),
            'bad view ignored');

        throws_ok {
            $schema->resultset($monikers->{mssql_loader_test4})
        } qr/Can't find source/,
            'no source registered for bad view';
    },
}}

1;
