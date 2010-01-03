use strict;
use warnings;
use Test::More;
use Test::Exception;
use File::Path qw/rmtree make_path/;
use Class::Unload;
use File::Temp qw/tempfile tempdir/;
use IO::File;
use lib qw(t/lib);
use make_dbictest_db2;

my $DUMP_DIR = './t/_common_dump';
rmtree $DUMP_DIR;
my $SCHEMA_CLASS = 'DBIXCSL_Test::Schema';

# test dynamic schema in 0.04006 mode
{
    my $res = run_loader();
    my $warning = $res->{warnings}[0];

    like $warning, qr/dynamic schema/i,
        'dynamic schema in backcompat mode detected';
    like $warning, qr/run in 0\.04006 mode/i,
        'dynamic schema in 0.04006 mode warning';
    like $warning, qr/DBIx::Class::Schema::Loader::Manual::UpgradingFromV4/,
        'warning refers to upgrading doc';
    
    run_v4_tests($res);
}

# setting naming accessor on dynamic schema should disable warning (even when
# we're setting it to 'v4' .)
{
    my $res = run_loader(naming => 'v4');

    is_deeply $res->{warnings}, [], 'no warnings with naming attribute set';

    run_v4_tests($res);
}

# test upgraded dynamic schema
{
    my $res = run_loader(naming => 'current');

# to dump a schema for debugging...
#    {
#        mkdir '/tmp/HLAGH';
#        $schema->_loader->{dump_directory} = '/tmp/HLAGH';
#        $schema->_loader->_dump_to_dir(values %{ $res->{classes} });
#    }

    is_deeply $res->{warnings}, [], 'no warnings with naming attribute set';

    run_v5_tests($res);
}

# test upgraded dynamic schema with external content loaded
{
    my $temp_dir = tempdir;
    push @INC, $temp_dir;

    my $external_result_dir = join '/', $temp_dir, split /::/, $SCHEMA_CLASS;
    make_path $external_result_dir;

    # make external content for Result that will be singularized
    IO::File->new(">$external_result_dir/Quuxs.pm")->print(<<"EOF");
package ${SCHEMA_CLASS}::Quuxs;
sub a_method { 'hlagh' }

__PACKAGE__->has_one('bazrel', 'DBIXCSL_Test::Schema::Bazs',
    { 'foreign.baz_num' => 'self.baz_id' });

1;
EOF

    # make external content for Result that will NOT be singularized
    IO::File->new(">$external_result_dir/Bar.pm")->print(<<"EOF");
package ${SCHEMA_CLASS}::Bar;

__PACKAGE__->has_one('foorel', 'DBIXCSL_Test::Schema::Foos',
    { 'foreign.fooid' => 'self.foo_id' });

1;
EOF

    my $res = run_loader(naming => 'current');
    my $schema = $res->{schema};

    is scalar @{ $res->{warnings} }, 1,
'correct nummber of warnings for upgraded dynamic schema with external ' .
'content for unsingularized Result.';

    my $warning = $res->{warnings}[0];
    like $warning, qr/Detected external content/i,
        'detected external content warning';

    lives_and { is $schema->resultset('Quux')->find(1)->a_method, 'hlagh' }
'external custom content for unsingularized Result was loaded by upgraded ' .
'dynamic Schema';

    lives_and { isa_ok $schema->resultset('Quux')->find(1)->bazrel,
        $res->{classes}{bazs} }
        'unsingularized class names in external content are translated';

    lives_and { isa_ok $schema->resultset('Bar')->find(1)->foorel,
        $res->{classes}{foos} }
'unsingularized class names in external content from unchanged Result class ' .
'names are translated';

    run_v5_tests($res);

    rmtree $temp_dir;
    pop @INC;
}

