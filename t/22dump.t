use strict;
use Test::More;
use lib qw(t/lib);
use make_dbictest_db;

{
    package DBICTest::Schema;
    use base qw/ DBIx::Class::Schema::Loader /;
    __PACKAGE__->loader_options(
        relationships => 1,
        dump_directory => './t/_dump',
        dump_overwrite => 1,
    );
    
}

plan tests => 1;

eval { DBICTest::Schema->connect($make_dbictest_db::dsn) };
ok(!$@, 'no death with dump_directory set')
    or diag "Dump failed: $@";
