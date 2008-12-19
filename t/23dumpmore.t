use strict;
use Test::More;
use lib qw(t/lib);
use File::Path;
use make_dbictest_db;
require DBIx::Class::Schema::Loader;

$^O eq 'MSWin32'
    ? plan(skip_all => "ActiveState perl produces additional warnings, and this test uses unix paths")
    : plan(tests => 91);

my $DUMP_PATH = './t/_dump';

sub do_dump_test {
    my %tdata = @_;

    my $schema_class = $tdata{classname};

    no strict 'refs';
    @{$schema_class . '::ISA'} = ('DBIx::Class::Schema::Loader');
    $schema_class->loader_options(dump_directory => $DUMP_PATH, %{$tdata{options}});

    my @warns;
    eval {
        local $SIG{__WARN__} = sub { push(@warns, @_) };
        $schema_class->connect($make_dbictest_db::dsn);
    };
    my $err = $@;
    $schema_class->storage->disconnect if !$err && $schema_class->storage;
    undef *{$schema_class};

    is($err, $tdata{error});

    my $check_warns = $tdata{warnings};
    is(@warns, @$check_warns);
    for(my $i = 0; $i <= $#$check_warns; $i++) {
        like($warns[$i], $check_warns->[$i]);
    }

    my $file_regexes = $tdata{regexes};
    my $file_neg_regexes = $tdata{neg_regexes} || {};
    my $schema_regexes = delete $file_regexes->{schema};
    
    my $schema_path = $DUMP_PATH . '/' . $schema_class;
    $schema_path =~ s{::}{/}g;
    dump_file_like($schema_path . '.pm', @$schema_regexes);
    foreach my $src (keys %$file_regexes) {
        my $src_file = $schema_path . '/' . $src . '.pm';
        dump_file_like($src_file, @{$file_regexes->{$src}});
    }
    foreach my $src (keys %$file_neg_regexes) {
        my $src_file = $schema_path . '/' . $src . '.pm';
        dump_file_not_like($src_file, @{$file_neg_regexes->{$src}});
    }

    my $current_md5sums = {}; # keep track of the md5sums we make so we can return them.
    my $file_md5sum_equals = $tdata{md5sum_equals} || {};
    foreach my $src (keys %$file_md5sum_equals) {
        my $src_file;
        if ($src eq 'schema' ) {
            $src_file = $schema_path . '.pm';
        } else {
            $src_file = $schema_path . '/' . $src . '.pm';
        }
        my $current_md5sum = get_md5sum_from_dump_file($src_file);
        is( $current_md5sum, $file_md5sum_equals->{$src}, "found the same md5sum ($current_md5sum) for file $src_file" );
        $current_md5sums->{$src} = $current_md5sum;
    }

    my $file_md5sum_ne = $tdata{md5sum_ne} || {};
    foreach my $src (keys %$file_md5sum_ne) {
        my $src_file;
        if ($src eq 'schema' ) {
            $src_file = $schema_path . '.pm';
        } else {
            $src_file = $schema_path . '/' . $src . '.pm';
        }
        my $current_md5sum = get_md5sum_from_dump_file($src_file);
        isnt( $current_md5sum, $file_md5sum_equals->{$src}, "found different md5sum ($current_md5sum) for file $src_file" );
        $current_md5sums->{$src} = $current_md5sum;
    }
    return { md5sums => $current_md5sums };
}

sub dump_file_like {
    my $path = shift;
    open(my $dumpfh, '<', $path) or die "Failed to open '$path': $!";
    my $contents = do { local $/; <$dumpfh>; };
    close($dumpfh);
    like($contents, $_) for @_;
}

sub dump_file_not_like {
    my $path = shift;
    open(my $dumpfh, '<', $path) or die "Failed to open '$path': $!";
    my $contents = do { local $/; <$dumpfh>; };
    close($dumpfh);
    unlike($contents, $_) for @_;
}

sub append_to_class {
    my ($class, $string) = @_;
    $class =~ s{::}{/}g;
    $class = $DUMP_PATH . '/' . $class . '.pm';
    open(my $appendfh, '>>', $class) or die "Failed to open '$class' for append: $!";
    print $appendfh $string;
    close($appendfh);
}

sub get_md5sum_from_dump_file {
    my $path = shift;
    open(my $dumpfh, '<', $path) or die "Failed to open '$path': $!";
    my $contents = do { local $/; <$dumpfh>; };
    close($dumpfh);
    if ( $contents =~ /md5sum:([^\s]+)/ ) {
        return $1;
    }
    return;
}

rmtree($DUMP_PATH, 1, 1);

my $dumped = do_dump_test(
    classname => 'DBICTest::DumpMore::1',
    options => { },
    error => '',
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
            qr/1;\n$/,
        ],
        Bar => [
            qr/package DBICTest::DumpMore::1::Bar;/,
            qr/->set_primary_key/,
            qr/1;\n$/,
        ],
    },
    md5sum_ne => {
                  schema => '',
                  Foo    => '',
                  Bar    => '',
              },
);

append_to_class('DBICTest::DumpMore::1::Foo',q{# XXX This is my custom content XXX});

$dumped = do_dump_test(
    classname => 'DBICTest::DumpMore::1',
    options => { },
    error => '',
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
    md5sum_equals => $dumped->{'md5sums'},
);

$dumped = do_dump_test(
    classname => 'DBICTest::DumpMore::1',
    options => { really_erase_my_files => 1 },
    error => '',
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
    md5sum_ne => $dumped->{'md5sums'},
);

do_dump_test(
    classname => 'DBICTest::DumpMore::1',
    options => { use_namespaces => 1 },
    error => '',
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

do_dump_test(
    classname => 'DBICTest::DumpMore::1',
    options => { use_namespaces => 1,
                 result_namespace => 'Res',
                 resultset_namespace => 'RSet',
                 default_resultset_class => 'RSetBase',
             },
    error => '',
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

do_dump_test(
    classname => 'DBICTest::DumpMore::1',
    options => { use_namespaces => 1,
                 result_namespace => '+DBICTest::DumpMore::1::Res',
                 resultset_namespace => 'RSet',
                 default_resultset_class => 'RSetBase',
             },
    error => '',
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

END { rmtree($DUMP_PATH, 1, 1); }
