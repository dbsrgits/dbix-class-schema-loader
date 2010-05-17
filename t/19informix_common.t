use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;

# to support " quoted identifiers
BEGIN { $ENV{DELIMIDENT} = 'y' }

# This test doesn't run over a shared memory connection, because of the single connection limit.

my $dsn      = $ENV{DBICTEST_INFORMIX_DSN} || '';
my $user     = $ENV{DBICTEST_INFORMIX_USER} || '';
my $password = $ENV{DBICTEST_INFORMIX_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor         => 'Informix',
    auto_inc_pk    => 'SERIAL PRIMARY KEY',
    null           => '',
    default_function     => 'CURRENT YEAR TO FRACTION(5)',
    default_function_def => 'DATETIME YEAR TO FRACTION(5) DEFAULT CURRENT YEAR TO FRACTION(5)',
    dsn            => $dsn,
    user           => $user,
    password       => $password,
    loader_options => { preserve_case => 1 },
    quote_char     => '"',
);

if( !$dsn ) {
    $tester->skip_tests('You need to set the DBICTEST_INFORMIX_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
# vim:et sts=4 sw=4 tw=0:
