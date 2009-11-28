use strict;
use lib qw(t/backcompat/0.04006/lib);
use dbixcsl_common_tests;

eval { require DBD::SQLite };
my $class = $@ ? 'SQLite2' : 'SQLite';

{
    my $tester = dbixcsl_common_tests->new(
        vendor          => 'SQLite',
        auto_inc_pk     => 'INTEGER NOT NULL PRIMARY KEY',
        dsn             => "dbi:$class:dbname=./t/sqlite_test",
        user            => '',
        password        => '',
    );

    $tester->run_tests();
}

END {
    unlink './t/sqlite_test';
}
