use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;

# You need the sybase branch of DBIx::Class, from:
# http://dev.catalyst.perl.org/repos/bast/DBIx-Class/0.08/branches/sybase

my $dsn      = $ENV{DBICTEST_SYBASE_DSN} || '';
my $user     = $ENV{DBICTEST_SYBASE_USER} || '';
my $password = $ENV{DBICTEST_SYBASE_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor      => 'sybase',
    auto_inc_pk => 'INTEGER IDENTITY NOT NULL PRIMARY KEY',
    dsn         => $dsn,
    user        => $user,
    password    => $password,
# This is necessary because there are too many cursors open for transactions on
# insert to work.
    connect_info_opts => { on_connect_call => 'unsafe_insert' }
);

if( !$dsn || !$user ) {
    $tester->skip_tests('You need to set the DBICTEST_SYBASE_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