# test upgraded static schema with external content loaded
{
    my $temp_dir = tempdir;
    push @INC, $temp_dir;

    my $external_result_dir = join '/', $temp_dir, split /::/, $SCHEMA_CLASS;
    make_path $external_result_dir;

    # make external content for Result that will be singularized
    IO::File->new(">$external_result_dir/Quuxs.pm")->print(<<"EOF");
package ${SCHEMA_CLASS}::Quuxs;
sub a_method { 'dongs' }

__PACKAGE__->has_one('bazrel2', 'DBIXCSL_Test::Schema::Bazs',
    { 'foreign.baz_num' => 'self.baz_id' });

1;
EOF

    # make external content for Result that will NOT be singularized
    IO::File->new(">$external_result_dir/Bar.pm")->print(<<"EOF");
package ${SCHEMA_CLASS}::Bar;

__PACKAGE__->has_one('foorel2', 'DBIXCSL_Test::Schema::Foos',
    { 'foreign.fooid' => 'self.foo_id' });

1;
EOF

    write_v4_schema_pm();

    my $res = run_loader(dump_directory => $DUMP_DIR, naming => 'current');
    my $schema = $res->{schema};

    run_v5_tests($res);

    lives_and { is $schema->resultset('Quux')->find(1)->a_method, 'dongs' }
'external custom content for unsingularized Result was loaded by upgraded ' .
'static Schema';

    lives_and { isa_ok $schema->resultset('Quux')->find(1)->bazrel2,
        $res->{classes}{bazs} }
        'unsingularized class names in external content are translated';

    lives_and { isa_ok $schema->resultset('Bar')->find(1)->foorel2,
        $res->{classes}{foos} }
'unsingularized class names in external content from unchanged Result class ' .
'names are translated in static schema';

    my $file = $schema->_loader->_get_dump_filename($res->{classes}{quuxs});
    my $code = do { local ($/, @ARGV) = (undef, $file); <> };

    like $code, qr/package ${SCHEMA_CLASS}::Quux;/,
'package line translated correctly from external custom content in static dump';

    like $code, qr/sub a_method { 'dongs' }/,
'external custom content loaded into static dump correctly';

    rmtree $temp_dir;
    pop @INC;
}

# test running against v4 schema without upgrade, twice, then upgrade
{
    write_v4_schema_pm();

    # now run the loader
    my $res = run_loader(dump_directory => $DUMP_DIR);
    my $warning = $res->{warnings}[0];

    like $warning, qr/static schema/i,
        'static schema in backcompat mode detected';
    like $warning, qr/0.04006/,
        'correct version detected';
    like $warning, qr/DBIx::Class::Schema::Loader::Manual::UpgradingFromV4/,
        'refers to upgrading doc';

    is scalar @{ $res->{warnings} }, 3,
        'correct number of warnings for static schema in backcompat mode';

    run_v4_tests($res);

    # add some custom content to a Result that will be replaced
    my $schema   = $res->{schema};
    my $quuxs_pm = $schema->_loader
        ->_get_dump_filename($res->{classes}{quuxs});
    {
        local ($^I, @ARGV) = ('', $quuxs_pm);
        while (<>) {
            if (/DO NOT MODIFY THIS OR ANYTHING ABOVE/) {
                print;
                print <<EOF;
sub a_method { 'mtfnpy' }

__PACKAGE__->has_one('bazrel3', 'DBIXCSL_Test::Schema::Bazs',
    { 'foreign.baz_num' => 'self.baz_id' });
EOF
            }
            else {
                print;
            }
        }
    }

    # Rerun the loader in backcompat mode to make sure it's still in backcompat
    # mode.
    $res = run_loader(dump_directory => $DUMP_DIR);
    run_v4_tests($res);

    # now upgrade the schema
    $res = run_loader(dump_directory => $DUMP_DIR, naming => 'current');
    $schema = $res->{schema};

    like $res->{warnings}[0], qr/Dumping manual schema/i,
        'correct warnings on upgrading static schema (with "naming" set)';

    like $res->{warnings}[1], qr/dump completed/i,
        'correct warnings on upgrading static schema (with "naming" set)';

    is scalar @{ $res->{warnings} }, 2,
'correct number of warnings on upgrading static schema (with "naming" set)'
        or diag @{ $res->{warnings} };

    run_v5_tests($res);

    (my $result_dir = "$DUMP_DIR/$SCHEMA_CLASS") =~ s{::}{/}g;
    my $result_count =()= glob "$result_dir/*";

    is $result_count, 4,
        'un-singularized results were replaced during upgrade';

    # check that custom content was preserved
    lives_and { is $schema->resultset('Quux')->find(1)->a_method, 'mtfnpy' }
        'custom content was carried over from un-singularized Result';

    lives_and { isa_ok $schema->resultset('Quux')->find(1)->bazrel3,
        $res->{classes}{bazs} }
        'unsingularized class names in custom content are translated';

    my $file = $schema->_loader->_get_dump_filename($res->{classes}{quuxs});
    my $code = do { local ($/, @ARGV) = (undef, $file); <> };

    like $code, qr/sub a_method { 'mtfnpy' }/,
'custom content from unsingularized Result loaded into static dump correctly';
}

