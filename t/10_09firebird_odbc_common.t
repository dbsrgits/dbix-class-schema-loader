use DBIx::Class::Schema::Loader::Optional::Dependencies
    -skip_all_without => 'test_rdbms_firebird_odbc';

use strict;
use warnings;
use lib 't/lib';

use dbixcsl_firebird_tests;

my %conninfo;
@conninfo{qw(dsn user password)} = map { $ENV{"DBICTEST_FIREBIRD_ODBC_$_"} } qw(DSN USER PASS);

dbixcsl_firebird_tests->new(%conninfo)->run_tests;

# vim:et sts=4 sw=4 tw=0:
