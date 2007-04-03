use strict;
use Test::More;
use lib qw(t/lib);
use File::Path;
use make_dbictest_db;
require DBIx::Class::Schema::Loader;

plan tests => 5;

plan skip_all => "ActiveState perl produces additional warnings"
    if ($^O eq 'MSWin32');

my $dump_path = './t/_dump';

sub do_dump_test {
    my ($schema_class, $opts) = @_;

    rmtree($dump_path, 1, 1);

    no strict 'refs';
    @{$schema_class . '::ISA'} = ('DBIx::Class::Schema::Loader');
    $schema_class->loader_options(dump_directory => $dump_path, %$opts);

    my @warn_output;
    eval {
        local $SIG{__WARN__} = sub { push(@warn_output, @_) };
        $schema_class->connect($make_dbictest_db::dsn);
    };
    my $err = $@;
    $schema_class->storage->disconnect if !$err && $schema_class->storage;
    undef *{$schema_class};
    return ($err, \@warn_output);
}


{
    my ($err, $warn) = do_dump_test('DBICTest::Schema::1', { });
    ok(!$err);
    is(@$warn, 2);
    like($warn->[0], qr/Dumping manual schema for DBICTest::Schema::1 to directory /);
    like($warn->[1], qr/Schema dump completed/);
}

ok(1);

# XXX obviously this test file needs to be fleshed out more :)

# END { rmtree($dump_path, 1, 1); }
