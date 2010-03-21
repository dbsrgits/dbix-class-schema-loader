use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;
use Test::More;
use Test::Exception;
use List::MoreUtils 'apply';

my $dsn      = $ENV{DBICTEST_SYBASE_DSN} || '';
my $user     = $ENV{DBICTEST_SYBASE_USER} || '';
my $password = $ENV{DBICTEST_SYBASE_PASS} || '';

my $tester = dbixcsl_common_tests->new(
    vendor      => 'sybase',
    auto_inc_pk => 'INTEGER IDENTITY NOT NULL PRIMARY KEY',
    default_function     => 'getdate()',
    default_function_def => 'AS getdate()',
    dsn         => $dsn,
    user        => $user,
    password    => $password,
# Test data types, see http://ispirer.com/wiki/sqlways/sybase/data-types
    data_types  => {
        'integer identity' => { data_type => 'integer', is_auto_increment => 1 },
        'AS getdate()'     => { data_type => undef, inflate_datetime => 1, default_value => \'getdate()' },
        text     => { data_type => 'text' },
        unitext  => { data_type => 'unitext' },
        image    => { data_type => 'image' },
        bigint   => { data_type => 'bigint' },
        int      => { data_type => 'integer' },
        integer  => { data_type => 'integer' },
        smallint => { data_type => 'smallint' },
        tinyint  => { data_type => 'tinyint' },
        date     => { data_type => 'date' },
        time     => { data_type => 'time' },
        datetime => { data_type => 'datetime' },
        smalldatetime  => { data_type => 'smalldatetime' },
        money          => { data_type => 'money' },
        smallmoney     => { data_type => 'smallmoney' },
        timestamp      => { data_type => 'timestamp', inflate_datetime => 0 },
        bit            => { data_type => 'bit' },
        'char(2)'      => { data_type => 'char', size => 2 },
        'nchar(2)'     => { data_type => 'nchar', size => 2 },
        'unichar(2)'   => { data_type => 'unichar', size => 2 },
        'varchar(2)'   => { data_type => 'varchar', size => 2 },
        'nvarchar(2)'  => { data_type => 'nvarchar', size => 2 },
        'univarchar(2)' => { data_type => 'univarchar', size => 2 },
        'binary(2)'    => { data_type => 'binary', size => 2 },
        'varbinary(2)' => { data_type => 'varbinary', size => 2 },
        'double precision' => { data_type => 'double precision' },
        real           => { data_type => 'real' },
        float          => { data_type => 'double precision' },
        'float(14)'    => { data_type => 'real' },
        'float(15)'    => { data_type => 'real' },
        'float(16)'    => { data_type => 'double precision' },
        'float(48)'    => { data_type => 'double precision' },
        'numeric(6,3)' => { data_type => 'numeric', size => [6,3] },
        'decimal(6,3)' => { data_type => 'numeric', size => [6,3] },
        numeric        => { data_type => 'numeric' },
        decimal        => { data_type => 'numeric' },
    },
);

if( !$dsn || !$user ) {
    $tester->skip_tests('You need to set the DBICTEST_SYBASE_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
