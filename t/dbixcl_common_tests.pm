package dbixcl_common_tests;

use strict;

use Test::More;
use DBIx::Class::Loader;
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

    plan tests => 26;

    $self->create();

    my $namespace = 'DBIXCL_Test_' . $self->{vendor};

    my $debug = ($self->{verbose} > 1) ? 1 : 0;

    my $loader = DBIx::Class::Loader->new(
         dsn           => $self->{dsn},
         user          => $self->{user},
         password      => $self->{password},
         namespace     => $namespace,
         constraint    => '^loader_test.*',
         relationships => 1,
         debug         => $debug,
    );

    my $conn = $loader->connect();

    my $moniker1 = $loader->moniker('loader_test1');
    my $rsobj1 = $conn->resultset($moniker1);
    my $moniker2 = $loader->moniker('loader_test2');
    my $rsobj2 = $conn->resultset($moniker2);

    isa_ok( $rsobj1, "DBIx::Class::ResultSet" );
    isa_ok( $rsobj2, "DBIx::Class::ResultSet" );

    my $obj    = $rsobj1->find(1);
    is( $obj->id,  1 );
    is( $obj->dat, "foo" );
    is( $rsobj2->count, 4 );

    my ($obj2) = $rsobj2->find( dat => 'bbb' );
    is( $obj2->id, 2 );

    SKIP: {
        skip $self->{skip_rels}, 20 if $self->{skip_rels};

        my $moniker3 = $loader->moniker('loader_test3');
        my $rsobj3 = $conn->resultset($moniker3);
        my $moniker4 = $loader->moniker('loader_test4');
        my $rsobj4 = $conn->resultset($moniker4);
        my $moniker5 = $loader->moniker('loader_test5');
        my $rsobj5 = $conn->resultset($moniker5);
        my $moniker6 = $loader->moniker('loader_test6');
        my $rsobj6 = $conn->resultset($moniker6);
        my $moniker7 = $loader->moniker('loader_test7');
        my $rsobj7 = $conn->resultset($moniker7);
        my $moniker8 = $loader->moniker('loader_test8');
        my $rsobj8 = $conn->resultset($moniker8);
        my $moniker9 = $loader->moniker('loader_test9');
        my $rsobj9 = $conn->resultset($moniker9);

        isa_ok( $rsobj3, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj4, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj5, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj6, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj7, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj8, "DBIx::Class::ResultSet" );
        isa_ok( $rsobj9, "DBIx::Class::ResultSet" );

        # basic rel test
        my $obj4 = $rsobj4->find(123);
        isa_ok( $obj4->fkid, "$namespace\::$moniker3");

        # fk def in comments should not be parsed
        my $obj5 = $rsobj5->find( id1 => 1, id2 => 1 );
        is( ref( $obj5->id2 ), '' );

        # mulit-col fk def (works for some, not others...)
        my $obj6 = $rsobj6->find(1);
        isa_ok( $obj6->loader_test2, "$namespace\::$moniker2" );
        SKIP: {
            skip "Multi-column FKs are only half-working for this vendor", 1
                unless $self->{multi_fk_broken};
            is( ref( $obj6->id2 ), '' );
        }

        # fk that references a non-pk key (UNIQUE)
        my $obj8 = $rsobj8->find(1);
        isa_ok( $obj8->loader_test7, "$namespace\::$moniker7" );

        # from Chisel's tests...
        SKIP: {
            if($self->{vendor} =~ /sqlite/i) {
                skip 'SQLite cannot do the advanced tests', 8;
            }

            my $moniker10 = $loader->moniker('loader_test10');
            my $rsobj10 = $conn->resultset($moniker10);
            my $moniker11 = $loader->moniker('loader_test11');
            my $rsobj11 = $conn->resultset($moniker11);

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
                isa_ok( $obj10_3, "$namespace\::$moniker10" );
                is( $obj10_3->loader_test11()->id(), $obj11->id(),
                    'found same $rsobj11 object we expected' );
            }
        }
    }
}

sub dbconnect {
    my ($self, $complain) = @_;

    DBI->connect(
         $self->{dsn}, $self->{user},
         $self->{password},
         {
             RaiseError => $complain,
             PrintError => $complain,
             AutoCommit => 1,
         }
    );
}

