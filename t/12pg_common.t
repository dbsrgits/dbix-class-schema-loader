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
    loader_options  => { preserve_case => 1 },
    connect_info_opts => {
        on_connect_do => [ 'SET client_min_messages=WARNING' ],
    },
    quote_char  => '"',
    data_types  => {
        # http://www.postgresql.org/docs/7.4/interactive/datatype.html
        #
        # Numeric Types
	boolean     => { data_type => 'boolean' },
	bool        => { data_type => 'boolean' },
        'bool default false'
                    => { data_type => 'boolean', default_value => \'false' },

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
	'numeric(6,3)' => { data_type => 'numeric', size => [6,3] },
	'decimal(6,3)' => { data_type => 'numeric', size => [6,3] },

        # Bit String Types
	'bit varying(2)' => { data_type => 'varbit', size => 2 },
	'varbit(2)'      => { data_type => 'varbit', size => 2 },
	'varbit'         => { data_type => 'varbit' },
	bit              => { data_type => 'bit', size => 1 },
	'bit(3)'         => { data_type => 'bit', size => 3 },

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
	'character varying(2)'           => { data_type => 'varchar', size => 2 },
	'varchar(2)'                     => { data_type => 'varchar', size => 2 },
	'character(2)'                   => { data_type => 'char', size => 2 },
	'char(2)'                        => { data_type => 'char', size => 2 },
	'character'                      => { data_type => 'char', size => 1 },
	'char'                           => { data_type => 'char', size => 1 },
	text                             => { data_type => 'text' },
        # varchar with no size has unlimited size, we rewrite to 'text'
	varchar                          => { data_type => 'text',
                                              original => { data_type => 'varchar' } },

        # Datetime Types
	date                             => { data_type => 'date' },
	interval                         => { data_type => 'interval' },
	'interval(2)'                    => { data_type => 'interval', size => 2 },
	time                             => { data_type => 'time' },
	'time(2)'                        => { data_type => 'time', size => 2 },
	'time without time zone'         => { data_type => 'time' },
	'time(2) without time zone'      => { data_type => 'time', size => 2 },
	'time with time zone'            => { data_type => 'time with time zone' },
	'time(2) with time zone'         => { data_type => 'time with time zone', size => 2 },
	timestamp                        => { data_type => 'timestamp' },
        'timestamp default now()'
                                         => { data_type => 'timestamp', default_value => \'current_timestamp',
                                              original => { default_value => \'now()' } },
	'timestamp(2)'                   => { data_type => 'timestamp', size => 2 },
	'timestamp without time zone'    => { data_type => 'timestamp' },
	'timestamp(2) without time zone' => { data_type => 'timestamp', size => 2 },

	'timestamp with time zone'       => { data_type => 'timestamp with time zone' },
	'timestamp(2) with time zone'    => { data_type => 'timestamp with time zone', size => 2 },

        # Blob Types
	bytea => { data_type => 'bytea' },
    },
    extra       => {
        create => [
            q{
                CREATE SCHEMA dbicsl_test
            },
            q{
                CREATE SEQUENCE dbicsl_test.myseq
            },
            q{
                CREATE TABLE pg_loader_test1 (
                    id INTEGER NOT NULL DEFAULT nextval('dbicsl_test.myseq') PRIMARY KEY,
                    value VARCHAR(100)
                )
            },
            qq{
                COMMENT ON TABLE pg_loader_test1 IS 'The\15\12Table'
            },
            qq{
                COMMENT ON COLUMN pg_loader_test1.value IS 'The\15\12Column'
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
        pre_drop_ddl => [
            'DROP SCHEMA dbicsl_test CASCADE',
        ],
        drop  => [ qw/ pg_loader_test1 pg_loader_test2 / ],
        count => 4,
        run   => sub {
            my ($schema, $monikers, $classes) = @_;

            is $schema->source($monikers->{pg_loader_test1})->column_info('id')->{sequence},
                'dbicsl_test.myseq',
                'qualified sequence detected';

            my $class    = $classes->{pg_loader_test1};
            my $filename = $schema->_loader->_get_dump_filename($class);

            my $code = slurp $filename;

            like $code, qr/^=head1 NAME\n\n^$class - The\nTable\n\n^=cut\n/m,
                'table comment';

            like $code, qr/^=head2 value\n\n(.+:.+\n)+\nThe\nColumn\n\n/m,
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
