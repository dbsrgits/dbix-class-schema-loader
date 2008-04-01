use strict;
use warnings;
use Test::More;
use lib qw(t/lib);
use make_dbictest_db;

{
    package DBICTest::Schema;
    use base qw/ DBIx::Class::Schema::Loader /;
    __PACKAGE__->loader_options( loader_class => 'TestLoaderSubclass' );
}

plan tests => 2;

my $schema = DBICTest::Schema->connect($make_dbictest_db::dsn);
isa_ok($schema->storage, 'DBIx::Class::Storage::DBI::SQLite');
isa_ok($schema->_loader, 'TestLoaderSubclass');
