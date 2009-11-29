use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;
use Test::More;

my $dsn      = $ENV{DBICTEST_PG_DSN} || '';
my $user     = $ENV{DBICTEST_PG_USER} || '';
my $password = $ENV{DBICTEST_PG_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor      => 'Pg',
    auto_inc_pk => 'SERIAL NOT NULL PRIMARY KEY',
    dsn         => $dsn,
    user        => $user,
    password    => $password,
    extra       => {
        create => [
            q{
                CREATE TABLE pg_loader_test1 (
                    id SERIAL NOT NULL PRIMARY KEY,
                    value VARCHAR(100)
                )
            },
            q{
                COMMENT ON TABLE pg_loader_test1 IS 'The Table'
            },
            q{
                COMMENT ON COLUMN pg_loader_test1.value IS 'The Column'
            },
        ],
        drop  => [ qw/ pg_loader_test1 / ],
        count => 2,
        run   => sub {
            my ($schema, $monikers, $classes) = @_;

            my $class    = $classes->{pg_loader_test1};
            my $filename = $schema->_loader->_get_dump_filename($class);

            my $code = do {
                local ($/, @ARGV) = (undef, $filename);
                <>;
            };

            like $code, qr/^=head1 NAME\n\n^$class - The Table\n\n^=cut\n/m,
                'table comment';

            like $code, qr/^=head2 value\n\nThe Column\n\n/m,
                'column comment';
        },
    },
);

if( !$dsn || !$user ) {
    $tester->skip_tests('You need to set the DBICTEST_PG_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
