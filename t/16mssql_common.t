use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warn;

# use this if you keep a copy of DBD::Sybase linked to FreeTDS somewhere else
BEGIN {
  if (my $lib_dirs = $ENV{DBICTEST_MSSQL_PERL5LIB}) {
    unshift @INC, $_ for split /:/, $lib_dirs;
  }
}

my ($dsns, $common_version);
for (qw/MSSQL MSSQL_ODBC/) {
  next unless $ENV{"DBICTEST_${_}_DSN"};

  $dsns->{$_}{dsn} = $ENV{"DBICTEST_${_}_DSN"};
  $dsns->{$_}{user} = $ENV{"DBICTEST_${_}_USER"};
  $dsns->{$_}{password} = $ENV{"DBICTEST_${_}_PASS"};

  require DBI;
  my $dbh = DBI->connect (@{$dsns->{$_}}{qw/dsn user password/}, { RaiseError => 1, PrintError => 0} );
  my $srv_ver = eval {
    $dbh->get_info(18)
      ||
    $dbh->selectrow_hashref('master.dbo.xp_msver ProductVersion')->{Character_Value}
  } || 0;

  my ($maj_srv_ver) = $srv_ver =~ /^(\d+)/;

  if (! defined $common_version or $common_version > $maj_srv_ver ) {
    $common_version = $maj_srv_ver;
  }
}

plan skip_all => 'You need to set the DBICTEST_MSSQL_DSN, _USER and _PASS and/or the DBICTEST_MSSQL_ODBC_DSN, _USER and _PASS environment variables'
  unless $dsns;

use lib qw(t/lib);
use dbixcsl_common_tests;

my $mssql_2008_new_data_types = {
  date     => { data_type => 'date' },
  time     => { data_type => 'time' },
  'time(0)'=> { data_type => 'time', size => 0 },
  'time(1)'=> { data_type => 'time', size => 1 },
  'time(2)'=> { data_type => 'time', size => 2 },
  'time(3)'=> { data_type => 'time', size => 3 },
  'time(4)'=> { data_type => 'time', size => 4 },
  'time(5)'=> { data_type => 'time', size => 5 },
  'time(6)'=> { data_type => 'time', size => 6 },
  'time(7)'=> { data_type => 'time' },
  datetimeoffset => { data_type => 'datetimeoffset' },
  'datetimeoffset(0)' => { data_type => 'datetimeoffset', size => 0 },
  'datetimeoffset(1)' => { data_type => 'datetimeoffset', size => 1 },
  'datetimeoffset(2)' => { data_type => 'datetimeoffset', size => 2 },
  'datetimeoffset(3)' => { data_type => 'datetimeoffset', size => 3 },
  'datetimeoffset(4)' => { data_type => 'datetimeoffset', size => 4 },
  'datetimeoffset(5)' => { data_type => 'datetimeoffset', size => 5 },
  'datetimeoffset(6)' => { data_type => 'datetimeoffset', size => 6 },
  'datetimeoffset(7)' => { data_type => 'datetimeoffset' },
  datetime2      => { data_type => 'datetime2' },
  'datetime2(0)' => { data_type => 'datetime2', size => 0 },
  'datetime2(1)' => { data_type => 'datetime2', size => 1 },
  'datetime2(2)' => { data_type => 'datetime2', size => 2 },
  'datetime2(3)' => { data_type => 'datetime2', size => 3 },
  'datetime2(4)' => { data_type => 'datetime2', size => 4 },
  'datetime2(5)' => { data_type => 'datetime2', size => 5 },
  'datetime2(6)' => { data_type => 'datetime2', size => 6 },
  'datetime2(7)' => { data_type => 'datetime2' },

  hierarchyid      => { data_type => 'hierarchyid' },
};

