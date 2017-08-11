use DBIx::Class::Schema::Loader::Optional::Dependencies
    -skip_all_without => 'use_moo';

use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use dbixcsl_dumper_tests;
my $t = 'dbixcsl_dumper_tests';

$t->cleanup;

# first dump a fresh use_moo=1 schema
$t->dump_test(
    classname => 'DBICTest::DumpMore::1',
    options => {
        use_moo => 1,
        result_base_class => 'My::ResultBaseClass',
        schema_base_class => 'My::SchemaBaseClass',
        result_roles => ['TestRole', 'TestRole2'],
    },
    regexes => {
        schema => [
            qr/\nuse Moo;\nuse namespace::autoclean;\nextends 'My::SchemaBaseClass';\n\n/,
        ],
        Foo => [
            qr/\nuse Moo;\nuse namespace::autoclean;\nextends 'My::ResultBaseClass';\n\n/,
            qr/=head1 L<Moo> ROLES APPLIED\n\n=over 4\n\n=item \* L<TestRole>\n\n=item \* L<TestRole2>\n\n=back\n\n=cut\n\n/,
            qr/\nwith 'TestRole', 'TestRole2';\n\n/,
        ],
        Bar => [
            qr/\nuse Moo;\nuse namespace::autoclean;\nextends 'My::ResultBaseClass';\n\n/,
            qr/=head1 L<Moo> ROLES APPLIED\n\n=over 4\n\n=item \* L<TestRole>\n\n=item \* L<TestRole2>\n\n=back\n\n=cut\n\n/,
            qr/\nwith 'TestRole', 'TestRole2';\n\n/,
        ],
    },
);

$t->cleanup;

# now upgrade a fresh non-moo schema to use_moo=1
$t->dump_test(
    classname => 'DBICTest::DumpMore::1',
    options => {
        use_moo => 0,
        result_base_class => 'My::ResultBaseClass',
        schema_base_class => 'My::SchemaBaseClass',
    },
    regexes => {
        schema => [
            qr/\nuse base 'My::SchemaBaseClass';\n/,
        ],
        Foo => [
            qr/\nuse base 'My::ResultBaseClass';\n/,
        ],
        Bar => [
            qr/\nuse base 'My::ResultBaseClass';\n/,
        ],
    },
);

# check that changed custom content is upgraded for Moo bits
$t->append_to_class('DBICTest::DumpMore::1::Foo', q{# XXX This is my custom content XXX});

$t->dump_test(
    classname => 'DBICTest::DumpMore::1',
    options => {
        use_moo => 1,
        result_base_class => 'My::ResultBaseClass',
        schema_base_class => 'My::SchemaBaseClass',
    },
    regexes => {
        schema => [
            qr/\nuse Moo;\nuse namespace::autoclean;\nextends 'My::SchemaBaseClass';\n\n/,
        ],
        Foo => [
            qr/\nuse Moo;\nuse namespace::autoclean;\nextends 'My::ResultBaseClass';\n\n/,
            qr/# XXX This is my custom content XXX/,
        ],
        Bar => [
            qr/\nuse Moo;\nuse namespace::autoclean;\nextends 'My::ResultBaseClass';\n\n/,
        ],
    },
);

done_testing();

