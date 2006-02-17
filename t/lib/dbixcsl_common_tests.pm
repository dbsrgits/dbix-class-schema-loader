package dbixcsl_common_tests;

use strict;
use warnings;

use Test::More;
use DBIx::Class::Schema::Loader;
use DBI;

sub new {
    my $class = shift;

    my $self;

    if( ref($_[0]) eq 'HASH') {
       my $args = shift;
       $self = { (%$args) };
    }
    else {
       $self = { @_ };
    }

    # Only MySQL uses this
    $self->{innodb} ||= '';
    
    $self->{verbose} = $ENV{TEST_VERBOSE} || 0;

    return bless $self => $class;
}

sub skip_tests {
    my ($self, $why) = @_;

    plan skip_all => $why;
}

sub run_tests {
    my $self = shift;

    plan tests => 49;

    $self->create();

    my $schema_class = 'DBIXCSL_Test::Schema';

    my $debug = ($self->{verbose} > 1) ? 1 : 0;

    my %loader_opts = (
        dsn                     => $self->{dsn},
        user                    => $self->{user},
        password                => $self->{password},
        constraint              => '^(?:\S+\.)?(?i:loader_test)[0-9]+$',
        relationships           => 1,
        additional_classes      => 'TestAdditional',
        additional_base_classes => 'TestAdditionalBase',
        left_base_classes       => [ qw/TestLeftBase/ ],
        components              => [ qw/TestComponent/ ],
        resultset_components    => [ qw/TestRSComponent/ ],
        debug                   => $debug,
    );

    $loader_opts{db_schema} = $self->{db_schema} if $self->{db_schema};
    $loader_opts{drop_db_schema} = $self->{drop_db_schema} if $self->{drop_db_schema};

    eval qq{
        package $schema_class;
        use base qw/DBIx::Class::Schema::Loader/;

        __PACKAGE__->load_from_connection(\%loader_opts);
    };
    ok(!$@, "Loader initialization") or diag $@;

    my $conn = $schema_class->connect($self->{dsn},$self->{user},$self->{password});
    my $monikers = $schema_class->loader->monikers;
    my $classes = $schema_class->loader->classes;

    my $moniker1 = $monikers->{loader_test1};
    my $class1   = $classes->{loader_test1};
    my $rsobj1   = $conn->resultset($moniker1);

    my $moniker2 = $monikers->{loader_test2};
    my $class2   = $classes->{loader_test2};
    my $rsobj2   = $conn->resultset($moniker2);

    isa_ok( $rsobj1, "DBIx::Class::ResultSet" );
    isa_ok( $rsobj2, "DBIx::Class::ResultSet" );

    {
        my ($skip_tab, $skip_tabo, $skip_taba, $skip_cmeth,
            $skip_rsmeth, $skip_tcomp, $skip_trscomp);

        can_ok( $class1, 'test_additional_base' ) or $skip_tab = 1;
        can_ok( $class1, 'test_additional_base_override' ) or $skip_tabo = 1;
        can_ok( $class1, 'test_additional_base_additional' ) or $skip_taba = 1;
        can_ok( $class1, 'dbix_class_testcomponent' ) or $skip_tcomp = 1;
        can_ok( $rsobj1, 'dbix_class_testrscomponent' ) or $skip_trscomp = 1;
        can_ok( $class1, 'loader_test1_classmeth' ) or $skip_cmeth = 1;

	TODO: {
	    local $TODO = "Not yet supported by ResultSetManger code";
            can_ok( $rsobj1, 'loader_test1_rsmeth' ) or $skip_rsmeth = 1;
	}

        SKIP: {
            skip "Pre-requisite test failed", 1 if $skip_tab;
            is( $class1->test_additional_base, "test_additional_base",
                "Additional Base method" );
        }

        SKIP: {
            skip "Pre-requisite test failed", 1 if $skip_tabo;
            is( $class1->test_additional_base_override,
                "test_left_base_override",
                "Left Base overrides Additional Base method" );
        }

        SKIP: {
            skip "Pre-requisite test failed", 1 if $skip_taba;
            is( $class1->test_additional_base_additional, "test_additional",
                "Additional Base can use Additional package method" );
        }

        SKIP: {
            skip "Pre-requisite test failed", 1 if $skip_tcomp;
            is( $class1->dbix_class_testcomponent,
                'dbix_class_testcomponent works' );
        }

        SKIP: {
            skip "Pre-requisite test failed", 1 if $skip_trscomp;
            is( $rsobj1->dbix_class_testrscomponent,
                'dbix_class_testrscomponent works' );
        }

        SKIP: {
            skip "Pre-requisite test failed", 1 if $skip_cmeth;
            is( $class1->loader_test1_classmeth, 'all is well' );
        }

        # XXX put this back in when the TODO above works...
        #SKIP: {
        #    skip "Pre-requisite test failed", 1 if $skip_rsmeth;
        #    is( $rsobj1->loader_test1_rsmeth, 'all is still well' );
        #}
    }


    my $obj    = $rsobj1->find(1);
    is( $obj->id,  1 );
    is( $obj->dat, "foo" );
    is( $rsobj2->count, 4 );

    my ($obj2) = $rsobj2->find( dat => 'bbb' );
    is( $obj2->id, 2 );

    SKIP: {
        skip $self->{skip_rels}, 29 if $self->{skip_rels};

        my $moniker3 = $monikers->{loader_test3};
        my $class3   = $classes->{loader_test3};
        my $rsobj3   = $conn->resultset($moniker3);

        my $moniker4 = $monikers->{loader_test4};
        my $class4   = $classes->{loader_test4};
        my $rsobj4   = $conn->resultset($moniker4);

        my $moniker5 = $monikers->{loader_test5};
        my $class5   = $classes->{loader_test5};
        my $rsobj5   = $conn->resultset($moniker5);

        my $moniker6 = $monikers->{loader_test6};
        my $class6   = $classes->{loader_test6};
        my $rsobj6   = $conn->resultset($moniker6);

        my $moniker7 = $monikers->{loader_test7};
        my $class7   = $classes->{loader_test7};
        my $rsobj7   = $conn->resultset($moniker7);

        my $moniker8 = $monikers->{loader_test8};
        my $class8   = $classes->{loader_test8};
        my $rsobj8   = $conn->resultset($moniker8);

        my $moniker9 = $monikers->{loader_test9};
        my $class9   = $classes->{loader_test9};
        my $rsobj9   = $conn->resultset($moniker9);

        isa_ok( $rsobj3, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj4, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj5, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj6, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj7, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj8, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj9, "DBIx::Class::ResultSet" );

        # basic rel test
        my $obj4 = $rsobj4->find(123);
        isa_ok( $obj4->fkid, $class3);

        my $obj3 = $rsobj3->find(1);
        my $rs_rel4 = $obj3->search_related('loader_test4s');
        isa_ok( $rs_rel4->first, $class4);

        # fk def in comments should not be parsed
        my $obj5 = $rsobj5->find( id1 => 1, id2 => 1 );
        is( ref( $obj5->id2 ), '' );

        # mulit-col fk def
        my $obj6 = $rsobj6->find(1);
        isa_ok( $obj6->loader_test2, $class2);
        isa_ok( $obj6->loader_test5, $class5);

        # fk that references a non-pk key (UNIQUE)
        my $obj8 = $rsobj8->find(1);
        isa_ok( $obj8->loader_test7, $class7);

        # from Chisel's tests...
        SKIP: {
            if($self->{vendor} =~ /sqlite/i) {
                skip 'SQLite cannot do the advanced tests', 8;
            }

            my $moniker10 = $monikers->{loader_test10};
            my $class10   = $classes->{loader_test10};
            my $rsobj10   = $conn->resultset($moniker10);

            my $moniker11 = $monikers->{loader_test11};
            my $class11   = $classes->{loader_test11};
            my $rsobj11   = $conn->resultset($moniker11);

            isa_ok( $rsobj10, "DBIx::Class::ResultSet" ); 
            isa_ok( $rsobj11, "DBIx::Class::ResultSet" );

            my $obj10 = $rsobj10->create({ subject => 'xyzzy' });

            $obj10->update();
            ok( defined $obj10, '$obj10 is defined' );

            my $obj11 = $rsobj11->create({ loader_test10 => $obj10->id() });
            $obj11->update();
            ok( defined $obj11, '$obj11 is defined' );

            eval {
                my $obj10_2 = $obj11->loader_test10;
                $obj10_2->loader_test11( $obj11->id11() );
                $obj10_2->update();
            };
            is($@, '', 'No errors after eval{}');

            SKIP: {
                skip 'Previous eval block failed', 3
                    unless ($@ eq '');
        
                my $results = $rsobj10->search({ subject => 'xyzzy' });
                is( $results->count(), 1,
                    'One $rsobj10 returned from search' );

                my $obj10_3 = $results->first();
                isa_ok( $obj10_3, $class10 );
                is( $obj10_3->loader_test11()->id(), $obj11->id(),
                    'found same $rsobj11 object we expected' );
            }
        }

        SKIP: {
            skip 'This vendor cannot do inline relationship definitions', 5
                if $self->{no_inline_rels};

            my $moniker12 = $monikers->{loader_test12};
            my $class12   = $classes->{loader_test12};
            my $rsobj12   = $conn->resultset($moniker12);

            my $moniker13 = $monikers->{loader_test13};
            my $class13   = $classes->{loader_test13};
            my $rsobj13   = $conn->resultset($moniker13);

            isa_ok( $rsobj12, "DBIx::Class::ResultSet" ); 
            isa_ok( $rsobj13, "DBIx::Class::ResultSet" );

            my $obj13 = $rsobj13->find(1);
            isa_ok( $obj13->id, $class12 );
            isa_ok( $obj13->loader_test12, $class12);
            isa_ok( $obj13->dat, $class12);
        }

        SKIP: {
            skip 'This vendor cannot do out-of-line implicit rel defs', 3
                if $self->{no_implicit_rels};
            my $moniker14 = $monikers->{loader_test14};
            my $class14   = $classes->{loader_test14};
            my $rsobj14   = $conn->resultset($moniker14);

            my $moniker15 = $monikers->{loader_test15};
            my $class15   = $classes->{loader_test15};
            my $rsobj15   = $conn->resultset($moniker15);

            isa_ok( $rsobj14, "DBIx::Class::ResultSet" ); 
            isa_ok( $rsobj15, "DBIx::Class::ResultSet" );

            my $obj15 = $rsobj15->find(1);
            isa_ok( $obj15->loader_test14, $class14 );
        }
    }
}

