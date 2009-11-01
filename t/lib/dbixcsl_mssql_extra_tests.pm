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
    count  => 6,
    run    => sub {
        my ($schema, $monikers, $classes) = @_;

# Test that the table above (with '.' in name) gets loaded correctly.
        my $vendor_titlecased = "\u\L$vendor";

        ok((my $rs = eval {
            $schema->resultset("${vendor_titlecased}LoaderTest1Dot") }),
            'got a resultset');

        ok((my $from = eval { $rs->result_source->from }),
            'got an $rsrc->from');

        is ref($from), 'SCALAR', '->table is a scalar ref';

        is eval { $$from }, "[${vendor}_loader_test1.dot]",
            '->table name is correct';

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
