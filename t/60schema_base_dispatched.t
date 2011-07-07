# test that the class in schema_base_class gets used when loading the schema
# by Ben Tilly (  btilly -at|   gmail.com )

use strict;
use Test::More tests => 1;
use DBIx::Class::Schema::Loader qw(make_schema_at);
use lib 't/lib';
use make_dbictest_db;

make_schema_at(
    'DBICTest::Schema::_test_schema_base',
    {
        really_erase_my_files => 1,
	naming => 'current',
	use_namespaces => 0,
	schema_base_class => 'TestSchemaBaseClass',
    },
    [ $make_dbictest_db::dsn ],
);

ok($TestSchemaBaseClass::test_ok, "Connected using schema_base_class.");
