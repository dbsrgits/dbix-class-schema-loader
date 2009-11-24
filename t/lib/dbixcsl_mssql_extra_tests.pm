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
        qq{
            CREATE TABLE ${vendor}_loader_test2 (
                id INT IDENTITY NOT NULL PRIMARY KEY,
                dat VARCHAR(100) DEFAULT 'foo',
                num NUMERIC DEFAULT 10.89,
                anint INT DEFAULT 6,
                ts DATETIME DEFAULT getdate()
            )
        },
    ],
    drop   => [ "[${vendor}_loader_test1.dot]", "${vendor}_loader_test2"  ],
    count  => 13,
    run    => sub {
        my ($schema, $monikers, $classes) = @_;

# Test that the table above (with '.' in name) gets loaded correctly.
        my $vendor_titlecased = "\u\L$vendor";

        ok((my $rs = eval {
            $schema->resultset("${vendor_titlecased}LoaderTest1Dot") }),
            'got a resultset for table with dot in name');

        ok((my $from = eval { $rs->result_source->from }),
            'got an $rsrc->from for table with dot in name');

        is ref($from), 'SCALAR', '->table with dot in name is a scalar ref';

        is eval { $$from }, "[${vendor}_loader_test1.dot]",
            '->table with dot in name has correct name';

# Test that column defaults are set correctly
        ok(($rs = eval {
            $schema->resultset("${vendor_titlecased}LoaderTest2") }),
            'got a resultset for table with column with default value');

        my $rsrc = $rs->result_source;

        is eval { $rsrc->column_info('dat')->{default_value} }, 'foo',
            'correct default_value for column with literal string default';

        is eval { $rsrc->column_info('anint')->{default_value} }, 6,
            'correct default_value for column with literal integer default';

        cmp_ok eval { $rsrc->column_info('num')->{default_value} },
            '==', 10.89,
            'correct default_value for column with literal numeric default';

        ok((my $function_default =
            eval { $rsrc->column_info('ts')->{default_value} }),
            'got default_value for column with function default');

        is ref($function_default), 'SCALAR',
            'default_value for function default is a SCALAR ref';

        is eval { $$function_default }, 'getdate()',
            'default_value for function default is correct';

# Test that identity columns do not have 'identity' in the data_type, and do
# have is_auto_increment.
        my $identity_col_info = $schema->resultset('LoaderTest10')
            ->result_source->column_info('id10');

        is $identity_col_info->{data_type}, 'int',
            q{'INT IDENTITY' column has data_type => 'int'};

        is $identity_col_info->{is_auto_increment}, 1,
            q{'INT IDENTITY' column has is_auto_increment => 1};
    },
}}

1;
