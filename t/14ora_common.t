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
    preserve_case_mode_is_exclusive => 1,
    quote_char                      => '"',
    dsn         => $dsn,
    user        => $user,
    password    => $password,
    data_types  => {
        # From:
        # http://download.oracle.com/docs/cd/B19306_01/server.102/b14200/sql_elements001.htm#i54330
        #
        # These tests require at least Oracle 9.2, because of the VARCHAR to
        # VARCHAR2 casting.
        #
        # Character Types
        'char'         => { data_type => 'char',      size => 1  },
        'char(11)'     => { data_type => 'char',      size => 11 },
        'nchar'        => { data_type => 'nchar',     size => 1  },
        'nchar(11)'    => { data_type => 'nchar',     size => 11 },
        'varchar(20)'  => { data_type => 'varchar2',  size => 20 },
        'varchar2(20)' => { data_type => 'varchar2',  size => 20 },
        'nvarchar2(20)'=> { data_type => 'nvarchar2', size => 20 },

        # Numeric Types
        #
        # integer/decimal/numeric is alised to NUMBER
        #
        'integer'      => { data_type => 'integer', original => { data_type => 'number', size => [38,0] } },
        'int'          => { data_type => 'integer', original => { data_type => 'number', size => [38,0] } },
        'smallint'     => { data_type => 'integer', original => { data_type => 'number', size => [38,0] } },

        'decimal'      => { data_type => 'integer', original => { data_type => 'number', size => [38,0] } },
        'dec'          => { data_type => 'integer', original => { data_type => 'number', size => [38,0] } },
        'numeric'      => { data_type => 'integer', original => { data_type => 'number', size => [38,0] } },

        'decimal(3)'   => { data_type => 'numeric', size => [3,0], original => { data_type => 'number' } },
        'dec(3)'       => { data_type => 'numeric', size => [3,0], original => { data_type => 'number' } },
        'numeric(3)'   => { data_type => 'numeric', size => [3,0], original => { data_type => 'number' } },

        'decimal(3,3)' => { data_type => 'numeric', size => [3,3], original => { data_type => 'number' } },
        'dec(3,3)'     => { data_type => 'numeric', size => [3,3], original => { data_type => 'number' } },
        'numeric(3,3)' => { data_type => 'numeric', size => [3,3], original => { data_type => 'number' } },

        'binary_float'  => { data_type => 'real',             original => { data_type => 'binary_float'  } },
        'binary_double' => { data_type => 'double precision', original => { data_type => 'binary_double' } },

        # these are not mentioned in the summary chart, must be aliased
	real            => { data_type => 'real',             original => { data_type => 'float', size => 63  } },
        'float(63)'     => { data_type => 'real',             original => { data_type => 'float', size => 63  } },
        'float(64)'     => { data_type => 'double precision', original => { data_type => 'float', size => 64  } },
        'float(126)'    => { data_type => 'double precision', original => { data_type => 'float', size => 126 } },
        float           => { data_type => 'double precision', original => { data_type => 'float', size => 126 } },

        # Blob Types
        'raw(50)'      => { data_type => 'raw', size => 50 },
        'clob'         => { data_type => 'clob' },
        'nclob'        => { data_type => 'nclob' },
        'blob'         => { data_type => 'blob' },
        'bfile'        => { data_type => 'bfile' },
        'long'         => { data_type => 'long' },
        'long raw'     => { data_type => 'long raw' },

        # Datetime Types
        'date'         => { data_type => 'datetime', original => { data_type => 'date' } },
        'date default sysdate'
                       => { data_type => 'datetime', default_value => \'current_timestamp',
                            original  => { data_type => 'date', default_value => \'sysdate' } },
        'timestamp'    => { data_type => 'timestamp' },
        'timestamp default current_timestamp'
                       => { data_type => 'timestamp', default_value => \'current_timestamp' },
        'timestamp(3)' => { data_type => 'timestamp', size => 3 },
        'timestamp with time zone'
                       => { data_type => 'timestamp with time zone' },
        'timestamp(3) with time zone'
                       => { data_type => 'timestamp with time zone', size => 3 },
        'timestamp with local time zone'
                       => { data_type => 'timestamp with local time zone' },
        'timestamp(3) with local time zone'
                       => { data_type => 'timestamp with local time zone', size => 3 },
        'interval year to month'
                       => { data_type => 'interval year to month' },
        'interval year(3) to month'
                       => { data_type => 'interval year to month', size => 3 },
        'interval day to second'
                       => { data_type => 'interval day to second' },
        'interval day(3) to second'
                       => { data_type => 'interval day to second', size => [3,6] },
        'interval day to second(3)'
                       => { data_type => 'interval day to second', size => [2,3] },
        'interval day(3) to second(3)'
                       => { data_type => 'interval day to second', size => [3,3] },

        # Other Types
        'rowid'        => { data_type => 'rowid' },
        'urowid'       => { data_type => 'urowid' },
        'urowid(3333)' => { data_type => 'urowid', size => 3333 },
    },
    extra => {
        count => 1,
        run   => sub {
            my ($schema, $monikers, $classes) = @_;

            SKIP: {
                if (my $source = $monikers->{loader_test1s}) {
                    is $schema->source($source)->column_info('id')->{sequence},
                        'loader_test1s_id_seq',
                        'Oracle sequence detection';
                }
                else {
                    skip 1, 'not running common tests';
                }
            }
        },
    },
);

if( !$dsn || !$user ) {
    $tester->skip_tests('You need to set the DBICTEST_ORA_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
# vim:et sw=4 sts=4 tw=0:
