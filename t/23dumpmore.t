use warnings;
use strict;

use File::Temp ();
use Test::More;

use lib qw(t/lib);
use dbixcsl_dumper_tests;
my $t = 'dbixcsl_dumper_tests';

$t->cleanup;

# test loading external content
$t->dump_test(
  classname => 'DBICTest::Schema::_no_skip_load_external',
  warnings => [
    qr/Dumping manual schema for DBICTest::Schema::_no_skip_load_external to directory /,
    qr/Schema dump completed/,
  ],
  regexes => {
    Foo => [
      qr/package DBICTest::Schema::_no_skip_load_external::Foo;\nour \$skip_me = "bad mojo";\n1;/
    ],
  },
);

# test skipping external content
$t->dump_test(
  classname => 'DBICTest::Schema::_skip_load_external',
  options => {
    skip_load_external => 1
  },
  warnings => [
    qr/Dumping manual schema for DBICTest::Schema::_skip_load_external to directory /,
    qr/Schema dump completed/,
  ],
  neg_regexes => {
    Foo => [
      qr/package DBICTest::Schema::_skip_load_external::Foo;\nour \$skip_me = "bad mojo";\n1;/
    ],
  },
);

$t->cleanup;
# test config_file
{
  my $config_file = File::Temp->new (UNLINK => 1);

  print $config_file "{ skip_relationships => 1 }\n";
  close $config_file;

  $t->dump_test(
    classname => 'DBICTest::Schema::_config_file',
    options => { config_file => "$config_file" },
    warnings => [
      qr/Dumping manual schema for DBICTest::Schema::_config_file to directory /,
      qr/Schema dump completed/,
    ],
    neg_regexes => {
      Foo => [
        qr/has_many/,
      ],
    },
  );
}

# proper exception
$t->dump_test(
  classname => 'DBICTest::Schema::_clashing_monikers',
  test_db_class => 'make_dbictest_db_clashing_monikers',
  error => qr/tables 'bar', 'bars' reduced to the same source moniker 'Bar'/,
);


$t->cleanup;

# test out the POD
$t->dump_test(
  classname => 'DBICTest::DumpMore::1',
  options => {
    custom_column_info => sub {
      my ($table, $col, $info) = @_;
      return +{ extra => { is_footext => 1 } } if $col eq 'footext';
    }
  },
  warnings => [
    qr/Dumping manual schema for DBICTest::DumpMore::1 to directory /,
    qr/Schema dump completed/,
  ],
  regexes => {
    schema => [
      qr/package DBICTest::DumpMore::1;/,
      qr/->load_classes/,
    ],
    Foo => [
      qr/package DBICTest::DumpMore::1::Foo;/,
      qr/=head1 NAME\n\nDBICTest::DumpMore::1::Foo\n\n=cut\n\n/,
      qr/=head1 ACCESSORS\n\n/,
      qr/=head2 fooid\n\n  data_type: 'integer'\n  is_auto_increment: 1\n  is_nullable: 0\n\n/,
      qr/=head2 footext\n\n  data_type: 'text'\n  default_value: 'footext'\n  extra: {is_footext => 1}\n  is_nullable: 1\n\n/,
      qr/->set_primary_key/,
      qr/=head1 RELATIONS\n\n/,
      qr/=head2 bars\n\nType: has_many\n\nRelated object: L<DBICTest::DumpMore::1::Bar>\n\n=cut\n\n/,
      qr/1;\n$/,
    ],
    Bar => [
      qr/package DBICTest::DumpMore::1::Bar;/,
      qr/=head1 NAME\n\nDBICTest::DumpMore::1::Bar\n\n=cut\n\n/,
      qr/=head1 ACCESSORS\n\n/,
      qr/=head2 barid\n\n  data_type: 'integer'\n  is_auto_increment: 1\n  is_nullable: 0\n\n/,
      qr/=head2 fooref\n\n  data_type: 'integer'\n  is_foreign_key: 1\n  is_nullable: 1\n\n/,
      qr/->set_primary_key/,
      qr/=head1 RELATIONS\n\n/,
      qr/=head2 fooref\n\nType: belongs_to\n\nRelated object: L<DBICTest::DumpMore::1::Foo>\n\n=cut\n\n/,
      qr/1;\n$/,
    ],
  },
);


$t->append_to_class('DBICTest::DumpMore::1::Foo',q{# XXX This is my custom content XXX});


$t->dump_test(
  classname => 'DBICTest::DumpMore::1',
  warnings => [
    qr/Dumping manual schema for DBICTest::DumpMore::1 to directory /,
    qr/Schema dump completed/,
  ],
  regexes => {
    schema => [
      qr/package DBICTest::DumpMore::1;/,
      qr/->load_classes/,
    ],
    Foo => [
      qr/package DBICTest::DumpMore::1::Foo;/,
      qr/->set_primary_key/,
      qr/1;\n# XXX This is my custom content XXX/,
    ],
    Bar => [
      qr/package DBICTest::DumpMore::1::Bar;/,
      qr/->set_primary_key/,
      qr/1;\n$/,
    ],
  },
);


$t->dump_test(
  classname => 'DBICTest::DumpMore::1',
  options => {
    really_erase_my_files => 1 
  },
  warnings => [
    qr/Dumping manual schema for DBICTest::DumpMore::1 to directory /,
    qr/Deleting existing file /,
    qr/Deleting existing file /,
    qr/Deleting existing file /,
    qr/Schema dump completed/,
  ],
  regexes => {
    schema => [
      qr/package DBICTest::DumpMore::1;/,
      qr/->load_classes/,
    ],
    Foo => [
      qr/package DBICTest::DumpMore::1::Foo;/,
      qr/->set_primary_key/,
      qr/1;\n$/,
    ],
    Bar => [
      qr/package DBICTest::DumpMore::1::Bar;/,
      qr/->set_primary_key/,
      qr/1;\n$/,
    ],
  },
  neg_regexes => {
    Foo => [
      qr/# XXX This is my custom content XXX/,
    ],
  },
);


$t->cleanup;

# test namespaces
$t->dump_test(
  classname => 'DBICTest::DumpMore::1',
  options => {
    use_namespaces => 1,
    generate_pod => 0
  },
  warnings => [
    qr/Dumping manual schema for DBICTest::DumpMore::1 to directory /,
    qr/Schema dump completed/,
  ],
  neg_regexes => {
    'Result/Foo' => [
      qr/^=/m,
    ],
  },
);


$t->dump_test(
  classname => 'DBICTest::DumpMore::1',
  options => {
    db_schema => 'foo_schema',
    qualify_objects => 1,
    use_namespaces => 1
  },
  warnings => [
    qr/Dumping manual schema for DBICTest::DumpMore::1 to directory /,
    qr/Schema dump completed/,
  ],
  regexes => {
    'Result/Foo' => [
      qr/^\Q__PACKAGE__->table("foo_schema.foo");\E/m,
      # the has_many relname should not have the schema in it!
      qr/^__PACKAGE__->has_many\(\n  "bars"/m,
    ],
  },
);

$t->dump_test(
  classname => 'DBICTest::DumpMore::1',
  options => {
    use_namespaces => 1
  },
  warnings => [
    qr/Dumping manual schema for DBICTest::DumpMore::1 to directory /,
    qr/Schema dump completed/,
  ],
  regexes => {
    schema => [
      qr/package DBICTest::DumpMore::1;/,
      qr/->load_namespaces/,
    ],
    'Result/Foo' => [
      qr/package DBICTest::DumpMore::1::Result::Foo;/,
      qr/->set_primary_key/,
      qr/1;\n$/,
    ],
    'Result/Bar' => [
      qr/package DBICTest::DumpMore::1::Result::Bar;/,
      qr/->set_primary_key/,
      qr/1;\n$/,
    ],
  },
);


$t->dump_test(
  classname => 'DBICTest::DumpMore::1',
  options => {
    use_namespaces => 1,
    result_namespace => 'Res',
    resultset_namespace => 'RSet',
    default_resultset_class => 'RSetBase',
  },
  warnings => [
    qr/Dumping manual schema for DBICTest::DumpMore::1 to directory /,
    qr/Schema dump completed/,
  ],
  regexes => {
    schema => [
      qr/package DBICTest::DumpMore::1;/,
      qr/->load_namespaces/,
      qr/result_namespace => 'Res'/,
      qr/resultset_namespace => 'RSet'/,
      qr/default_resultset_class => 'RSetBase'/,
    ],
    'Res/Foo' => [
      qr/package DBICTest::DumpMore::1::Res::Foo;/,
      qr/->set_primary_key/,
      qr/1;\n$/,
    ],
    'Res/Bar' => [
      qr/package DBICTest::DumpMore::1::Res::Bar;/,
      qr/->set_primary_key/,
      qr/1;\n$/,
    ],
  },
);


$t->dump_test(
  classname => 'DBICTest::DumpMore::1',
  options => {
    use_namespaces => 1,
    result_namespace => '+DBICTest::DumpMore::1::Res',
    resultset_namespace => 'RSet',
    default_resultset_class => 'RSetBase',
    result_base_class => 'My::ResultBaseClass',
    schema_base_class => 'My::SchemaBaseClass',
  },
  warnings => [
    qr/Dumping manual schema for DBICTest::DumpMore::1 to directory /,
    qr/Schema dump completed/,
  ],
  regexes => {
    schema => [
      qr/package DBICTest::DumpMore::1;/,
      qr/->load_namespaces/,
      qr/result_namespace => '\+DBICTest::DumpMore::1::Res'/,
      qr/resultset_namespace => 'RSet'/,
      qr/default_resultset_class => 'RSetBase'/,
      qr/use base 'My::SchemaBaseClass'/,
    ],
    'Res/Foo' => [
      qr/package DBICTest::DumpMore::1::Res::Foo;/,
      qr/use base 'My::ResultBaseClass'/,
      qr/->set_primary_key/,
      qr/1;\n$/,
    ],
    'Res/Bar' => [
      qr/package DBICTest::DumpMore::1::Res::Bar;/,
      qr/use base 'My::ResultBaseClass'/,
      qr/->set_primary_key/,
      qr/1;\n$/,
    ],
  },
);


$t->dump_test(
  classname => 'DBICTest::DumpMore::1',
  options => {
    use_namespaces    => 1,
    result_base_class => 'My::MissingResultBaseClass',
  },
  error => qr/My::MissingResultBaseClass.*is not installed/,
);

done_testing;
