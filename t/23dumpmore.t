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

# test naming => { column_accessors => 'preserve' }
# also test POD for unique constraint
$t->dump_test(
    classname => 'DBICTest::Schema::_preserve_column_accessors',
    test_db_class => 'make_dbictest_db_with_unique',
    options => { naming => { column_accessors => 'preserve' } },
    warnings => [
        qr/Dumping manual schema for DBICTest::Schema::_preserve_column_accessors to directory /,
        qr/Schema dump completed/,
    ],
    neg_regexes => {
        RouteChange => [
            qr/\baccessor\b/,
        ],
    },
    regexes => {
        Baz => [
            qr/\n\n=head1 UNIQUE CONSTRAINTS\n\n=head2 C<baz_num_unique>\n\n=over 4\n\n=item \* L<\/baz_num>\n\n=back\n\n=cut\n\n__PACKAGE__->add_unique_constraint\("baz_num_unique"\, \["baz_num"\]\);\n\n/,
        ],
    }
);

$t->cleanup;

# test that rels are sorted
$t->dump_test(
    classname => 'DBICTest::Schema::_sorted_rels',
    test_db_class => 'make_dbictest_db_with_unique',
    warnings => [
        qr/Dumping manual schema for DBICTest::Schema::_sorted_rels to directory /,
        qr/Schema dump completed/,
    ],
    regexes => {
        Baz => [
            qr/->might_have\(\n  "quux".*->belongs_to\(\n  "station_visited"/s,
        ],
    }
);

$t->cleanup;

# test naming => { monikers => 'plural' }
$t->dump_test(
    classname => 'DBICTest::Schema::_plural_monikers',
    options => { naming => { monikers => 'plural' } },
    warnings => [
        qr/Dumping manual schema for DBICTest::Schema::_plural_monikers to directory /,
        qr/Schema dump completed/,
    ],
    regexes => {
        Foos => [
            qr/\n=head1 NAME\n\nDBICTest::Schema::_plural_monikers::Foos\n\n=cut\n\n/,
        ],
        Bars => [
            qr/\n=head1 NAME\n\nDBICTest::Schema::_plural_monikers::Bars\n\n=cut\n\n/,
        ],
    },
);

$t->cleanup;

# test naming => { monikers => 'singular' }
$t->dump_test(
    classname => 'DBICTest::Schema::_singular_monikers',
    test_db_class => 'make_dbictest_db_plural_tables',
    options => { naming => { monikers => 'singular' } },
    warnings => [
        qr/Dumping manual schema for DBICTest::Schema::_singular_monikers to directory /,
        qr/Schema dump completed/,
    ],
    regexes => {
        Foo => [
            qr/\n=head1 NAME\n\nDBICTest::Schema::_singular_monikers::Foo\n\n=cut\n\n/,
        ],
        Bar => [
            qr/\n=head1 NAME\n\nDBICTest::Schema::_singular_monikers::Bar\n\n=cut\n\n/,
        ],
    },
);

$t->cleanup;

# test naming => { monikers => 'preserve' }
$t->dump_test(
    classname => 'DBICTest::Schema::_preserve_monikers',
    test_db_class => 'make_dbictest_db_plural_tables',
    options => { naming => { monikers => 'preserve' } },
    warnings => [
        qr/Dumping manual schema for DBICTest::Schema::_preserve_monikers to directory /,
        qr/Schema dump completed/,
    ],
    regexes => {
        Foos => [
            qr/\n=head1 NAME\n\nDBICTest::Schema::_preserve_monikers::Foos\n\n=cut\n\n/,
        ],
        Bars => [
            qr/\n=head1 NAME\n\nDBICTest::Schema::_preserve_monikers::Bars\n\n=cut\n\n/,
        ],
    },
);

$t->cleanup;

# test out the POD
$t->dump_test(
  classname => 'DBICTest::DumpMore::1',
  options => {
    custom_column_info => sub {
      my ($table, $col, $info) = @_;
      return +{ extra => { is_footext => 1 } } if $col eq 'footext';
    },
    result_base_class => 'My::ResultBaseClass',
    additional_classes => 'TestAdditional',
    additional_base_classes => 'TestAdditionalBase',
    left_base_classes => 'TestLeftBase',
    components => [ 'TestComponent', '+TestComponentFQN' ],
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
      qr/\n=head1 NAME\n\nDBICTest::DumpMore::1::Foo\n\n=cut\n\nuse strict;\nuse warnings;\n\n/,
      qr/\n=head1 BASE CLASS: L<My::ResultBaseClass>\n\n=cut\n\nuse base 'My::ResultBaseClass';\n\n/,
      qr/\n=head1 ADDITIONAL CLASSES USED\n\n=over 4\n\n=item \* L<TestAdditional>\n\n=back\n\n=cut\n\n/,
      qr/\n=head1 ADDITIONAL BASE CLASSES\n\n=over 4\n\n=item \* L<TestAdditionalBase>\n\n=back\n\n=cut\n\n/,
      qr/\n=head1 LEFT BASE CLASSES\n\n=over 4\n\n=item \* L<TestLeftBase>\n\n=back\n\n=cut\n\n/,
      qr/\n=head1 COMPONENTS LOADED\n\n=over 4\n\n=item \* L<DBIx::Class::TestComponent>\n\n=item \* L<TestComponentFQN>\n\n=back\n\n=cut\n\n/,
      qr/\n=head1 TABLE: C<foo>\n\n=cut\n\n__PACKAGE__->table\("foo"\);\n\n/,
      qr/\n=head1 ACCESSORS\n\n/,
      qr/\n=head2 fooid\n\n  data_type: 'integer'\n  is_auto_increment: 1\n  is_nullable: 0\n\n/,
      qr/\n=head2 footext\n\n  data_type: 'text'\n  default_value: 'footext'\n  extra: {is_footext => 1}\n  is_nullable: 1\n\n/,
      qr/\n=head1 PRIMARY KEY\n\n=over 4\n\n=item \* L<\/fooid>\n\n=back\n\n=cut\n\n__PACKAGE__->set_primary_key\("fooid"\);\n/,
      qr/\n=head1 RELATIONS\n\n/,
      qr/\n=head2 bars\n\nType: has_many\n\nRelated object: L<DBICTest::DumpMore::1::Bar>\n\n=cut\n\n/,
      qr/1;\n$/,
    ],
    Bar => [
      qr/package DBICTest::DumpMore::1::Bar;/,
      qr/\n=head1 NAME\n\nDBICTest::DumpMore::1::Bar\n\n=cut\n\nuse strict;\nuse warnings;\n\n/,
      qr/\n=head1 BASE CLASS: L<My::ResultBaseClass>\n\n=cut\n\nuse base 'My::ResultBaseClass';\n\n/,
      qr/\n=head1 ADDITIONAL CLASSES USED\n\n=over 4\n\n=item \* L<TestAdditional>\n\n=back\n\n=cut\n\n/,
      qr/\n=head1 ADDITIONAL BASE CLASSES\n\n=over 4\n\n=item \* L<TestAdditionalBase>\n\n=back\n\n=cut\n\n/,
      qr/\n=head1 LEFT BASE CLASSES\n\n=over 4\n\n=item \* L<TestLeftBase>\n\n=back\n\n=cut\n\n/,
      qr/\n=head1 COMPONENTS LOADED\n\n=over 4\n\n=item \* L<DBIx::Class::TestComponent>\n\n=item \* L<TestComponentFQN>\n\n=back\n\n=cut\n\n/,
      qr/\n=head1 TABLE: C<bar>\n\n=cut\n\n__PACKAGE__->table\("bar"\);\n\n/,
      qr/\n=head1 ACCESSORS\n\n/,
      qr/\n=head2 barid\n\n  data_type: 'integer'\n  is_auto_increment: 1\n  is_nullable: 0\n\n/,
      qr/\n=head2 fooref\n\n  data_type: 'integer'\n  is_foreign_key: 1\n  is_nullable: 1\n\n/,
      qr/\n=head1 PRIMARY KEY\n\n=over 4\n\n=item \* L<\/barid>\n\n=back\n\n=cut\n\n__PACKAGE__->set_primary_key\("barid"\);\n/,
      qr/\n=head1 RELATIONS\n\n/,
      qr/\n=head2 fooref\n\nType: belongs_to\n\nRelated object: L<DBICTest::DumpMore::1::Foo>\n\n=cut\n\n/,
      qr/\n1;\n$/,
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
      qr/result_namespace => "Res"/,
      qr/resultset_namespace => "RSet"/,
      qr/default_resultset_class => "RSetBase"/,
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
      qr/result_namespace => "\+DBICTest::DumpMore::1::Res"/,
      qr/resultset_namespace => "RSet"/,
      qr/default_resultset_class => "RSetBase"/,
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

# test quote_char in connect_info for dbicdump
$t->dump_test(
  classname => 'DBICTest::DumpMore::1',
  extra_connect_info => [
    '',
    '',
    { quote_char => '"' },
  ],
  warnings => [
    qr/Dumping manual schema for DBICTest::DumpMore::1 to directory /,
    qr/Schema dump completed/,
  ],
);

done_testing;
# vim:et sts=4 sw=4 tw=0:
