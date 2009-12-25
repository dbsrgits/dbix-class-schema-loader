use strict;
use warnings;
use Test::More;
use File::Path;
use Class::Unload;
use lib qw(t/lib);
use make_dbictest_db2;

my $DUMP_DIR = './t/_common_dump';
rmtree $DUMP_DIR;

sub run_loader {
    my %loader_opts = @_;

    my $schema_class = 'DBIXCSL_Test::Schema';
    Class::Unload->unload($schema_class);

    my @connect_info = $make_dbictest_db2::dsn;
    my @loader_warnings;
    local $SIG{__WARN__} = sub { push(@loader_warnings, $_[0]); };
    eval qq{
        package $schema_class;
        use base qw/DBIx::Class::Schema::Loader/;

        __PACKAGE__->loader_options(\%loader_opts);
        __PACKAGE__->connection(\@connect_info);
    };

    ok(!$@, "Loader initialization") or diag $@;

    my $schema = $schema_class->clone;
    my (%monikers, %classes);
    foreach my $source_name ($schema->sources) {
        my $table_name = $schema->source($source_name)->from;
        $monikers{$table_name} = $source_name;
        $classes{$table_name}  = "${schema_class}::${source_name}";
    }

    return {
        schema => $schema,
        warnings => \@loader_warnings,
        monikers => \%monikers,
        classes => \%classes,
    };
}

# test dynamic schema in 0.04006 mode
{
    my $res = run_loader();

    like $res->{warnings}[0], qr/dynamic schema/i,
        'dynamic schema in backcompat mode detected';
    like $res->{warnings}[0], qr/run in 0\.04006 mode/,
        'dynamic schema in 0.04006 mode warning';

    is_deeply [ @{ $res->{monikers} }{qw/foos bar bazes quuxes/} ],
        [qw/Foos Bar Bazes Quuxes/],
        'correct monikers in 0.04006 mode';

    ok my $bar = eval { $res->{schema}->resultset('Bar')->find(1) };

    isa_ok eval { $bar->fooref }, $res->{classes}{foos},
        'correct rel name';

    ok my $baz  = eval { $res->{schema}->resultset('Bazes')->find(1) };

    isa_ok eval { $baz->quuxes }, 'DBIx::Class::ResultSet',
        'correct rel type and name for UNIQUE FK';
}

done_testing;

END { rmtree $DUMP_DIR }
