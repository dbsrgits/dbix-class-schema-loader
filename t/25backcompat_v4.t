use strict;
use warnings;
use Test::More;
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

    IO::File->new(">$external_result_dir/Quuxs.pm")->print(<<"EOF");
package ${SCHEMA_CLASS}::Quuxs;
sub a_method { 'hlagh' }
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

    is eval { $schema->resultset('Quux')->find(1)->a_method }, 'hlagh',
'external custom content for unsingularized Result was loaded by upgraded ' .
'dynamic Schema';

    run_v5_tests($res);

    rmtree $temp_dir;
    pop @INC;
}

# test running against v4 schema without upgrade
{
    # write out the 0.04006 Schema.pm we have in __DATA__
    (my $schema_dir = "$DUMP_DIR/$SCHEMA_CLASS") =~ s/::[^:]+\z//;
    make_path $schema_dir;
    my $schema_pm = "$schema_dir/Schema.pm";
    open my $fh, '>', $schema_pm or die $!;
    while (<DATA>) {
        print $fh $_;
    }
    close $fh;

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
                print "sub a_method { 'mtfnpy' }\n";
            }
            else {
                print;
            }
        }
    }

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
    is eval { $schema->resultset('Quux')->find(1)->a_method }, 'mtfnpy',
        'custom content was carried over from un-singularized Result';
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

# a Schema.pm made with 0.04006

__DATA__
package DBIXCSL_Test::Schema;

use strict;
use warnings;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_classes;


# Created by DBIx::Class::Schema::Loader v0.04006 @ 2009-12-25 01:49:25
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ibIJTbfM1ji4pyD/lgSEog


# You can replace this text with custom content, and it will be preserved on regeneration
1;

