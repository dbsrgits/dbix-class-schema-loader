
use inc::Module::Install;

name           'DBIx-Class-Schema-Loader';
all_from       'lib/DBIx/Class/Schema/Loader.pm';

test_requires 'Test::More'  => '0.47';
test_requires 'DBI'         => '1.56';
test_requires 'DBD::SQLite' => '1.12';
test_requires 'File::Path'  => 0;

requires 'File::Spec'                  => 0;
requires 'Scalar::Util'                => 0;
requires 'Data::Dump'                  => '1.06';
requires 'UNIVERSAL::require'          => '0.11';
requires 'Lingua::EN::Inflect::Number' => '1.1';
requires 'Text::Balanced'              => 0;
requires 'Digest::MD5'                 => '2.36';
requires 'Class::Accessor::Fast'       => '0.30';
requires 'Class::Data::Accessor'       => '0.03';
requires 'Class::C3'                   => '0.18';
requires 'Carp::Clan'                  => 0;
requires 'Class::Inspector'            => 0;
requires 'DBIx::Class'                 => '0.07006';

feature 'SQLite Support' =>
    -default      => $ENV{DBIC_FEATURE_SQLITE} || 0,
    'DBI'         => '1.56',
    'DBD::SQLite' => '1.12';

feature 'MySQL Support' =>
    -default      => $ENV{DBIC_FEATURE_MYSQL} || 0,
    'DBI'         => '1.56',
    'DBD::mysql'  => '4.004';

feature 'PostgreSQL Support' =>
    -default      => $ENV{DBIC_FEATURE_PG} || 0,
    'DBI'         => '1.56',
    'DBD::Pg'     => '1.49'; # Soon to be 1.50

feature 'DB2 Support' =>
    -default      => $ENV{DBIC_FEATURE_DB2} || 0,
    'DBI'         => '1.56',
    'DBD::DB2'    => '1.0';

feature 'Oracle Support (*experimental*)' =>
    -default      => $ENV{DBIC_FEATURE_ORACLE} || 0,
    'DBI'         => '1.56',
    'DBD::Oracle' => '0.19';

# Rebuild README for maintainers
if(-e 'MANIFEST.SKIP') {
    system("pod2text lib/DBIx/Class/Schema/Loader.pm > README");
}

auto_provides;
auto_install;
WriteAll;
