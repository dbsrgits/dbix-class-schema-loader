use strict;
use lib qw( . ./t );
use dbixcl_common_tests;

my $database = $ENV{DB2_NAME} || '';
my $user     = $ENV{DB2_USER} || '';
my $password = $ENV{DB2_PASS} || '';

my $tester = dbixcl_common_tests->new(
    vendor      => 'DB2',
    auto_inc_pk => 'SERIAL NOT NULL PRIMARY KEY',
    dsn         => "dbi:DB2:$database",
    user        => $user,
    password    => $password,
);

if( !$database || !$user ) {
    $tester->skip_tests('You need to set the DB2_NAME, DB2_USER and DB2_PASS environment variables');
}
else {
    $tester->run_tests();
}
