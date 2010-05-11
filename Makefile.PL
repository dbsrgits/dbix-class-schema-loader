use inc::Module::Install 0.91;

name           'DBIx-Class-Schema-Loader';
all_from       'lib/DBIx/Class/Schema/Loader.pm';

test_requires 'Test::Exception';
test_requires 'Test::More'    => '0.94';
test_requires 'DBI'           => '1.56';
test_requires 'DBD::SQLite'   => '1.29';
test_requires 'File::Copy';
test_requires 'File::Temp'    => '0.16';
test_requires 'File::Path'    => '2.07';
test_requires 'IPC::Open3'    => 0;

requires 'File::Spec'                  => 0;
requires 'Scalar::Util'                => 0;
requires 'Data::Dump'                  => '1.06';
requires 'Lingua::EN::Inflect::Number' => '1.1';
requires 'Lingua::EN::Inflect::Phrase' => '0.02';
requires 'Text::Balanced'              => 0;
requires 'Digest::MD5'                 => '2.36';
requires 'Class::Accessor::Grouped'    => '0.09002';
requires 'Class::C3'                   => '0.18';
requires 'Class::C3::Componentised'    => '1.0005';
requires 'Carp::Clan'                  => 0;
requires 'Class::Inspector'            => 0;
requires 'DBIx::Class'                 => '0.08114';
requires 'Class::Unload'               => 0;
requires 'File::Slurp'                 => '9999.13';
requires 'List::MoreUtils'             => 0;
requires 'namespace::autoclean'        => 0;
requires 'Data::Dumper::Concise'       => '1.200';
requires 'Scope::Guard'                => 0;
requires 'List::MoreUtils'             => 0;
requires 'Exporter'                    => '5.63';

install_script 'script/dbicdump';

tests_recursive;

# Rebuild README for maintainers
if ($Module::Install::AUTHOR) {
    system("pod2text lib/DBIx/Class/Schema/Loader.pm > README");
}

realclean_files 'README';

resources 'IRC'         => 'irc://irc.perl.org/#dbix-class';
resources 'license'     => 'http://dev.perl.org/licenses/';
resources 'repository'  => 'git://git.shadowcat.co.uk/dbsrgits/DBIx-Class-Schema-Loader.git';
resources 'MailingList' => 'http://lists.scsys.co.uk/cgi-bin/mailman/listinfo/dbix-class';

auto_provides;
auto_install;
WriteAll;
