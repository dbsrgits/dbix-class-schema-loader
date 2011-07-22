use strict;
use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use File::Slurp qw(slurp);
use File::Path;
use make_dbictest_db;
use dbixcsl_test_dir qw/$tdir/;

my $dump_path = "$tdir/dump";

{
    package DBICTest::Schema::1;
    use base qw/ DBIx::Class::Schema::Loader /;
    __PACKAGE__->loader_options(
        dump_directory => $dump_path,
    );
}

DBICTest::Schema::1->connect($make_dbictest_db::dsn);

plan tests => 1;

my $foo = slurp("$dump_path/DBICTest/Schema/1/Result/Foo.pm");
my $bar = slurp("$dump_path/DBICTest/Schema/1/Result/Bar.pm");

like($foo, qr/Result::Foo\n/, 'No error from no comments');

END { rmtree($dump_path, 1, 1); }
