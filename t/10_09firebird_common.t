use DBIx::Class::Schema::Loader::Optional::Dependencies
    -skip_all_without => 'test_rdbms_firebird';

use strict;
use warnings;
use DBIx::Class::Schema::Loader::Utils qw/sigwarn_silencer/;
use lib 't/lib';

use dbixcsl_firebird_tests;

{
    # get rid of stupid warning from Firebird/GetInfo.pm
    local $SIG{__WARN__} = sigwarn_silencer(
        qr{^(?:Argument "[0-9_]+" isn't numeric|Missing argument) in sprintf at \S+DBD/Firebird/GetInfo.pm line \d+\.$}
    );
    require DBD::Firebird::GetInfo;
}

my %conninfo;
@conninfo{qw(dsn user password)} = map { $ENV{"DBICTEST_FIREBIRD_$_"} } qw(DSN USER PASS);

dbixcsl_firebird_tests->new(
    %conninfo,
    connect_info_opts => {
        on_connect_call => 'use_softcommit',
    },
)->run_tests;

# vim:et sts=4 sw=4 tw=0:
