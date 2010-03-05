package dbixcsl_firebird_extra_tests;

use strict;
use warnings;
use Test::More;
use Test::Exception;

sub extra { +{
    create => [
# test a mixed case table
        q{
            CREATE TABLE "Firebird_Loader_Test1" (
                "Id" INTEGER NOT NULL PRIMARY KEY
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
    ],
    pre_drop_ddl => [
        q{DROP TRIGGER "Firebird_Loader_Test1_BI"},
        q{DROP GENERATOR "Gen_Firebird_Loader_Test1_Id"},
    ],
    drop   => [
        q{"Firebird_Loader_Test1"}
    ],
    count  => 5,
    run    => sub {
        my ($schema, $monikers, $classes) = @_;

        ok ((my $rsrc = eval { $schema->resultset($monikers->{Firebird_Loader_Test1})->result_source }),
            'got rsrc for mixed case table');

        ok ((my $col_info = eval { $rsrc->column_info('Id') }),
            'got column_info for column Id');

        is $col_info->{accessor}, 'id', 'column Id has lowercase accessor "id"';

        is $col_info->{is_auto_increment}, 1, 'is_auto_increment detected for mixed case trigger';

        is $col_info->{sequence}, 'Gen_Firebird_Loader_Test1_Id', 'correct mixed case sequence name';
    },
}}

1;
