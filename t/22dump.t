use strict;
use Test::More;
use lib qw(t/lib);
use File::Path;
use make_dbictest_db;

my $dump_path = './t/_dump';

{
    package DBICTest::Schema::1;
    use base qw/ DBIx::Class::Schema::Loader /;
    __PACKAGE__->loader_options(
        relationships => 1,
        dump_directory => $dump_path,
    );
}

{
    package DBICTest::Schema::2;
    use base qw/ DBIx::Class::Schema::Loader /;
    __PACKAGE__->loader_options(
        relationships => 1,
        dump_directory => $dump_path,
        dump_overwrite => 1,
    );
}

plan tests => 4;

rmtree($dump_path, 1, 0711);

eval { DBICTest::Schema::1->connect($make_dbictest_db::dsn) };
ok(!$@, 'no death with dump_directory set') or diag "Dump failed: $@";

DBICTest::Schema::1->loader(undef);
eval { DBICTest::Schema::1->connect($make_dbictest_db::dsn) };
like($@, qr|DBICTest/Schema/1.pm exists, will not overwrite|,
    'death when attempting to overwrite without option');

rmtree($dump_path, 1, 0711);

eval { DBICTest::Schema::2->connect($make_dbictest_db::dsn) };
ok(!$@, 'no death with dump_directory set (overwrite1)') or diag "Dump failed: $@";

DBICTest::Schema::2->loader(undef);
eval { DBICTest::Schema::2->connect($make_dbictest_db::dsn) };
ok(!$@, 'no death with dump_directory set (overwrite2)') or diag "Dump failed: $@";

END { rmtree($dump_path, 1, 0711); }
