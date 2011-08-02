use strict;
use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use File::Slurp qw(slurp);
use File::Path;
use make_dbictest_db_bad_comment_tables;
use dbixcsl_test_dir qw/$tdir/;
use Try::Tiny;

my $dump_path = "$tdir/dump";

{
    package DBICTest::Schema::1;
    use base qw/ DBIx::Class::Schema::Loader /;
    __PACKAGE__->loader_options(
        dump_directory => $dump_path,
    );
}

try {
    DBICTest::Schema::1->connect($make_dbictest_db_bad_comment_tables::dsn);
};

plan tests => 1;

my $foo = try { slurp("$dump_path/DBICTest/Schema/1/Result/Foo.pm") };
my $bar = try { slurp("$dump_path/DBICTest/Schema/1/Result/Bar.pm") };

like($foo, qr/Result::Foo\n/, 'No error from invalid comment tables');

END { rmtree($dump_path, 1, 1); }
