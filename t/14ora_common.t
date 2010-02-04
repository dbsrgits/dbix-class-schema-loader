use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;
use Test::More;
use Test::Exception;

my $dsn      = $ENV{DBICTEST_ORA_DSN} || '';
my $user     = $ENV{DBICTEST_ORA_USER} || '';
my $password = $ENV{DBICTEST_ORA_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor      => 'Oracle',
    auto_inc_pk => 'INTEGER NOT NULL PRIMARY KEY',
    auto_inc_cb => sub {
        my ($table, $col) = @_;
        return (
            qq{ CREATE SEQUENCE ${table}_${col}_seq START WITH 1 INCREMENT BY 1},
            qq{ 
                CREATE OR REPLACE TRIGGER ${table}_${col}_trigger
                BEFORE INSERT ON ${table}
                FOR EACH ROW
                BEGIN
                    SELECT ${table}_${col}_seq.nextval INTO :NEW.${col} FROM dual;
                END;
            }
        );
    },
    auto_inc_drop_cb => sub {
        my ($table, $col) = @_;
        return qq{ DROP SEQUENCE ${table}_${col}_seq };
    },
    dsn         => $dsn,
    user        => $user,
    password    => $password,
    extra       => {
        create => [
            q{
                CREATE TABLE oracle_loader_test1 (
                    id INTEGER PRIMARY KEY,
                    a_varchar VARCHAR2(100) DEFAULT 'foo',
                    an_int INTEGER DEFAULT 42,
                    a_double DOUBLE PRECISION DEFAULT 10.555,
                    a_date DATE DEFAULT sysdate
                )
            },
        ],
        drop   => [ qw/ oracle_loader_test1 / ],
        count  => 5,
        run    => sub {
            my ($schema, $monikers, $classes) = @_;

            my $rsrc = $schema->resultset($monikers->{oracle_loader_test1})
                ->result_source;

            is $rsrc->column_info('a_varchar')->{default_value},
                'foo',
                'constant character default';

            is $rsrc->column_info('an_int')->{default_value},
                42,
                'constant integer default';

            is $rsrc->column_info('a_double')->{default_value},
                10.555,
                'constant numeric default';

            my $function_default =
                $rsrc->column_info('a_date')->{default_value};

            ok ((ref $function_default eq 'SCALAR'),
                'default_value for function default is a scalar ref')
            or diag "default_value is: ", $function_default
            ;

            eval { is $$function_default,
                'sysdate',
                'default_value for function default is correct' };
        },
    },
);

if( !$dsn || !$user ) {
    $tester->skip_tests('You need to set the DBICTEST_ORA_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
