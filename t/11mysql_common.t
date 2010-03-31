use strict;
use lib qw(t/lib);
use dbixcsl_common_tests;
use Test::More;

my $dsn         = $ENV{DBICTEST_MYSQL_DSN} || '';
my $user        = $ENV{DBICTEST_MYSQL_USER} || '';
my $password    = $ENV{DBICTEST_MYSQL_PASS} || '';
my $test_innodb = $ENV{DBICTEST_MYSQL_INNODB} || 0;

my $skip_rels_msg = 'You need to set the DBICTEST_MYSQL_INNODB environment variable to test relationships';

my $tester = dbixcsl_common_tests->new(
    vendor           => 'Mysql',
    auto_inc_pk      => 'INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT',
    innodb           => $test_innodb ? q{Engine=InnoDB} : 0,
    dsn              => $dsn,
    user             => $user,
    password         => $password,
    connect_info_opts=> { on_connect_call => 'set_strict_mode' },
    skip_rels        => $test_innodb ? 0 : $skip_rels_msg,
    no_inline_rels   => 1,
    no_implicit_rels => 1,
    data_types  => {
        # http://dev.mysql.com/doc/refman/5.5/en/data-type-overview.html
        # Numeric Types
        'smallint '    => { data_type => 'SMALLINT',  size => 6  },   # Space in key makes column name smallint_
        'mediumint '   => { data_type => 'MEDIUMINT', size => 9  },   # to avoid MySQL reserved word.
        'int '         => { data_type => 'INT',       size => 11 },
        'integer '     => { data_type => 'INT',       size => 11 },
        'bigint '      => { data_type => 'BIGINT',    size => 20 },
        'serial '      => { data_type => 'BIGINT',    size => 20, is_auto_increment => 1, extra => {unsigned => 1} },
        'float '       => { data_type => 'FLOAT',     size => 32 },
        'double '      => { data_type => 'DOUBLE',    size => 64 },
        'double precision' =>
                        { data_type => 'DOUBLE',    size => 64 },
        'decimal '     => { data_type => 'DECIMAL',   size => 10 },
        'dec '         => { data_type => 'DECIMAL',   size => 10 },
        'fixed '       => { data_type => 'DECIMAL',   size => 10 },
        # Date and Time Types
        'date '        => { data_type => 'DATE',      size => 10 },
        'datetime '    => { data_type => 'DATETIME',  size => 19 },
        'timestamp '   => { data_type => 'TIMESTAMP', size => 14, default_value => \"CURRENT_TIMESTAMP" },
        'time '        => { data_type => 'TIME',      size => 8  },
        'year '        => { data_type => 'YEAR',      size => 4  },
        # String Types
        'char '        => { data_type => 'CHAR',      size => 1  },
        'varchar(20)'  => { data_type => 'VARCHAR',   size => 20 },
        'binary(1)'    => { data_type => 'BINARY',    size => 1 },
        'varbinary(1)' => { data_type => 'VARBINARY', size => 1 },
        'tinytext '    => { data_type => 'TINYTEXT',  size => 255 },
        'text '        => { data_type => 'TEXT',      size => 65535 },
        'longtext '    => { data_type => 'LONGTEXT',  size => 4294967295 },
        'tinyblob '    => { data_type => 'TINYBLOB',  size => 255 },
        'blob '        => { data_type => 'BLOB',      size => 65535 },
        'mediumblob '  => { data_type => 'MEDIUMBLOB',size => 16777215 },
        'longblob '    => { data_type => 'LONGBLOB',  size => 4294967295 },
        # Hmm... need some t/lib/dbixcsl_common_tests.pm hackery to get these working I think...
        # 'enum(1,2,3)'  => { data_type => 'ENUM',  size => 1 },
        # 'set(1,2,3)'   => { data_type => 'SET',  size => 1 },
    },
    extra            => {
        create => [
            qq{
                CREATE TABLE mysql_loader_test1 (
                    id INTEGER UNSIGNED NOT NULL PRIMARY KEY,
                    value ENUM('foo', 'bar', 'baz')
                )
            },
            qq{
                CREATE TABLE mysql_loader_test2 (
                  id INTEGER UNSIGNED NOT NULL PRIMARY KEY,
                  somets TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
            },
        ],
        drop   => [ qw/ mysql_loader_test1 mysql_loader_test2 / ],
        count  => 5,
        run    => sub {
            my ($schema, $monikers, $classes) = @_;
        
            my $rs = $schema->resultset($monikers->{mysql_loader_test1});
            my $column_info = $rs->result_source->column_info('id');
            
            is($column_info->{extra}->{unsigned}, 1, 'Unsigned MySQL columns');

            $column_info = $rs->result_source->column_info('value');

            like($column_info->{data_type}, qr/^enum$/i, 'MySQL ENUM type');
            is_deeply($column_info->{extra}->{list}, [qw/foo bar baz/],
                      'MySQL ENUM values');

            $rs = $schema->resultset($monikers->{mysql_loader_test2});
            $column_info = $rs->result_source->column_info('somets');
            my $default  = $column_info->{default_value};
            ok ((ref($default) eq 'SCALAR'),
                'CURRENT_TIMESTAMP default_value is a scalar ref');
            like $$default, qr/^CURRENT_TIMESTAMP\z/i,
                'CURRENT_TIMESTAMP default eq "CURRENT_TIMESTAMP"';
        },
    }
);

if( !$dsn || !$user ) {
    $tester->skip_tests('You need to set the DBICTEST_MYSQL_DSN, _USER, and _PASS environment variables');
}
else {
    $tester->run_tests();
}