# Test upgrading an already singular result with custom content that refers to
# old class names.
{
    write_v4_schema_pm();
    my $res = run_loader(dump_directory => $DUMP_DIR);
    my $schema   = $res->{schema};
    run_v4_tests($res);

    # add some custom content to a Result that will be replaced
    my $bar_pm = $schema->_loader
        ->_get_dump_filename($res->{classes}{bar});
    {
        local ($^I, @ARGV) = ('', $bar_pm);
        while (<>) {
            if (/DO NOT MODIFY THIS OR ANYTHING ABOVE/) {
                print;
                print <<EOF;
sub a_method { 'lalala' }

__PACKAGE__->has_one('foorel3', 'DBIXCSL_Test::Schema::Foos',
    { 'foreign.fooid' => 'self.foo_id' });
EOF
            }
            else {
                print;
            }
        }
    }

    # now upgrade the schema
    $res = run_loader(dump_directory => $DUMP_DIR, naming => 'current');
    $schema = $res->{schema};
    run_v5_tests($res);

    # check that custom content was preserved
    lives_and { is $schema->resultset('Bar')->find(1)->a_method, 'lalala' }
        'custom content was preserved from Result pre-upgrade';

    lives_and { isa_ok $schema->resultset('Bar')->find(1)->foorel3,
        $res->{classes}{foos} }
'unsingularized class names in custom content from Result with unchanged ' .
'name are translated';

    my $file = $schema->_loader->_get_dump_filename($res->{classes}{bar});
    my $code = do { local ($/, @ARGV) = (undef, $file); <> };

    like $code, qr/sub a_method { 'lalala' }/,
'custom content from Result with unchanged name loaded into static dump ' .
'correctly';
}

done_testing;

END {
    rmtree $DUMP_DIR unless $ENV{SCHEMA_LOADER_TESTS_NOCLEANUP};
}

sub run_loader {
    my %loader_opts = @_;

    eval {
        foreach my $source_name ($SCHEMA_CLASS->clone->sources) {
            Class::Unload->unload("${SCHEMA_CLASS}::${source_name}");
        }

        Class::Unload->unload($SCHEMA_CLASS);
    };
    undef $@;

    my @connect_info = $make_dbictest_db2::dsn;
    my @loader_warnings;
    local $SIG{__WARN__} = sub { push(@loader_warnings, $_[0]); };
    eval qq{
        package $SCHEMA_CLASS;
        use base qw/DBIx::Class::Schema::Loader/;

        __PACKAGE__->loader_options(\%loader_opts);
        __PACKAGE__->connection(\@connect_info);
    };

    ok(!$@, "Loader initialization") or diag $@;

    my $schema = $SCHEMA_CLASS->clone;
    my (%monikers, %classes);
    foreach my $source_name ($schema->sources) {
        my $table_name = $schema->source($source_name)->from;
        $monikers{$table_name} = $source_name;
        $classes{$table_name}  = "${SCHEMA_CLASS}::${source_name}";
    }

    return {
        schema => $schema,
        warnings => \@loader_warnings,
        monikers => \%monikers,
        classes => \%classes,
    };
}

sub write_v4_schema_pm {
    (my $schema_dir = "$DUMP_DIR/$SCHEMA_CLASS") =~ s/::[^:]+\z//;
    rmtree $schema_dir;
    make_path $schema_dir;
    my $schema_pm = "$schema_dir/Schema.pm";
    open my $fh, '>', $schema_pm or die $!;
    print $fh <<'EOF';
package DBIXCSL_Test::Schema;

use strict;
use warnings;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_classes;


# Created by DBIx::Class::Schema::Loader v0.04006 @ 2009-12-25 01:49:25
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ibIJTbfM1ji4pyD/lgSEog


# You can replace this text with custom content, and it will be preserved on regeneration
1;
EOF
}

sub run_v4_tests {
    my $res = shift;
    my $schema = $res->{schema};

    is_deeply [ @{ $res->{monikers} }{qw/foos bar bazs quuxs/} ],
        [qw/Foos Bar Bazs Quuxs/],
        'correct monikers in 0.04006 mode';

    isa_ok ((my $bar = eval { $schema->resultset('Bar')->find(1) }),
        $res->{classes}{bar},
        'found a bar');

    isa_ok eval { $bar->foo_id }, $res->{classes}{foos},
        'correct rel name in 0.04006 mode';

    ok my $baz  = eval { $schema->resultset('Bazs')->find(1) };

    isa_ok eval { $baz->quux }, 'DBIx::Class::ResultSet',
        'correct rel type and name for UNIQUE FK in 0.04006 mode';
}

sub run_v5_tests {
    my $res = shift;
    my $schema = $res->{schema};

    is_deeply [ @{ $res->{monikers} }{qw/foos bar bazs quuxs/} ],
        [qw/Foo Bar Baz Quux/],
        'correct monikers in current mode';

    ok my $bar = eval { $schema->resultset('Bar')->find(1) };

    isa_ok eval { $bar->foo }, $res->{classes}{foos},
        'correct rel name in current mode';

    ok my $baz  = eval { $schema->resultset('Baz')->find(1) };

    isa_ok eval { $baz->quux }, $res->{classes}{quuxs},
        'correct rel type and name for UNIQUE FK in current mode';
}
