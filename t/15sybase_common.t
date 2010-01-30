use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;
use Test::More;

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
                    ts timestamp
                )
            },
        ],
        drop  => [ qw/ sybase_loader_test1 / ],
        count => 1,
        run   => sub {
            my ($schema, $monikers, $classes) = @_;

            my $rs = $schema->resultset($monikers->{sybase_loader_test1});

            {
                local $TODO = 'timestamp introspection broken';

                is $rs->result_source->column_info('ts')->{data_type},
                   'timestamp',
                   'timestamps have the correct data_type';
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
