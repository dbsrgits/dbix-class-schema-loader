use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;

# to support " quoted identifiers
BEGIN { $ENV{DELIMIDENT} = 'y' }

# This test doesn't run over a shared memory connection, because of the single connection limit.

my $dsn      = $ENV{DBICTEST_INFORMIX_DSN} || '';
my $user     = $ENV{DBICTEST_INFORMIX_USER} || '';
my $password = $ENV{DBICTEST_INFORMIX_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor         => 'Informix',
    auto_inc_pk    => 'serial primary key',
    null           => '',
    default_function     => 'current year to fraction(5)',
    default_function_def => 'datetime year to fraction(5) default current year to fraction(5)',
    dsn            => $dsn,
    user           => $user,
    password       => $password,
    loader_options => { preserve_case => 1 },
    quote_char     => '"',
    data_types => {
        # http://publib.boulder.ibm.com/infocenter/idshelp/v115/index.jsp?topic=/com.ibm.sqlr.doc/ids_sqr_094.htm

        # Numeric Types
        'int'              => { data_type => 'integer' },
        integer            => { data_type => 'integer' },
        int8               => { data_type => 'bigint' },
        bigint             => { data_type => 'bigint' },
        serial             => { data_type => 'integer', is_auto_increment => 1 },
        bigserial          => { data_type => 'bigint',  is_auto_increment => 1 },
        serial8            => { data_type => 'bigint',  is_auto_increment => 1 },
        smallint           => { data_type => 'smallint' },
        real               => { data_type => 'real' },
        smallfloat         => { data_type => 'real' },
        # just 'double' is a syntax error
        'double precision' => { data_type => 'double precision' },
        float              => { data_type => 'double precision' },
        'float(1)'         => { data_type => 'double precision' },
        'float(5)'         => { data_type => 'double precision' },
        'float(10)'        => { data_type => 'double precision' },
        'float(15)'        => { data_type => 'double precision' },
        'float(16)'        => { data_type => 'double precision' },
        numeric            => { data_type => 'numeric' },
        decimal            => { data_type => 'numeric' },
        dec                => { data_type => 'numeric' },
	'numeric(6,3)'     => { data_type => 'numeric', size => [6,3] },
	'decimal(6,3)'     => { data_type => 'numeric', size => [6,3] },
	'dec(6,3)'         => { data_type => 'numeric', size => [6,3] },

        # Boolean Type
        # XXX this should map to 'boolean'
        boolean            => { data_type => 'smallint' },

        # Money Type
        money              => { data_type => 'money' },
        'money(3,3)'       => { data_type => 'numeric', size => [3,3] },

        # Byte Type
        byte               => { data_type => 'bytea', original => { data_type => 'byte' } },

        # Character String Types
        char               => { data_type => 'char', size => 1 },
        'char(3)'          => { data_type => 'char', size => 3 },
        character          => { data_type => 'char', size => 1 },
        'character(3)'     => { data_type => 'char', size => 3 },
        'varchar(3)'       => { data_type => 'varchar', size => 3 },
        'character varying(3)'
                           => { data_type => 'varchar', size => 3 },
        # XXX min size not supported, colmin from syscolumns is NULL
        'varchar(3,2)'     => { data_type => 'varchar', size => 3 },
        'character varying(3,2)'
                           => { data_type => 'varchar', size => 3 },
        nchar              => { data_type => 'nchar', size => 1 },
        'nchar(3)'         => { data_type => 'nchar', size => 3 },
        'nvarchar(3)'      => { data_type => 'nvarchar', size => 3 },
        'nvarchar(3,2)'    => { data_type => 'nvarchar', size => 3 },
        'lvarchar(3)'      => { data_type => 'lvarchar', size => 3 },
        'lvarchar(33)'     => { data_type => 'lvarchar', size => 33 },
        text               => { data_type => 'text' },

        # DateTime Types
        date               => { data_type => 'date' },
        'date default today'
                           => { data_type => 'date', default_value => \'today' },
        # XXX support all precisions
        'datetime year to fraction(5)',
                           => { data_type => 'datetime year to fraction(5)' },
        'datetime year to fraction(5) default current year to fraction(5)',
                           => { data_type => 'datetime year to fraction(5)', default_value => \'current year to fraction(5)' },
        # XXX do interval

        # Blob Types
        # XXX no way to distinguish opaque types boolean, blob and clob
        blob               => { data_type => 'blob' },
        clob               => { data_type => 'blob' },

        # IDSSECURITYLABEL Type
        #
        # This requires the DBSECADM privilege and a security policy on the
        # table, things I know nothing about.
#        idssecuritylabel   => { data_type => 'idssecuritylabel' },

        # List Types
        # XXX need to introspect element type too
        'list(varchar(20) not null)'
                           => { data_type => 'list' },
        'multiset(varchar(20) not null)'
                           => { data_type => 'multiset' },
        'set(varchar(20) not null)'
                           => { data_type => 'set' },
    },
);

if( !$dsn ) {
    $tester->skip_tests('You need to set the DBICTEST_INFORMIX_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
# vim:et sts=4 sw=4 tw=0:
