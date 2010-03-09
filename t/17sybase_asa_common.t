use strict;
use warnings;
use lib qw(t/lib);
use dbixcsl_common_tests;

# The default max_cursor_count and max_statement_count settings of 50 are too
# low to run this test.

my $dbd_sqlanywhere_dsn      = $ENV{DBICTEST_SYBASE_ASA_DSN} || '';
my $dbd_sqlanywhere_user     = $ENV{DBICTEST_SYBASE_ASA_USER} || '';
my $dbd_sqlanywhere_password = $ENV{DBICTEST_SYBASE_ASA_PASS} || '';

my $odbc_dsn      = $ENV{DBICTEST_SYBASE_ASA_ODBC_DSN} || '';
my $odbc_user     = $ENV{DBICTEST_SYBASE_ASA_ODBC_USER} || '';
my $odbc_password = $ENV{DBICTEST_SYBASE_ASA_ODBC_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor      => 'SQLAnywhere',
    auto_inc_pk => 'INTEGER IDENTITY NOT NULL PRIMARY KEY',
    default_function => 'current timestamp',
    connect_info => [ ($dbd_sqlanywhere_dsn ? {
            dsn         => $dbd_sqlanywhere_dsn,
            user        => $dbd_sqlanywhere_user,
            password    => $dbd_sqlanywhere_password,
        } : ()),
        ($odbc_dsn ? {
            dsn         => $odbc_dsn,
            user        => $odbc_user,
            password    => $odbc_password,
        } : ()),
    ],
);

if (not ($dbd_sqlanywhere_dsn || $odbc_dsn)) {
    $tester->skip_tests('You need to set the DBICTEST_SYBASE_ASA_DSN, _USER and _PASS and/or the DBICTEST_SYBASE_ASA_ODBC_DSN, _USER and _PASS environment variables');
}
else {
    $tester->run_tests();
}
