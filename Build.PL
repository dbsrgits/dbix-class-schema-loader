use strict;
use Module::Build;

my %arguments = (
    license            => 'perl',
    module_name        => 'DBIx::Class::Schema::Loader',
    requires           => {
        'DBIx::Class'           => 0.05,
        'UNIVERSAL::require'    => 0.10,
        'Lingua::EN::Inflect'   => 0,
        'Text::Balanced'        => 0,
        'Class::Accessor::Fast' => 0.22,
        'Class::Data::Accessor' => 0.02,
        'Class::C3'             => 0.09,
    },
    build_requires     => {
        'Test::More'          => 0.32,
        'DBI'                 => 1.40,
        'DBD::SQLite'         => 1.11,
    },
    create_makefile_pl => 'passthrough',
    create_readme      => 1,
);

Module::Build->new(%arguments)->create_build_script;
