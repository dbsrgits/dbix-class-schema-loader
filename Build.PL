use strict;
use Module::Build;

my %arguments = (
    license            => 'perl',
    module_name        => 'DBIx::Class::Schema::Loader',
    requires           => {
        'File::Spec'                    => 0,
        'Scalar::Util'                  => 0,
        'Data::Dump'                    => 1.06,
        'UNIVERSAL::require'            => 0.11,
        'Lingua::EN::Inflect::Number'   => 1.1,
        'Text::Balanced'                => 0,
        'Digest::MD5'                   => 2.36,
        'Class::Accessor::Fast'         => 0.30,
        'Class::Data::Accessor'         => 0.03,
        'Class::C3'                     => 0.14,
        'Carp::Clan'                    => 0,
        'DBIx::Class'                   => 0.07005,
    },
    recommends         => {
        'Class::Inspector'              => 0,
        'DBI'                           => 1.53,
        'DBD::SQLite'                   => 1.13,
        'DBD::mysql'                    => 4.004,
        'DBD::Pg'                       => 1.49, # Soon to be 1.50
        'DBD::DB2'                      => 1.0,
        'DBD::Oracle'                   => 0.19,
    },
    build_requires     => {
        'Test::More'                    => 0.32,
        'DBI'                           => 1.53,
        'DBD::SQLite'                   => 1.13,
        'File::Path'                    => 0,
    },
    create_makefile_pl => 'passthrough',
    create_readme      => 1,
);

Module::Build->new(%arguments)->create_build_script;
