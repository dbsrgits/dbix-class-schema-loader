use strict;
use warnings;
use Test::More;
use Test::Exception;

# use this if you keep a copy of DBD::Sybase linked to FreeTDS somewhere else
BEGIN {
  if (my $lib_dirs = $ENV{DBICTEST_MSSQL_PERL5LIB}) {
    unshift @INC, $_ for split /:/, $lib_dirs;
  }
}

use lib qw(t/lib);
use dbixcsl_common_tests;

my $dbd_sybase_dsn      = $ENV{DBICTEST_MSSQL_DSN} || '';
my $dbd_sybase_user     = $ENV{DBICTEST_MSSQL_USER} || '';
my $dbd_sybase_password = $ENV{DBICTEST_MSSQL_PASS} || '';

my $odbc_dsn      = $ENV{DBICTEST_MSSQL_ODBC_DSN} || '';
my $odbc_user     = $ENV{DBICTEST_MSSQL_ODBC_USER} || '';
my $odbc_password = $ENV{DBICTEST_MSSQL_ODBC_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor      => 'mssql',
    auto_inc_pk => 'INTEGER IDENTITY NOT NULL PRIMARY KEY',
    default_function     => 'getdate()',
    default_function_def => 'DATETIME DEFAULT getdate()',
    connect_info => [ ($dbd_sybase_dsn ? {
            dsn         => $dbd_sybase_dsn,
            user        => $dbd_sybase_user,
            password    => $dbd_sybase_password,
        } : ()),
        ($odbc_dsn ? {
            dsn         => $odbc_dsn,
            user        => $odbc_user,
            password    => $odbc_password,
        } : ()),
    ],
    data_types => {
        'int identity' => { data_type => 'int', is_auto_increment => 1 },
    },
    extra => {
        create => [
            q{
                CREATE TABLE [mssql_loader_test1.dot] (
                    id INT IDENTITY NOT NULL PRIMARY KEY,
                    dat VARCHAR(8)
                )
            },
            q{
                CREATE TABLE mssql_loader_test3 (
                    id INT IDENTITY NOT NULL PRIMARY KEY
                )
            },
            q{
                CREATE VIEW mssql_loader_test4 AS
                SELECT * FROM mssql_loader_test3
            },
            # test capitalization of cols in unique constraints
            q{ SET QUOTED_IDENTIFIER ON },
            q{ SET ANSI_NULLS ON },
            q{
                CREATE TABLE [mssql_loader_test5] (
                    [id] INT IDENTITY NOT NULL PRIMARY KEY,
                    [FooCol] INT NOT NULL,
                    [BarCol] INT NOT NULL,
                    UNIQUE ([FooCol], [BarCol])
                )
            },
        ],
        pre_drop_ddl => [
            'CREATE TABLE mssql_loader_test3 (id INT IDENTITY NOT NULL PRIMARY KEY)',
            'DROP VIEW mssql_loader_test4',
        ],
        drop   => [
            '[mssql_loader_test1.dot]',
            'mssql_loader_test3',
            'mssql_loader_test5',
        ],
        count  => 9,
        run    => sub {
            my ($schema, $monikers, $classes) = @_;

# Test that the table above (with '.' in name) gets loaded correctly.
            ok((my $rs = eval {
                $schema->resultset($monikers->{'[mssql_loader_test1.dot]'}) }),
                'got a resultset for table with dot in name');

            ok((my $from = eval { $rs->result_source->from }),
                'got an $rsrc->from for table with dot in name');

            is ref($from), 'SCALAR', '->table with dot in name is a scalar ref';

            is eval { $$from }, "[mssql_loader_test1.dot]",
                '->table with dot in name has correct name';

# Test capitalization of columns and unique constraints
            ok ((my $rsrc = $schema->resultset($monikers->{mssql_loader_test5})->result_source),
                'got result_source');

            is $rsrc->column_info('foocol')->{data_type}, 'int',
                'column names are lowercased';

            my %uniqs = $rsrc->unique_constraints;
            delete $uniqs{primary};

            is_deeply ((values %uniqs)[0], [qw/foocol barcol/],
                'columns in unique constraint lowercased');

# Test that a bad view (where underlying table is gone) is ignored.
            my $dbh = $schema->storage->dbh;
            $dbh->do("DROP TABLE mssql_loader_test3");

            my @warnings;
            {
                local $SIG{__WARN__} = sub { push @warnings, $_[0] };
                $schema->rescan;
            }
            ok ((grep /^Bad table or view 'mssql_loader_test4'/, @warnings),
                'bad view ignored');

            throws_ok {
                $schema->resultset($monikers->{mssql_loader_test4})
            } qr/Can't find source/,
                'no source registered for bad view';
        },
    },
);

if(not ($dbd_sybase_dsn || $odbc_dsn)) {
    $tester->skip_tests('You need to set the DBICTEST_MSSQL_DSN, _USER and _PASS and/or the DBICTEST_MSSQL_ODBC_DSN, _USER and _PASS environment variables');
}
else {
    $tester->run_tests();
}
