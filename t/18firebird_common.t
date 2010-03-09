use strict;
use warnings;
use Test::More;
use Scope::Guard ();
use lib qw(t/lib);
use dbixcsl_common_tests;

my $dbd_interbase_dsn      = $ENV{DBICTEST_FIREBIRD_DSN} || '';
my $dbd_interbase_user     = $ENV{DBICTEST_FIREBIRD_USER} || '';
my $dbd_interbase_password = $ENV{DBICTEST_FIREBIRD_PASS} || '';

my $odbc_dsn      = $ENV{DBICTEST_FIREBIRD_ODBC_DSN} || '';
my $odbc_user     = $ENV{DBICTEST_FIREBIRD_ODBC_USER} || '';
my $odbc_password = $ENV{DBICTEST_FIREBIRD_ODBC_PASS} || '';

my $schema;

my $tester = dbixcsl_common_tests->new(
    vendor      => 'Firebird',
    auto_inc_pk => 'INTEGER NOT NULL PRIMARY KEY',
    auto_inc_cb => sub {
        my ($table, $col) = @_;
        return (
            qq{ CREATE GENERATOR gen_${table}_${col} },
            qq{
                CREATE TRIGGER ${table}_bi FOR $table
                ACTIVE BEFORE INSERT POSITION 0
                AS
                BEGIN
                 IF (NEW.$col IS NULL) THEN
                  NEW.$col = GEN_ID(gen_${table}_${col},1);
                END
            }
        );
    },
    auto_inc_drop_cb => sub {
        my ($table, $col) = @_;
        return (
            qq{ DROP TRIGGER ${table}_bi },
            qq{ DROP GENERATOR gen_${table}_${col} },
        );
    },
    null        => '',
    loader_options => { unquoted_ddl => 1 },
    connect_info => [ ($dbd_interbase_dsn ? {
            dsn         => $dbd_interbase_dsn,
            user        => $dbd_interbase_user,
            password    => $dbd_interbase_password,
            connect_info_opts => { on_connect_call => 'use_softcommit' },
        } : ()),
        ($odbc_dsn ? {
            dsn         => $odbc_dsn,
            user        => $odbc_user,
            password    => $odbc_password,
        } : ()),
    ],
    extra => {
        count  => 6,
        run    => sub {
            $schema = shift;

            cleanup_extra();

            my $dbh = $schema->storage->dbh;

# create a mixed case table
            $dbh->do($_) for (
q{
    CREATE TABLE "Firebird_Loader_Test1" (
        "Id" INTEGER NOT NULL PRIMARY KEY,
        "Foo" INTEGER DEFAULT 42
    )
},
q{
    CREATE GENERATOR "Gen_Firebird_Loader_Test1_Id"
},
q{
    CREATE TRIGGER "Firebird_Loader_Test1_BI" for "Firebird_Loader_Test1"
    ACTIVE BEFORE INSERT POSITION 0
    AS
    BEGIN
     IF (NEW."Id" IS NULL) THEN
      NEW."Id" = GEN_ID("Gen_Firebird_Loader_Test1_Id",1);
    END
},
            );

            my $guard = Scope::Guard->new(\&cleanup_extra);

            $schema->_loader->{unquoted_ddl} = 0;
            $schema->_loader->_setup;
            {
                local $SIG{__WARN__} = sub {};
                $schema->rescan;
            }

            ok ((my $rsrc = eval { $schema->resultset('FirebirdLoaderTest1')->result_source }),
                'got rsrc for mixed case table');

            ok ((my $col_info = eval { $rsrc->column_info('Id') }),
                'got column_info for column Id');

            is $col_info->{accessor}, 'id', 'column Id has lowercase accessor "id"';

            is $col_info->{is_auto_increment}, 1, 'is_auto_increment detected for mixed case trigger';

            is $col_info->{sequence}, 'Gen_Firebird_Loader_Test1_Id', 'correct mixed case sequence name';

            is eval { $rsrc->column_info('Foo')->{default_value} }, 42, 'default_value detected for mixed case column';
        },
    },
);

if (not ($dbd_interbase_dsn || $odbc_dsn)) {
    $tester->skip_tests('You need to set the DBICTEST_FIREBIRD_DSN, _USER and _PASS and/or the DBICTEST_FIREBIRD_ODBC_DSN, _USER and _PASS environment variables');
}
else {
    # get rid of stupid warning from InterBase/GetInfo.pm
    if ($dbd_interbase_dsn) {
        local $SIG{__WARN__} = sub {};
        require DBD::InterBase;
        require DBD::InterBase::GetInfo;
    }
    $tester->run_tests();
}

sub cleanup_extra {
    $schema->storage->disconnect;
    my $dbh = $schema->storage->dbh;

    foreach my $stmt (
        'DROP TRIGGER "Firebird_Loader_Test1_BI"',
        'DROP GENERATOR "Gen_Firebird_Loader_Test1_Id"',
        'DROP TABLE "Firebird_Loader_Test1"',
    ) {
        eval { $dbh->do($stmt) };
    }
}
