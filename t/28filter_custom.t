use strict;
use warnings;
use DBIx::Class::Schema::Loader;
use DBIx::Class::Schema::Loader::Utils 'slurp_file';
use File::Path;
use Test::More tests => 19;
use Test::Exception;
use lib qw(t/lib);
use make_dbictest_db;
use dbixcsl_test_dir qw/$tdir/;

my $dump_path = "$tdir/dump";

my %original_class_data;

my ($schema_file_count, $result_file_count);

{
    package DBICTest::Schema::1;
    use Test::More;
    use base 'DBIx::Class::Schema::Loader';
    __PACKAGE__->loader_options(
        dump_directory => $dump_path,
        quiet => 1,
        filter_custom_content => sub{
            my ($type, $class, $text) = @_;
            like $type, qr/^(?:schema|result)\z/,
                'got correct file type';

            if ($type eq 'schema') {
                $schema_file_count++;
                is $class, 'DBICTest::Schema::1',
                    'correct class for schema type file passed to filter';
            }
            elsif ($type eq 'result') {
                $result_file_count++;
                like $class, qr/^DBICTest::Schema::1::Result::(?:Foo|Bar)\z/,
#                    'correct class for result type file passed to filter';
            }
            else {
                die 'invalid file type passed to filter';
            }

            unless( $text =~ /sub foo/ ){
                $text =~ s/1;\n/sub foo{ "x" }\n1;/;
            }

            return $text;
        },
    );
}

{
    package DBICTest::Schema::2;
    use base 'DBIx::Class::Schema::Loader';
    __PACKAGE__->loader_options(
        dump_directory => $dump_path,
        quiet => 1,
        filter_custom_content => "$^X t/bin/simple_filter",
    );
}



DBICTest::Schema::1->connect($make_dbictest_db::dsn);

# schema is generated in 2 passes

is $schema_file_count, 2,
    'correct number of schema files passed to filter';

is $result_file_count, 4,
    'correct number of result files passed to filter';
my $foo = slurp_file "$dump_path/DBICTest/Schema/1/Result/Foo.pm";
like $foo, qr/package DBICTest::Schema::1::Result::Foo/, 'package statement intact';
like $foo, qr/# Created by DBIx::Class::Schema::Loader/, 'end of generated comment seems to be there';
like $foo, qr/# You can replace this text/, 'Comment in the custom text shows we haven\'t eradicated it';
like $foo, qr/sub foo{ "x" }/, 'Can insert a sub';

DBICTest::Schema::2->connect($make_dbictest_db::dsn);

$foo = slurp_file "$dump_path/DBICTest/Schema/2/Result/Foo.pm";

like $foo, qr/Kilroy was here/,
    "Can insert text via command filter";

