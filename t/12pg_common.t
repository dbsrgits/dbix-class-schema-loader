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
	'bigint'    => { size => undef, data_type => 'bigint' },
	'int8'      => { size => undef, data_type => 'bigint' },
	'bigserial' => { size => undef, data_type => 'bigint', is_auto_increment => 1 },
	'serial8'   => { size => undef, data_type => 'bigint', is_auto_increment => 1 },
	'bit'       => { size => undef, data_type => 'bit' },
	'boolean'   => { size => undef, data_type => 'boolean' },
	'bool'      => { size => undef, data_type => 'boolean' },
	'box'       => { size => undef, data_type => 'box' },
	'bytea'     => { size => undef, data_type => 'bytea' },
	'cidr'      => { size => undef, data_type => 'cidr' },
	'circle'    => { size => undef, data_type => 'circle' },
	'date'      => { size => undef, data_type => 'date' },
	'double precision' => { size => undef, data_type => 'double precision' },
	'float8'      => { size => undef, data_type => 'double precision' },
	'inet'        => { size => undef, data_type => 'inet' },
	'integer'     => { size => undef, data_type => 'integer' },
	'int'         => { size => undef, data_type => 'integer' },
	'int4'        => { size => undef, data_type => 'integer' },
	'interval'    => { size => undef, data_type => 'interval' },
	'interval(2)' => { size => 2, data_type => 'interval' },
	'line'        => { size => undef, data_type => 'line' },
	'lseg'        => { size => undef, data_type => 'lseg' },
	'macaddr'     => { size => undef, data_type => 'macaddr' },
	'money'       => { size => undef, data_type => 'money' },
	'path'        => { size => undef, data_type => 'path' },
	'point'       => { size => undef, data_type => 'point' },
	'polygon'     => { size => undef, data_type => 'polygon' },
	'real'        => { size => undef, data_type => 'real' },
	'float4'      => { size => undef, data_type => 'real' },
	'smallint'    => { size => undef, data_type => 'smallint' },
	'int2'        => { size => undef, data_type => 'smallint' },
	'serial'      => { size => undef, data_type => 'integer', is_auto_increment => 1 },
	'serial4'     => { size => undef, data_type => 'integer', is_auto_increment => 1 },
	'text'        => { size => undef, data_type => 'text' },
	'time'        => { size => undef, data_type => 'time without time zone' },
	'time(2)'     => { size => 2, data_type => 'time without time zone' },
	'time without time zone'         => { size => undef, data_type => 'time without time zone' },
	'time(2) without time zone'      => { size => 2, data_type => 'time without time zone' },
	'time with time zone'            => { size => undef, data_type => 'time with time zone' },
	'time(2) with time zone'         => { size => 2, data_type => 'time with time zone' },
	'timestamp'                      => { size => undef, data_type => 'timestamp without time zone' },
	'timestamp(2)'                   => { size => 2, data_type => 'timestamp without time zone' },
	'timestamp without time zone'    => { size => undef, data_type => 'timestamp without time zone' },
	'timestamp(2) without time zone' => { size => 2, data_type => 'timestamp without time zone' },
	'timestamp with time zone'       => { size => undef, data_type => 'timestamp with time zone' },
	'timestamp(2) with time zone'    => { size => 2, data_type => 'timestamp with time zone' },
	'bit varying(2)'                 => { size => 2, data_type => 'bit varying' },
	'varbit(2)'                      => { size => 2, data_type => 'bit varying' },
	'character varying(2)'           => { size => 2, data_type => 'character varying' },
	'varchar(2)'                     => { size => 2, data_type => 'character varying' },
	'character(2)'                   => { size => 2, data_type => 'character' },
	'char(2)'                        => { size => 2, data_type => 'character' },
	'numeric(6, 3)'                  => { size => [6,3], data_type => 'numeric' },
	'decimal(6, 3)'                  => { size => [6,3], data_type => 'numeric' },
        'float(24)'                      => { size => undef, data_type => 'real' },
        'float(53)'                      => { size => undef, data_type => 'double precision' },
        'float'                          => { size => undef, data_type => 'double precision' },
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
