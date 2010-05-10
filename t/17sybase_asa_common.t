use strict;
use warnings;
use lib qw(t/lib);
use dbixcsl_common_tests;

# The default max_cursor_count and max_statement_count settings of 50 are too
# low to run this test.
#
# Setting them to zero is preferred.

my $dbd_sqlanywhere_dsn      = $ENV{DBICTEST_SYBASE_ASA_DSN} || '';
my $dbd_sqlanywhere_user     = $ENV{DBICTEST_SYBASE_ASA_USER} || '';
my $dbd_sqlanywhere_password = $ENV{DBICTEST_SYBASE_ASA_PASS} || '';

my $odbc_dsn      = $ENV{DBICTEST_SYBASE_ASA_ODBC_DSN} || '';
my $odbc_user     = $ENV{DBICTEST_SYBASE_ASA_ODBC_USER} || '';
my $odbc_password = $ENV{DBICTEST_SYBASE_ASA_ODBC_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor      => 'SQLAnywhere',
    auto_inc_pk => 'INTEGER IDENTITY NOT NULL PRIMARY KEY',
    connect_info => [ ($dbd_sqlanywhere_dsn ? {
            dsn         => $dbd_sqlanywhere_dsn,
            user        => $dbd_sqlanywhere_user,
            password    => $dbd_sqlanywhere_password,
        } : ()),
        ($odbc_dsn ? {
            dsn         => $odbc_dsn,
            user        => $odbc_user,
            password    => $odbc_password,
        } : ()),
    ],
    loader_options => { preserve_case => 1 },
    data_types  => {
        # http://infocenter.sybase.com/help/topic/com.sybase.help.sqlanywhere.11.0.1/dbreference_en11/rf-datatypes.html
        #
        # Numeric types
        'bit'         => { data_type => 'bit' },
        'tinyint'     => { data_type => 'tinyint' },
        'smallint'    => { data_type => 'smallint' },
        'int'         => { data_type => 'integer' },
        'integer'     => { data_type => 'integer' },
        'bigint'      => { data_type => 'bigint' },
        'float'       => { data_type => 'real' },
        'real'        => { data_type => 'real' },
        'double'      => { data_type => 'double precision' },
        'double precision' =>
                         { data_type => 'double precision' },

        'float(2)'    => { data_type => 'real' },
        'float(24)'   => { data_type => 'real' },
        'float(25)'   => { data_type => 'double precision' },
        'float(53)'   => { data_type => 'double precision' },

        # This test only works with the default precision and scale options.
        #
        # They are preserved even for the default values, because the defaults
        # can be changed.
        'decimal'     => { data_type => 'decimal', size => [30,6] },
        'dec'         => { data_type => 'decimal', size => [30,6] },
        'numeric'     => { data_type => 'numeric', size => [30,6] },

        'decimal(3)'   => { data_type => 'decimal', size => [3,0] },
        'dec(3)'       => { data_type => 'decimal', size => [3,0] },
        'numeric(3)'   => { data_type => 'numeric', size => [3,0] },

        'decimal(3,3)' => { data_type => 'decimal', size => [3,3] },
        'dec(3,3)'     => { data_type => 'decimal', size => [3,3] },
        'numeric(3,3)' => { data_type => 'numeric', size => [3,3] },

        'decimal(18,18)' => { data_type => 'decimal', size => [18,18] },
        'dec(18,18)'     => { data_type => 'decimal', size => [18,18] },
        'numeric(18,18)' => { data_type => 'numeric', size => [18,18] },

        # money types
        'money'        => { data_type => 'money' },
        'smallmoney'   => { data_type => 'smallmoney' },

        # bit arrays
        'long varbit'  => { data_type => 'long varbit' },
        'long bit varying'
                       => { data_type => 'long varbit' },
        'varbit'       => { data_type => 'varbit', size => 1 },
        'varbit(20)'   => { data_type => 'varbit', size => 20 },
        'bit varying'  => { data_type => 'varbit', size => 1 },
        'bit varying(20)'
                       => { data_type => 'varbit', size => 20 },

        # Date and Time Types
        'date'        => { data_type => 'date' },
        'datetime'    => { data_type => 'datetime' },
        'smalldatetime'
                      => { data_type => 'smalldatetime' },
        'timestamp'   => { data_type => 'timestamp' },
        # rewrite 'current timestamp' as 'current_timestamp'
        'timestamp default current timestamp'
                      => { data_type => 'timestamp', default_value => \'current_timestamp',
                           original => { default_value => \'current timestamp' } },
        'time'        => { data_type => 'time' },

        # String Types
        'char'         => { data_type => 'char',      size => 1  },
        'char(11)'     => { data_type => 'char',      size => 11 },
        'nchar'        => { data_type => 'nchar',     size => 1  },
        'nchar(11)'    => { data_type => 'nchar',     size => 11 },
        'varchar'      => { data_type => 'varchar',   size => 1  },
        'varchar(20)'  => { data_type => 'varchar',   size => 20 },
        'char varying(20)'
                       => { data_type => 'varchar',   size => 20 },
        'character varying(20)'
                       => { data_type => 'varchar',   size => 20 },
        'nvarchar(20)' => { data_type => 'nvarchar',  size => 20 },
        'xml'          => { data_type => 'xml' },
        'uniqueidentifierstr'
                       => { data_type => 'uniqueidentifierstr' },

        # Binary types
        'binary'       => { data_type => 'binary', size => 1 },
        'binary(20)'   => { data_type => 'binary', size => 20 },
        'varbinary'    => { data_type => 'varbinary', size => 1 },
        'varbinary(20)'=> { data_type => 'varbinary', size => 20 },
        'uniqueidentifier'
                       => { data_type => 'uniqueidentifier' },

        # Blob types
        'long binary'  => { data_type => 'long binary' },
        'image'        => { data_type => 'image' },
        'long varchar' => { data_type => 'long varchar' },
        'text'         => { data_type => 'text' },
        'long nvarchar'=> { data_type => 'long nvarchar' },
        'ntext'        => { data_type => 'ntext' },
    },

);

if (not ($dbd_sqlanywhere_dsn || $odbc_dsn)) {
    $tester->skip_tests('You need to set the DBICTEST_SYBASE_ASA_DSN, _USER and _PASS and/or the DBICTEST_SYBASE_ASA_ODBC_DSN, _USER and _PASS environment variables');
}
else {
    $tester->run_tests();
}
# vim:et sts=4 sw=4 tw=0:
