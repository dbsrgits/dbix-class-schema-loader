use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;
use Test::More;
use Test::Exception;

my $dsn      = $ENV{DBICTEST_SYBASE_DSN} || '';
my $user     = $ENV{DBICTEST_SYBASE_USER} || '';
my $password = $ENV{DBICTEST_SYBASE_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor      => 'sybase',
    auto_inc_pk => 'INTEGER IDENTITY NOT NULL PRIMARY KEY',
    dsn         => $dsn,
    user        => $user,
    password    => $password,
    extra       => {
        create  => [
            q{
                CREATE TABLE sybase_loader_test1 (
                    id INTEGER IDENTITY NOT NULL PRIMARY KEY,
                    ts timestamp,
                    charfield VARCHAR(10) DEFAULT 'foo',
                    computed_dt AS getdate()
                )
            },
        ],
        drop  => [ qw/ sybase_loader_test1 / ],
        count => 9,
        run   => sub {
            my ($schema, $monikers, $classes) = @_;

            my $rs = $schema->resultset($monikers->{sybase_loader_test1});
            my $rsrc = $rs->result_source;

            is $rsrc->column_info('id')->{data_type},
                'numeric',
                'INTEGER IDENTITY data_type is correct';

            is $rsrc->column_info('id')->{is_auto_increment},
                1,
                'INTEGER IDENTITY is_auto_increment => 1';

            {
                local $TODO = 'timestamp introspection broken';

                is $rsrc->column_info('ts')->{data_type},
                   'timestamp',
                   'timestamps have the correct data_type';
            }

            is $rsrc->column_info('charfield')->{data_type},
                'varchar',
                'VARCHAR has correct data_type';

            {
                local $TODO = 'constant DEFAULT introspection';

                is $rsrc->column_info('charfield')->{default_value},
                    'foo',
                    'constant DEFAULT is correct';
            }

            is $rsrc->column_info('charfield')->{size},
                10,
                'VARCHAR(10) has correct size';

            ok ((exists $rsrc->column_info('computed_dt')->{data_type}
              && (not defined $rsrc->column_info('computed_dt')->{data_type})),
                'data_type for computed column exists and is undef')
            or diag "Data type is: ",
                $rsrc->column_info('computed_dt')->{data_type}
            ;

            {
                local $TODO = 'default_value for computed columns';

                my $computed_dt_default =
                    $rsrc->column_info('computed_dt')->{default_value};

                ok ((ref $computed_dt_default eq 'SCALAR'),
                    'default_value for computed column is a scalar ref')
#                or diag "default_value is: ", $computed_dt_default
                ;

                eval { is $$computed_dt_default,
                    'getdate()',
                    'default_value for computed column is correct' };
            }
        },
    },
);

if( !$dsn || !$user ) {
    $tester->skip_tests('You need to set the DBICTEST_SYBASE_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
