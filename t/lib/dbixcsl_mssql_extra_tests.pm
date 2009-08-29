package dbixcsl_mssql_extra_tests;

use Test::More;

my $vendor = 'mssql';

sub vendor {
    shift;
    $vendor = shift;
}

sub extra { +{
    create => [
        qq{
            CREATE TABLE [${vendor}_loader_test1.dot] (
                id INT IDENTITY NOT NULL PRIMARY KEY,
                dat VARCHAR(8)
            )
        },
    ],
    drop   => [ "[${vendor}_loader_test1.dot]" ],
    count  => 4,
    run    => sub {
        my ($schema, $monikers, $classes) = @_;

        my $vendor_titlecased = "\u\L$vendor";

        ok((my $rs = eval {
            $schema->resultset("${vendor_titlecased}LoaderTest1Dot") }),
            'got a resultset');

        ok((my $from = eval { $rs->result_source->from }),
            'got an $rsrc->from');

        is ref($from), 'SCALAR', '->table is a scalar ref';

        is eval { $$from }, "[${vendor}_loader_test1.dot]",
            '->table name is correct';
    },
}}

1;