sub dbconnect {
    my ($self, $complain) = @_;

    my $dbh = DBI->connect(
         $self->{dsn}, $self->{user},
         $self->{password},
         {
             RaiseError => $complain,
             PrintError => $complain,
             AutoCommit => 1,
         }
    );

    die "Failed to connect to database: $DBI::errstr" if !$dbh;

    return $dbh;
}

sub create {
    my $self = shift;

    my @statements = (
        qq{
            CREATE TABLE loader_test1 (
                id $self->{auto_inc_pk},
                dat VARCHAR(32)
            ) $self->{innodb}
        },

        q{ INSERT INTO loader_test1 (dat) VALUES('foo') },
        q{ INSERT INTO loader_test1 (dat) VALUES('bar') }, 
        q{ INSERT INTO loader_test1 (dat) VALUES('baz') }, 

        qq{ 
            CREATE TABLE loader_test2 (
                id $self->{auto_inc_pk},
                dat VARCHAR(32)
            ) $self->{innodb}
        },

        q{ INSERT INTO loader_test2 (dat) VALUES('aaa') }, 
        q{ INSERT INTO loader_test2 (dat) VALUES('bbb') }, 
        q{ INSERT INTO loader_test2 (dat) VALUES('ccc') }, 
        q{ INSERT INTO loader_test2 (dat) VALUES('ddd') }, 
    );

    my @statements_reltests = (
        qq{
            CREATE TABLE loader_test3 (
                id INTEGER NOT NULL PRIMARY KEY,
                dat VARCHAR(32)
            ) $self->{innodb}
        },

        q{ INSERT INTO loader_test3 (id,dat) VALUES(1,'aaa') }, 
        q{ INSERT INTO loader_test3 (id,dat) VALUES(2,'bbb') }, 
        q{ INSERT INTO loader_test3 (id,dat) VALUES(3,'ccc') }, 
        q{ INSERT INTO loader_test3 (id,dat) VALUES(4,'ddd') }, 

        qq{
            CREATE TABLE loader_test4 (
                id INTEGER NOT NULL PRIMARY KEY,
                fkid INTEGER NOT NULL,
                dat VARCHAR(32),
                FOREIGN KEY (fkid) REFERENCES loader_test3 (id)
            ) $self->{innodb}
        },

        q{ INSERT INTO loader_test4 (id,fkid,dat) VALUES(123,1,'aaa') },
        q{ INSERT INTO loader_test4 (id,fkid,dat) VALUES(124,2,'bbb') }, 
        q{ INSERT INTO loader_test4 (id,fkid,dat) VALUES(125,3,'ccc') },
        q{ INSERT INTO loader_test4 (id,fkid,dat) VALUES(126,4,'ddd') },

        qq{
            CREATE TABLE loader_test5 (
                id1 INTEGER NOT NULL,
                id2 INTEGER NOT NULL, -- , id2 INTEGER REFERENCES loader_test1,
                dat VARCHAR(8),
                PRIMARY KEY (id1,id2)
            ) $self->{innodb}
        },

        q{ INSERT INTO loader_test5 (id1,id2,dat) VALUES (1,1,'aaa') },

        qq{
            CREATE TABLE loader_test6 (
                id INTEGER NOT NULL PRIMARY KEY,
                id2 INTEGER,
                loader_test2 INTEGER,
                dat VARCHAR(8),
                FOREIGN KEY (loader_test2) REFERENCES loader_test2 (id),
                FOREIGN KEY (id, id2 ) REFERENCES loader_test5 (id1,id2)
            ) $self->{innodb}
        },

        (q{ INSERT INTO loader_test6 (id, id2,loader_test2,dat) } .
         q{ VALUES (1, 1,1,'aaa') }),

        qq{
            CREATE TABLE loader_test7 (
                id INTEGER NOT NULL PRIMARY KEY,
                id2 VARCHAR(8) NOT NULL UNIQUE,
                dat VARCHAR(8)
            ) $self->{innodb}
        },

        q{ INSERT INTO loader_test7 (id,id2,dat) VALUES (1,'aaa','bbb') },

        qq{
            CREATE TABLE loader_test8 (
                id INTEGER NOT NULL PRIMARY KEY,
                loader_test7 VARCHAR(8) NOT NULL,
                dat VARCHAR(8),
                FOREIGN KEY (loader_test7) REFERENCES loader_test7 (id2)
            ) $self->{innodb}
        },

        (q{ INSERT INTO loader_test8 (id,loader_test7,dat) } .
         q{ VALUES (1,'aaa','bbb') }),

        qq{
            CREATE TABLE loader_test9 (
                loader_test9 VARCHAR(8) NOT NULL
            ) $self->{innodb}
        },
    );

    my @statements_advanced = (
        qq{
            CREATE TABLE loader_test10 (
                id10 $self->{auto_inc_pk},
                subject VARCHAR(8),
                loader_test11 INTEGER
            ) $self->{innodb}
        },

        qq{
            CREATE TABLE loader_test11 (
                id11 $self->{auto_inc_pk},
                message VARCHAR(8) DEFAULT 'foo',
                loader_test10 INTEGER,
                FOREIGN KEY (loader_test10) REFERENCES loader_test10 (id10)
            ) $self->{innodb}
        },

        (q{ ALTER TABLE loader_test10 ADD CONSTRAINT } .
         q{ loader_test11_fk FOREIGN KEY (loader_test11) } .
         q{ REFERENCES loader_test11 (id11) }),
    );

    my @statements_inline_rels = (
        qq{
            CREATE TABLE loader_test12 (
                id INTEGER NOT NULL PRIMARY KEY,
                id2 VARCHAR(8) NOT NULL UNIQUE,
                dat VARCHAR(8) NOT NULL UNIQUE
            ) $self->{innodb}
        },

        q{ INSERT INTO loader_test12 (id,id2,dat) VALUES (1,'aaa','bbb') },

        qq{
            CREATE TABLE loader_test13 (
                id INTEGER NOT NULL PRIMARY KEY REFERENCES loader_test12,
                loader_test12 VARCHAR(8) NOT NULL REFERENCES loader_test12 (id2),
                dat VARCHAR(8) REFERENCES loader_test12 (dat)
            ) $self->{innodb}
        },

        (q{ INSERT INTO loader_test13 (id,loader_test12,dat) } .
         q{ VALUES (1,'aaa','bbb') }),
    );


    my @statements_implicit_rels = (
        qq{
            CREATE TABLE loader_test14 (
                id INTEGER NOT NULL PRIMARY KEY,
                dat VARCHAR(8)
            ) $self->{innodb}
        },
 
        q{ INSERT INTO loader_test14 (id,dat) VALUES (123,'aaa') },

        qq{
            CREATE TABLE loader_test15 (
                id INTEGER NOT NULL PRIMARY KEY,
                loader_test14 INTEGER NOT NULL,
                FOREIGN KEY (loader_test14) REFERENCES loader_test14
            ) $self->{innodb}
        },

        q{ INSERT INTO loader_test15 (id,loader_test14) VALUES (1,123) },
   );

    $self->drop_tables;

    $self->{created} = 1;

    my $dbh = $self->dbconnect(1);

    # Silence annoying but harmless postgres "NOTICE:  CREATE TABLE..."
    local $SIG{__WARN__} = sub {
        my $msg = shift;
        print STDERR $msg unless $msg =~ m{^NOTICE:\s+CREATE TABLE};
    };

    $dbh->do($_) for (@statements);
    unless($self->{skip_rels}) {
        # hack for now, since DB2 doesn't like inline comments, and we need
        # to test one for mysql, which works on everyone else...
        # this all needs to be refactored anyways.
        if($self->{vendor} =~ /DB2/i) {
            @statements_reltests = map { s/--.*\n//; $_ } @statements_reltests;
        }
        $dbh->do($_) for (@statements_reltests);
        unless($self->{vendor} =~ /sqlite/i) {
            $dbh->do($_) for (@statements_advanced);
        }
        unless($self->{no_inline_rels}) {
            $dbh->do($_) for (@statements_inline_rels);
        }
        unless($self->{no_implicit_rels}) {
            $dbh->do($_) for (@statements_implicit_rels);
        }
    }
    $dbh->disconnect();
}

sub drop_tables {
    my $self = shift;

    return unless $self->{created};

    my @tables = qw/
        loader_test1
        loader_test2
    /;

    my @tables_reltests = qw/
        loader_test4
        loader_test3
        loader_test6
        loader_test5
        loader_test8
        loader_test7
        loader_test9
    /;

    my @tables_advanced = qw/
        loader_test11
        loader_test10
    /;

    my @tables_inline_rels = qw/
        loader_test13
        loader_test12
    /;

    my @tables_implicit_rels = qw/
        loader_test15
        loader_test14
    /;

    my $drop_fk_mysql =
        q{ALTER TABLE loader_test10 DROP FOREIGN KEY loader_test11_fk;};

    my $drop_fk =
        q{ALTER TABLE loader_test10 DROP CONSTRAINT loader_test11_fk;};

    my $dbh = $self->dbconnect(0);

    unless($self->{skip_rels}) {
        $dbh->do("DROP TABLE $_") for (@tables_reltests);
        unless($self->{vendor} =~ /sqlite/i) {
            if($self->{vendor} =~ /mysql/i) {
                $dbh->do($drop_fk_mysql);
            }
            else {
                $dbh->do($drop_fk);
            }
            $dbh->do("DROP TABLE $_") for (@tables_advanced);
        }
        unless($self->{no_inline_rels}) {
            $dbh->do("DROP TABLE $_") for (@tables_inline_rels);
        }
        unless($self->{no_implicit_rels}) {
            $dbh->do("DROP TABLE $_") for (@tables_implicit_rels);
        }
    }
    $dbh->do("DROP TABLE $_") for (@tables);
    $dbh->disconnect;
}

sub DESTROY { shift->drop_tables; }

1;
