use strict;
use Test::More;
use lib qw(t/lib);
use dbixcsl_common_tests;

eval { require DBD::SQLite };
my $class = $@ ? 'SQLite2' : 'SQLite';

my $tester = dbixcsl_common_tests->new(
    vendor          => 'SQLite',
    auto_inc_pk     => 'INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT',
    dsn             => "dbi:$class:dbname=./t/sqlite_test",
    user            => '',
    password        => '',
    connect_info_opts => {
        on_connect_do => 'PRAGMA foreign_keys = ON',
    },
    extra           => {
        create => [
            # 'sqlite_' is reserved, so we use 'extra_'
            q{
                CREATE TABLE "extra_loader_test1" (
                    "id" NOT NULL PRIMARY KEY,
                    "value" TEXT UNIQUE NOT NULL
                )
            },
            q{
                CREATE TABLE extra_loader_test2 (
                    event_id INTEGER PRIMARY KEY
                )
            },
            q{
                CREATE TABLE extra_loader_test3 (
                    person_id INTEGER PRIMARY KEY
                )
            },
            # Wordy, newline-heavy SQL
            q{
                CREATE TABLE extra_loader_test4 (
                    event_id INTEGER NOT NULL
                        CONSTRAINT fk_event_id
                        REFERENCES extra_loader_test2(event_id),
                    person_id INTEGER NOT NULL
                        CONSTRAINT fk_person_id
                        REFERENCES extra_loader_test3 (person_id),
                    PRIMARY KEY (event_id, person_id)
                )
            },
            # make sure views are picked up
            q{
                CREATE VIEW extra_loader_test5 AS SELECT * FROM extra_loader_test4
            }
        ],
        pre_drop_ddl => [ 'DROP VIEW extra_loader_test5' ],
        drop  => [ qw/extra_loader_test1 extra_loader_test2 extra_loader_test3 extra_loader_test4 / ],
        count => 9,
        run   => sub {
            my ($schema, $monikers, $classes) = @_;

            ok ((my $rs = $schema->resultset($monikers->{extra_loader_test1})),
                'resultset for quoted table');

            ok ((my $source = $rs->result_source), 'source');

            is_deeply [ $source->columns ], [ qw/id value/ ],
                'retrieved quoted column names from quoted table';

            ok ((exists $source->column_info('value')->{is_nullable}),
                'is_nullable exists');

            is $source->column_info('value')->{is_nullable}, 0,
                'is_nullable is set correctly';

            ok (($source = $schema->source($monikers->{extra_loader_test4})),
                'verbose table');

            is_deeply [ $source->primary_columns ], [ qw/event_id person_id/ ],
                'composite primary key';

            is ($source->relationships, 2,
                '2 foreign key constraints found');

            # test that columns for views are picked up
            is $schema->resultset($monikers->{extra_loader_test5})->result_source->column_info('person_id')->{data_type}, 'integer',
                'columns for views are introspected';
        },
    },
);

$tester->run_tests();

END {
    unlink './t/sqlite_test';
}
