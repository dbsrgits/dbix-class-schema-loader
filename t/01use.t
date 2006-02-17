use strict;
use Test::More tests => 5;

BEGIN {
    use_ok 'DBIx::Class::Schema::Loader';
    use_ok 'DBIx::Class::Schema::Loader::SQLite';
    use_ok 'DBIx::Class::Schema::Loader::mysql';
    use_ok 'DBIx::Class::Schema::Loader::Pg';
    use_ok 'DBIx::Class::Schema::Loader::DB2';
}
