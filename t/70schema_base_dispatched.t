use strict;
use warnings;
no warnings 'once';
use Test::More tests => 2;
use DBIx::Class::Schema::Loader 'make_schema_at';
use lib 't/lib';
use make_dbictest_db;

make_schema_at(
    'DBICTest::Schema::_test_schema_base',
    {
	naming => 'current',
	schema_base_class => 'TestSchemaBaseClass',
        schema_components => ['TestSchemaComponent'],
    },
    [ $make_dbictest_db::dsn ],
);

ok $TestSchemaBaseClass::test_ok,
    'connected using schema_base_class';

ok $DBIx::Class::TestSchemaComponent::test_component_ok,
    'connected using schema_components';
