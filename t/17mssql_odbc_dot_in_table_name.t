use strict;
use lib qw(t/lib);
use Test::More;
use DBI;

my $DUMP_DIR;
BEGIN { 
    $DUMP_DIR = './t/_common_dump';
}

use lib $DUMP_DIR;
use DBIx::Class::Schema::Loader 'make_schema_at', "dump_to_dir:$DUMP_DIR";
use File::Path;

my $dsn      = $ENV{DBICTEST_MSSQL_ODBC_DSN} || '';
my $user     = $ENV{DBICTEST_MSSQL_ODBC_USER} || '';
my $password = $ENV{DBICTEST_MSSQL_ODBC_PASS} || '';

if( !$dsn || !$user ) {
    plan skip_all => 'You need to set the DBICTEST_MSSQL_ODBC_DSN, _USER, and _PASS environment variables';
    exit;
}

plan tests => 3;

my $dbh = DBI->connect($dsn, $user, $password, {
    RaiseError => 1, PrintError => 0
});

eval { $dbh->do('DROP TABLE [test.dot]') };
$dbh->do(q{
    CREATE TABLE [test.dot] (
        id INT IDENTITY NOT NULL PRIMARY KEY,
        dat VARCHAR(8)
    )
});

rmtree $DUMP_DIR;

eval {
    make_schema_at(
        'TestSL::Schema', 
        { use_namespaces => 1 },
        [ $dsn, $user, $password, ]
    );
};

ok !$@, 'table name with . parsed correctly';
diag $@ if $@;

#system qq{$^X -pi -e 's/"test\.dot"/\\\\"[test.dot]"/' t/_common_dump/TestSL/Schema/Result/TestDot.pm};
#diag do { local ($/, @ARGV) = (undef, "t/_common_dump/TestSL/Schema/Result/TestDot.pm"); <> };
#do "t/_common_dump/TestSL/Schema/Result/TestDot.pm";

eval 'use TestSL::Schema';
ok !$@, 'loaded schema';
diag $@ if $@;

TODO: {
    local $TODO = q{this is really a DBIC test to check if the table is usable,
and it doesn't work in the released version yet};

    eval {
        my $rs = TestSL::Schema->resultset('TestDot');
        my $row = $rs->create({ dat => 'foo' });
        $row->update({ dat => 'bar' });
        $row = $rs->find($row->id);
        $row->delete;
    };
    ok !$@, 'used table from DBIC succeessfully';
    diag $@ if $@;
}

rmtree $DUMP_DIR;

$dbh->do('DROP TABLE [test.dot]');
