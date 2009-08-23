package dbixcsl_mssql_extra_tests;

use Test::More;

sub extra { +{
    create => [
        qq{
            CREATE TABLE [mssql_loader_test1.dot] (
                id INT IDENTITY NOT NULL PRIMARY KEY,
                dat VARCHAR(8)
            )
        },
    ],
    drop   => [ qw/ [mssql_loader_test1.dot] / ],
    count  => 4,
    run    => sub {
        my ($schema, $monikers, $classes) = @_;

        ok((my $rs = eval { $schema->resultset('MssqlLoaderTest1Dot') }),
            'got a resultset');

        ok((my $from = eval { $rs->result_source->from }),
            'got an $rsrc->from');

        is ref($from), 'SCALAR', '->table is a scalar ref';

        is eval { $$from }, '[mssql_loader_test1.dot]',
            '->table name is correct';
    },
}}

1;