my $tester = dbixcsl_common_tests->new(
    vendor      => 'mssql',
    auto_inc_pk => 'INTEGER IDENTITY NOT NULL PRIMARY KEY',
    default_function_def => 'DATETIME DEFAULT getdate()',
    connect_info => [values %$dsns],
    preserve_case_mode_is_exclusive => 1,
    quote_char => [ qw/[ ]/ ],
    basic_date_datatype => ($common_version >= 10) ? 'DATE' : 'SMALLDATETIME',
    data_types => {
        # http://msdn.microsoft.com/en-us/library/ms187752.aspx

        # numeric types
        'int identity' => { data_type => 'integer', is_auto_increment => 1 },
        bigint   => { data_type => 'bigint' },
        int      => { data_type => 'integer' },
        integer  => { data_type => 'integer' },
        smallint => { data_type => 'smallint' },
        tinyint  => { data_type => 'tinyint' },
        money       => { data_type => 'money' },
        smallmoney  => { data_type => 'smallmoney' },
        bit         => { data_type => 'bit' },
        real           => { data_type => 'real' },
        'float(14)'    => { data_type => 'real' },
        'float(24)'    => { data_type => 'real' },
        'float(25)'    => { data_type => 'double precision' },
        'float(53)'    => { data_type => 'double precision' },
        float          => { data_type => 'double precision' },
        'double precision'
                       => { data_type => 'double precision' },
        'numeric(6,3)' => { data_type => 'numeric', size => [6,3] },
        'decimal(6,3)' => { data_type => 'decimal', size => [6,3] },
        'dec(6,3)'     => { data_type => 'decimal', size => [6,3] },
        numeric        => { data_type => 'numeric' },
        decimal        => { data_type => 'decimal' },
        dec            => { data_type => 'decimal' },

        # datetime types
        datetime => { data_type => 'datetime' },
        # test rewriting getdate() to current_timestamp
        'datetime default getdate()'
                 => { data_type => 'datetime', default_value => \'current_timestamp',
                      original => { default_value => \'getdate()' } },
        smalldatetime  => { data_type => 'smalldatetime' },

        ($common_version >= 10) ? %$mssql_2008_new_data_types : (),

        # string types
        char           => { data_type => 'char', size => 1 },
        'char(2)'      => { data_type => 'char', size => 2 },
        character      => { data_type => 'char', size => 1 },
        'character(2)' => { data_type => 'char', size => 2 },
        'varchar(2)'   => { data_type => 'varchar', size => 2 },
        nchar          => { data_type => 'nchar', size => 1 },
        'nchar(2)'     => { data_type => 'nchar', size => 2 },
        'nvarchar(2)'  => { data_type => 'nvarchar', size => 2 },

        # binary types
        'binary'       => { data_type => 'binary', size => 1 },
        'binary(2)'    => { data_type => 'binary', size => 2 },
        'varbinary(2)' => { data_type => 'varbinary', size => 2 },

        # blob types
        'varchar(max)'   => { data_type => 'text' },
        text             => { data_type => 'text' },
        'nvarchar(max)'  => { data_type => 'ntext' },
        ntext            => { data_type => 'ntext' },
        'varbinary(max)' => { data_type => 'image' },
        image            => { data_type => 'image' },

        # other types
        timestamp        => { data_type => 'timestamp', inflate_datetime => 0 },
        rowversion       => { data_type => 'rowversion' },
        uniqueidentifier => { data_type => 'uniqueidentifier' },
        sql_variant      => { data_type => 'sql_variant' },
        xml              => { data_type => 'xml' },
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
            # test capitalization of cols in unique constraints and rels
            q{ SET QUOTED_IDENTIFIER ON },
            q{ SET ANSI_NULLS ON },
            q{
                CREATE TABLE [MSSQL_Loader_Test5] (
                    [Id] INT IDENTITY NOT NULL PRIMARY KEY,
                    [FooCol] INT NOT NULL,
                    [BarCol] INT NOT NULL,
                    UNIQUE ([FooCol], [BarCol])
                )
            },
            q{
                CREATE TABLE [MSSQL_Loader_Test6] (
                    [Five_Id] INT REFERENCES [MSSQL_Loader_Test5] ([Id])
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
            'MSSQL_Loader_Test6',
            'MSSQL_Loader_Test5',
        ],
        count  => 10,
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

            if ($schema->_loader->preserve_case) {
                is_deeply [ $rsrc->columns ], [qw/Id FooCol BarCol/],
                    'column name case is preserved with case-sensitive collation';

                my %uniqs = $rsrc->unique_constraints;
                delete $uniqs{primary};

                is_deeply ((values %uniqs)[0], [qw/FooCol BarCol/],
                    'column name case is preserved in unique constraint with case-sensitive collation');
            }
            else {
                is_deeply [ $rsrc->columns ], [qw/id foocol barcol/],
                    'column names are lowercased for case-insensitive collation';

                my %uniqs = $rsrc->unique_constraints;
                delete $uniqs{primary};

                is_deeply ((values %uniqs)[0], [qw/foocol barcol/],
                    'columns in unique constraint lowercased for case-insensitive collation');
            }

            lives_and {
                my $five_row = $schema->resultset($monikers->{mssql_loader_test5})->new_result({});

                if ($schema->_loader->preserve_case) {
                    $five_row->foo_col(1);
                    $five_row->bar_col(2);
                }
                else {
                    $five_row->foocol(1);
                    $five_row->barcol(2);
                }
                $five_row->insert;

                my $six_row = $five_row->create_related('mssql_loader_test6s', {});

                is $six_row->five->id, 1;
            } 'relationships for mixed-case tables/columns detected';

# Test that a bad view (where underlying table is gone) is ignored.
            my $dbh = $schema->storage->dbh;
            $dbh->do("DROP TABLE mssql_loader_test3");

            warnings_exist { $schema->rescan }
              qr/^Bad table or view 'mssql_loader_test4'/, 'bad view ignored';

            throws_ok {
                $schema->resultset($monikers->{mssql_loader_test4})
            } qr/Can't find source/,
                'no source registered for bad view';
        },
    },
);

$tester->run_tests();

# vim:et sts=4 sw=4 tw=0:
