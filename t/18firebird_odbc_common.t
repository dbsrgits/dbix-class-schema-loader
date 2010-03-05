use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;
use dbixcsl_firebird_extra_tests;

my $dsn      = $ENV{DBICTEST_FIREBIRD_ODBC_DSN} || '';
my $user     = $ENV{DBICTEST_FIREBIRD_ODBC_USER} || '';
my $password = $ENV{DBICTEST_FIREBIRD_ODBC_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor      => 'Firebird',
    auto_inc_pk => 'INTEGER NOT NULL PRIMARY KEY',
    auto_inc_cb => sub {
        my ($table, $col) = @_;
        return (
            qq{ CREATE GENERATOR gen_${table}_${col} },
            qq{
                CREATE TRIGGER ${table}_bi FOR $table
                ACTIVE BEFORE INSERT POSITION 0
                AS
                BEGIN
                 IF (NEW.$col IS NULL) THEN
                  NEW.$col = GEN_ID(gen_${table}_${col},1);
                END
            }
        );
    },
    auto_inc_drop_cb => sub {
        my ($table, $col) = @_;
        return (
            qq{ DROP TRIGGER ${table}_bi },
            qq{ DROP GENERATOR gen_${table}_${col} },
        );
    },
    null        => '',
    extra       => dbixcsl_firebird_extra_tests->extra,
    uppercase_identifiers => 1,
    dsn         => $dsn,
    user        => $user,
    password    => $password,
);

if( !$dsn ) {
    $tester->skip_tests('You need to set the DBICTEST_FIREBIRD_ODBC_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
