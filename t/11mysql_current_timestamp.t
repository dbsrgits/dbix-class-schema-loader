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
use Test::Exception;

my ($dsn, $user, $password) = map $ENV{"DBICTEST_MYSQL_$_"}, qw/DSN USER PASS/;

if( !$dsn || !$user ) {
    plan skip_all => 'You need to set the DBICTEST_MYSQL_DSN, _USER, and _PASS'
                     .' environment variables';
}

eval "use SQL::Translator '0.09007';";
plan skip_all => 'SQL::Translator 0.09007 or greater required'
    if $@;

plan tests => 2;

my $dbh = DBI->connect($dsn, $user, $password, {
    RaiseError => 1, PrintError => 0
});

eval { $dbh->do('DROP TABLE loadertest') };
$dbh->do(q{
    CREATE TABLE loadertest (
      id INT PRIMARY KEY,
      somedate TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      somestr VARCHAR(100) NOT NULL DEFAULT 'foo'
    ) Engine=InnoDB
});
# XXX there needs to be code to distinguish these two types of defaults

rmtree $DUMP_DIR;

make_schema_at(
    'TestSL::Schema', 
    {
        use_namespaces => 1,
        constraint => qr/^loadertest\z/
    },
    [ $dsn, $user, $password, ]
);

lives_ok { require TestSL::Schema } 'schema loads';

$dbh->do('DROP TABLE loadertest');

my $schema = TestSL::Schema->connect($dsn, $user, $password);

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, shift };

$schema->deploy;

ok (not(grep /Invalid default/, @warnings)), 'default deployed';
diag $_ for @warnings;

END {
    rmtree $DUMP_DIR;
    eval { $dbh->do('DROP TABLE loadertest') };
}
