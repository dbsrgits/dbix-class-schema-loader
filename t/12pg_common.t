use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;
use Test::More;
use File::Slurp 'slurp';

my $dsn      = $ENV{DBICTEST_PG_DSN} || '';
my $user     = $ENV{DBICTEST_PG_USER} || '';
my $password = $ENV{DBICTEST_PG_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor      => 'Pg',
    auto_inc_pk => 'SERIAL NOT NULL PRIMARY KEY',
    default_function => 'now()',
    dsn         => $dsn,
    user        => $user,
    password    => $password,
    data_types  => {
	bigint    => { data_type => 'bigint' },
	int8      => { data_type => 'bigint' },
	bigserial => { data_type => 'bigint', is_auto_increment => 1 },
	serial8   => { data_type => 'bigint', is_auto_increment => 1 },
	bit       => { data_type => 'bit' },
	boolean   => { data_type => 'boolean' },
	bool      => { data_type => 'boolean' },
	box       => { data_type => 'box' },
	bytea     => { data_type => 'bytea' },
	cidr      => { data_type => 'cidr' },
	circle    => { data_type => 'circle' },
	date      => { data_type => 'date' },
	'double precision' => { data_type => 'double precision' },
	float8      => { data_type => 'double precision' },
	inet        => { data_type => 'inet' },
	integer     => { data_type => 'integer' },
	int         => { data_type => 'integer' },
	int4        => { data_type => 'integer' },
	interval    => { data_type => 'interval' },
	'interval(2)' => { size => 2, data_type => 'interval' },
	line        => { data_type => 'line' },
	lseg        => { data_type => 'lseg' },
	macaddr     => { data_type => 'macaddr' },
	money       => { data_type => 'money' },
	path        => { data_type => 'path' },
	point       => { data_type => 'point' },
	polygon     => { data_type => 'polygon' },
	real        => { data_type => 'real' },
	float4      => { data_type => 'real' },
	smallint    => { data_type => 'smallint' },
	int2        => { data_type => 'smallint' },
	serial      => { data_type => 'integer', is_auto_increment => 1 },
	serial4     => { data_type => 'integer', is_auto_increment => 1 },
	text        => { data_type => 'text' },
	time        => { data_type => 'time without time zone' },
	'time(2)'     => { size => 2, data_type => 'time without time zone' },
	'time without time zone'         => { data_type => 'time without time zone' },
	'time(2) without time zone'      => { size => 2, data_type => 'time without time zone' },
	'time with time zone'            => { data_type => 'time with time zone' },
	'time(2) with time zone'         => { size => 2, data_type => 'time with time zone' },
	timestamp                        => { data_type => 'timestamp without time zone' },
	'timestamp(2)'                   => { size => 2, data_type => 'timestamp without time zone' },
	'timestamp without time zone'    => { data_type => 'timestamp without time zone' },
	'timestamp(2) without time zone' => { size => 2, data_type => 'timestamp without time zone' },
	'timestamp with time zone'       => { data_type => 'timestamp with time zone' },
	'timestamp(2) with time zone'    => { size => 2, data_type => 'timestamp with time zone' },
	'bit varying(2)'                 => { size => 2, data_type => 'bit varying' },
	'varbit(2)'                      => { size => 2, data_type => 'bit varying' },
	'character varying(2)'           => { size => 2, data_type => 'character varying' },
	'varchar(2)'                     => { size => 2, data_type => 'character varying' },
	'character(2)'                   => { size => 2, data_type => 'character' },
	'char(2)'                        => { size => 2, data_type => 'character' },
	'numeric(6, 3)'                  => { size => [6,3], data_type => 'numeric' },
	'decimal(6, 3)'                  => { size => [6,3], data_type => 'numeric' },
        numeric                          => { data_type => 'numeric' },
        decimal                          => { data_type => 'numeric' },
        'float(24)'                      => { data_type => 'real' },
        'float(53)'                      => { data_type => 'double precision' },
        float                            => { data_type => 'double precision' },
    },
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
            q{
                CREATE TABLE pg_loader_test2 (
                    id SERIAL NOT NULL PRIMARY KEY,
                    value VARCHAR(100)
                )
            },
            q{
                COMMENT ON TABLE pg_loader_test2 IS 'very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very long comment'
            },
        ],
        drop  => [ qw/ pg_loader_test1 pg_loader_test2 / ],
        count => 3,
        run   => sub {
            my ($schema, $monikers, $classes) = @_;

            my $class    = $classes->{pg_loader_test1};
            my $filename = $schema->_loader->_get_dump_filename($class);

            my $code = slurp $filename;

            like $code, qr/^=head1 NAME\n\n^$class - The Table\n\n^=cut\n/m,
                'table comment';

            like $code, qr/^=head2 value\n\n(.+:.+\n)+\nThe Column\n\n/m,
                'column comment and attrs';

            $class    = $classes->{pg_loader_test2};
            $filename = $schema->_loader->_get_dump_filename($class);

            $code = slurp $filename;

            like $code, qr/^=head1 NAME\n\n^$class\n\n=head1 DESCRIPTION\n\n^very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very very long comment\n\n^=cut\n/m,
                'long table comment is in DESCRIPTION';
        },
    },
);

if( !$dsn || !$user ) {
    $tester->skip_tests('You need to set the DBICTEST_PG_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
