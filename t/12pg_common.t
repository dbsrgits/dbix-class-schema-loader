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
    dsn         => $dsn,
    user        => $user,
    password    => $password,
    data_types  => {
        # http://www.postgresql.org/docs/7.4/interactive/datatype.html
        #
        # Numeric Types
	boolean     => { data_type => 'boolean' },
	bool        => { data_type => 'boolean' },

	bigint      => { data_type => 'bigint' },
	int8        => { data_type => 'bigint' },
	bigserial   => { data_type => 'bigint', is_auto_increment => 1 },
	serial8     => { data_type => 'bigint', is_auto_increment => 1 },
	integer     => { data_type => 'integer' },
	int         => { data_type => 'integer' },
	int4        => { data_type => 'integer' },
	serial      => { data_type => 'integer', is_auto_increment => 1 },
	serial4     => { data_type => 'integer', is_auto_increment => 1 },
	smallint    => { data_type => 'smallint' },
	int2        => { data_type => 'smallint' },

	money       => { data_type => 'money' },

	'double precision' => { data_type => 'double precision' },
	float8             => { data_type => 'double precision' },
	real               => { data_type => 'real' },
	float4             => { data_type => 'real' },
        'float(24)'        => { data_type => 'real' },
        'float(25)'        => { data_type => 'double precision' },
        'float(53)'        => { data_type => 'double precision' },
        float              => { data_type => 'double precision' },

        numeric        => { data_type => 'numeric' },
        decimal        => { data_type => 'numeric' },
	'numeric(6,3)' => { size => [6,3], data_type => 'numeric' },
	'decimal(6,3)' => { size => [6,3], data_type => 'numeric' },

        # Bit String Types
        #
        # XXX alias 'bit varying' to 'varbit'
	'bit varying(2)' => { size => 2, data_type => 'bit varying' },
	'varbit(2)'      => { size => 2, data_type => 'bit varying' },
	'varbit'         => { size => 1, data_type => 'bit varying' },
        # XXX support bit(n)
	bit              => { data_type => 'bit' },

        # Network Types
	inet    => { data_type => 'inet' },
	cidr    => { data_type => 'cidr' },
	macaddr => { data_type => 'macaddr' },

        # Geometric Types
	point   => { data_type => 'point' },
	line    => { data_type => 'line' },
	lseg    => { data_type => 'lseg' },
	box     => { data_type => 'box' },
	path    => { data_type => 'path' },
	polygon => { data_type => 'polygon' },
	circle  => { data_type => 'circle' },

        # Character Types
        # XXX alias 'character varying' to 'varchar'
	'character varying(2)'           => { size => 2, data_type => 'character varying' },
	'varchar(2)'                     => { size => 2, data_type => 'character varying' },

        # XXX alias 'character' to 'char'
	'character(2)'                   => { size => 2, data_type => 'character' },
	'char(2)'                        => { size => 2, data_type => 'character' },
	'character'                      => { size => 1, data_type => 'character' },
	'char'                           => { size => 1, data_type => 'character' },
	text                             => { data_type => 'text' },

        # Datetime Types
	date                             => { data_type => 'date' },
	interval                         => { data_type => 'interval' },
	'interval(2)'                    => { size => 2, data_type => 'interval' },
	time                             => { data_type => 'time without time zone' },
	'time(2)'                        => { size => 2, data_type => 'time without time zone' },
	'time without time zone'         => { data_type => 'time without time zone' },
	'time(2) without time zone'      => { size => 2, data_type => 'time without time zone' },
	'time with time zone'            => { data_type => 'time with time zone' },
	'time(2) with time zone'         => { size => 2, data_type => 'time with time zone' },

        # XXX alias 'timestamp without time zone' to 'timestamp'
	timestamp                        => { data_type => 'timestamp without time zone' },
        'timestamp default current_timestamp'
                                         => { data_type => 'timestamp without time zone', default_value => \'current_timestamp' },
	'timestamp(2)'                   => { size => 2, data_type => 'timestamp without time zone' },
	'timestamp without time zone'    => { data_type => 'timestamp without time zone' },
	'timestamp(2) without time zone' => { size => 2, data_type => 'timestamp without time zone' },

	'timestamp with time zone'       => { data_type => 'timestamp with time zone' },
	'timestamp(2) with time zone'    => { size => 2, data_type => 'timestamp with time zone' },

        # Blob Types
	bytea => { data_type => 'bytea' },
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
# vim:et sw=4 sts=4 tw=0:
