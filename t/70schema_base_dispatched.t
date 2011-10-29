use strict;
use warnings;
use Test::More tests => 8;
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

# try an explicit dynamic schema

$TestSchemaBaseClass::test_ok = 0;
$DBIx::Class::TestSchemaComponent::test_component_ok = 0;

{
    package DBICTest::Schema::_test_schema_base_dynamic;
    use base 'DBIx::Class::Schema::Loader';
    __PACKAGE__->loader_options({
        naming => 'current',
        schema_base_class => 'TestSchemaBaseClass',
        schema_components => ['TestSchemaComponent'],
    });
    # check that connection doesn't cause an infinite loop
    sub connection { my $self = shift; return $self->next::method(@_) }
}

ok(my $schema =
    DBICTest::Schema::_test_schema_base_dynamic->connect($make_dbictest_db::dsn),
    'connected dynamic schema');

ok $TestSchemaBaseClass::test_ok,
    'connected using schema_base_class in dynamic schema';

ok $DBIx::Class::TestSchemaComponent::test_component_ok,
    'connected using schema_components in dynamic schema';

# connect a second time

$TestSchemaBaseClass::test_ok = 0;
$DBIx::Class::TestSchemaComponent::test_component_ok = 0;

ok($schema =
    DBICTest::Schema::_test_schema_base_dynamic->connect($make_dbictest_db::dsn),
    'connected dynamic schema a second time');

ok $TestSchemaBaseClass::test_ok,
    'connected using schema_base_class in dynamic schema a second time';

ok $DBIx::Class::TestSchemaComponent::test_component_ok,
    'connected using schema_components in dynamic schema a second time';
