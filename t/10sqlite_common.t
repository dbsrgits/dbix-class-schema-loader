use strict;
use Test::More;
use lib qw(t/lib);
use dbixcsl_common_tests;

eval { require DBD::SQLite };
my $class = $@ ? 'SQLite2' : 'SQLite';

my $tester = dbixcsl_common_tests->new(
    vendor          => 'SQLite',
    auto_inc_pk     => 'INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT',
    dsn             => "dbi:$class:dbname=./t/sqlite_test",
    user            => '',
    password        => '',
    extra           => {
        create => [
            # 'sqlite_' is reserved, so we use 'extra_'
            q{
                CREATE TABLE "extra_loader_test1" (
                    "id" NOT NULL PRIMARY KEY,
                    "value" VARCHAR(100)
                )
            }
        ],
        drop  => [ 'extra_loader_test1' ],
        count => 2,
        run   => sub {
            my ($schema, $monikers, $classes) = @_;

            ok ((my $rs = $schema->resultset($monikers->{extra_loader_test1})),
                'resultset for quoted table');

            is_deeply [ $rs->result_source->columns ], [ qw/id value/ ],
                'retrieved quoted column names from quoted table';
        },
    },
);

$tester->run_tests();

END {
    unlink './t/sqlite_test';
}