sub create {
    my $self = shift;

    my @statements = (
        qq{
            CREATE TABLE loader_test1 (
                id $self->{auto_inc_pk},
                dat VARCHAR(32)
            ) $self->{innodb};
        },

        q{ INSERT INTO loader_test1 (dat) VALUES('foo'); },
        q{ INSERT INTO loader_test1 (dat) VALUES('bar'); }, 
        q{ INSERT INTO loader_test1 (dat) VALUES('baz'); }, 

        qq{ 
            CREATE TABLE loader_test2 (
                id $self->{auto_inc_pk},
                dat VARCHAR(32)
            ) $self->{innodb};
        },

        q{ INSERT INTO loader_test2 (dat) VALUES('aaa'); }, 
        q{ INSERT INTO loader_test2 (dat) VALUES('bbb'); }, 
        q{ INSERT INTO loader_test2 (dat) VALUES('ccc'); }, 
        q{ INSERT INTO loader_test2 (dat) VALUES('ddd'); }, 
    );

    my @statements_reltests = (
        qq{
            CREATE TABLE loader_test3 (
                id INTEGER NOT NULL PRIMARY KEY,
                dat VARCHAR(32)
            ) $self->{innodb};
        },

        q{ INSERT INTO loader_test3 (id,dat) VALUES(1,'aaa'); }, 
        q{ INSERT INTO loader_test3 (id,dat) VALUES(2,'bbb'); }, 
        q{ INSERT INTO loader_test3 (id,dat) VALUES(3,'ccc'); }, 
        q{ INSERT INTO loader_test3 (id,dat) VALUES(4,'ddd'); }, 

        qq{
            CREATE TABLE loader_test4 (
                id INTEGER NOT NULL PRIMARY KEY,
                fkid INTEGER NOT NULL,
                dat VARCHAR(32),
                FOREIGN KEY (fkid) REFERENCES loader_test3 (id)
            ) $self->{innodb};
        },

        q{ INSERT INTO loader_test4 (id,fkid,dat) VALUES(123,1,'aaa'); },
        q{ INSERT INTO loader_test4 (id,fkid,dat) VALUES(124,2,'bbb'); }, 
        q{ INSERT INTO loader_test4 (id,fkid,dat) VALUES(125,3,'ccc'); },
        q{ INSERT INTO loader_test4 (id,fkid,dat) VALUES(126,4,'ddd'); },

        qq{
            CREATE TABLE loader_test5 (
                id1 INTEGER,
                id2 INTEGER, -- , id2 INTEGER REFERENCES loader_test1,
                dat TEXT,
                PRIMARY KEY (id1,id2)
            ) $self->{innodb};
        },

        q{ INSERT INTO loader_test5 (id1,id2,dat) VALUES (1,1,'aaa'); },

        qq{
            CREATE TABLE loader_test6 (
                id $self->{auto_inc_pk},
                id2 INTEGER,
                loader_test2 INTEGER,
                dat TEXT,
                FOREIGN KEY (loader_test2) REFERENCES loader_test2 (id),
                FOREIGN KEY (id, id2 ) REFERENCES loader_test5 (id1,id2)
            ) $self->{innodb};
        },

        (q{ INSERT INTO loader_test6 (id2,loader_test2,dat) } .
         q{ VALUES (1,1,'aaa'); }),

        qq{
            CREATE TABLE loader_test7 (
                id INTEGER NOT NULL PRIMARY KEY,
                id2 VARCHAR(8) NOT NULL UNIQUE,
                dat TEXT
            ) $self->{innodb};
        },

        q{ INSERT INTO loader_test7 (id,id2,dat) VALUES (1,'aaa','bbb'); },

        qq{
            CREATE TABLE loader_test8 (
                id INTEGER NOT NULL PRIMARY KEY,
                loader_test7 VARCHAR(8) NOT NULL,
                dat TEXT,
                FOREIGN KEY (loader_test7) REFERENCES loader_test7 (id2)
            ) $self->{innodb};
        },

        (q{ INSERT INTO loader_test8 (id,loader_test7,dat) } .
         q{ VALUES (1,'aaa','bbb'); }),

        qq{
            CREATE TABLE loader_test9 (
                loader_test9 TEXT NOT NULL
            ) $self->{innodb};
        },
    );

    my @statements_advanced = (
        qq{
            CREATE TABLE loader_test10 (
                id10 $self->{auto_inc_pk},
                subject VARCHAR(8),
                loader_test11 INTEGER
            ) $self->{innodb};
        },

        qq{
            CREATE TABLE loader_test11 (
                id11 $self->{auto_inc_pk},
                message VARCHAR(8) DEFAULT 'foo',
                loader_test10 INTEGER NOT NULL,
                FOREIGN KEY (loader_test10) REFERENCES loader_test10 (id10)
            ) $self->{innodb};
        },

        (q{ ALTER TABLE loader_test10 ADD CONSTRAINT } .
         q{ loader_test11_fk FOREIGN KEY (loader_test11) } .
         q{ REFERENCES loader_test11 (id11); }),
    );

    $self->{created} = 1;

    my $dbh = $self->dbconnect(1);
    $dbh->do($_) for (@statements);
    unless($self->{skip_rels}) {
        $dbh->do($_) for (@statements_reltests);
        unless($self->{vendor} =~ /sqlite/i) {
            $dbh->do($_) for (@statements_advanced);
        }
    }
    $dbh->disconnect();
}

sub DESTROY {
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
    }
    $dbh->do("DROP TABLE $_") for (@tables);
    $dbh->disconnect();
}

1;
