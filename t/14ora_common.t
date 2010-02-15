use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;
use Test::More;
use Test::Exception;

my $dsn      = $ENV{DBICTEST_ORA_DSN} || '';
my $user     = $ENV{DBICTEST_ORA_USER} || '';
my $password = $ENV{DBICTEST_ORA_PASS} || '';

sub _custom_column_info {
    my $info = shift;

    if ( $info->{TYPE_NAME} eq 'DATE' ){
        return { timezone => "Europe/Berlin" };
    }
    return;
}

my $tester = dbixcsl_common_tests->new(
    vendor      => 'Oracle',
    custom_column_info => \&_custom_column_info,
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
    extra => {
        create => [qq{
            CREATE TABLE oracle_loader_test1 (
                id number(5) NOT NULL,
                name varchar2(100) NOT NULL,
                create_date date NOT NULL,
                modification_date date,
                PRIMARY KEY (id)
            )
        },],
        drop  => [qw/ oracle_loader_test1 /],
        count => 2,
        run   => sub {
            my ( $schema, $monikers, $classes ) = @_;
            my $rs = $schema->resultset( $monikers->{oracle_loader_test1} );

            is $rs->result_source->column_info('create_date')->{timezone},
                'Europe/Berlin',
                'create_date hast timezone';

            is $rs->result_source->column_info('modification_date')->{timezone},
                'Europe/Berlin',
                'modification_date hast timezone';

        },
      }

);

if( !$dsn || !$user ) {
    $tester->skip_tests('You need to set the DBICTEST_ORA_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
