package DBIx::Class::Schema::Loader::DBI::MSSQL;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI::Sybase::Common';
use mro 'c3';
use Carp::Clan qw/^DBIx::Class/;
use Try::Tiny;
use namespace::clean;

our $VERSION = '0.07010';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::MSSQL - DBIx::Class::Schema::Loader::DBI MSSQL Implementation.

=head1 DESCRIPTION

Base driver for Microsoft SQL Server, used by
L<DBIx::Class::Schema::Loader::DBI::Sybase::Microsoft_SQL_Server> for support
via L<DBD::Sybase> and
L<DBIx::Class::Schema::Loader::DBI::ODBC::Microsoft_SQL_Server> for support via
L<DBD::ODBC>.

See L<DBIx::Class::Schema::Loader> and L<DBIx::Class::Schema::Loader::Base> for
usage information.

=head1 CASE SENSITIVITY

Most MSSQL databases use C<CI> (case-insensitive) collation, for this reason
generated column names are lower-cased as this makes them easier to work with
in L<DBIx::Class>.

We attempt to detect the database collation at startup, and set the column
lowercasing behavior accordingly, as lower-cased column names do not work on
case-sensitive databases.

To manually control case-sensitive mode, put:

    preserve_case => 1|0

in your Loader options.

See L<preserve_case|DBIx::Class::Schema::Loader::Base/preserve_case>.

B<NOTE:> this option used to be called C<case_sensitive_collation>, but has
been renamed to a more generic option.

=cut

sub _setup {
    my $self = shift;

    $self->next::method(@_);

    return if defined $self->preserve_case;

    my $dbh = $self->schema->storage->dbh;

    # We use the sys.databases query for the general case, and fallback to
    # databasepropertyex() if for some reason sys.databases is not available,
    # which does not work over DBD::ODBC with unixODBC+FreeTDS.
    #
    # XXX why does databasepropertyex() not work over DBD::ODBC ?
    #
    # more on collations here: http://msdn.microsoft.com/en-us/library/ms143515.aspx
    my ($collation_name) =
           eval { $dbh->selectrow_array('SELECT collation_name FROM sys.databases WHERE name = DB_NAME()') }
        || eval { $dbh->selectrow_array("SELECT CAST(databasepropertyex(DB_NAME(), 'Collation') AS VARCHAR)") };

    if (not $collation_name) {
        warn <<'EOF';

WARNING: MSSQL Collation detection failed. Defaulting to case-insensitive mode.
Override the 'preserve_case' attribute in your Loader options if needed.

See 'preserve_case' in
perldoc DBIx::Class::Schema::Loader::Base
EOF
        $self->preserve_case(0);
        return;
    }

    my $case_sensitive = $collation_name =~ /_(?:CS|BIN2?)(?:_|\z)/;

    $self->preserve_case($case_sensitive ? 1 : 0);
}

sub _tables_list {
    my ($self, $opts) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(<<'EOF');
SELECT t.table_name
FROM INFORMATION_SCHEMA.TABLES t
WHERE t.table_schema = ?
EOF
    $sth->execute($self->db_schema);

    my @tables = map @$_, @{ $sth->fetchall_arrayref };

    return $self->_filter_tables(\@tables, $opts);
}

sub _table_pk_info {
    my ($self, $table) = @_;
    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{sp_pkeys '$table'});
    $sth->execute;

    my @keydata;

    while (my $row = $sth->fetchrow_hashref) {
        push @keydata, $self->_lc($row->{COLUMN_NAME});
    }

    return \@keydata;
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my ($local_cols, $remote_cols, $remote_table, @rels, $sth);
    my $dbh = $self->schema->storage->dbh;
    eval {
        $sth = $dbh->prepare(qq{sp_fkeys \@fktable_name = '$table'});
        $sth->execute;
    };

    while (my $row = eval { $sth->fetchrow_hashref }) {
        my $fk = $row->{FK_NAME};
        push @{$local_cols->{$fk}}, $self->_lc($row->{FKCOLUMN_NAME});
        push @{$remote_cols->{$fk}}, $self->_lc($row->{PKCOLUMN_NAME});
        $remote_table->{$fk} = $row->{PKTABLE_NAME};
    }

    foreach my $fk (keys %$remote_table) {
        push @rels, {
                      local_columns => \@{$local_cols->{$fk}},
                      remote_columns => \@{$remote_cols->{$fk}},
                      remote_table => $remote_table->{$fk},
                    };

    }
    return \@rels;
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    local $dbh->{FetchHashKeyName} = 'NAME_lc';

    my $sth = $dbh->prepare(qq{
SELECT ccu.constraint_name, ccu.column_name
FROM INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu
JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc on (ccu.constraint_name = tc.constraint_name)
JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu on (ccu.constraint_name = kcu.constraint_name and ccu.column_name = kcu.column_name)
wHERE ccu.table_name = @{[ $dbh->quote($table) ]} AND constraint_type = 'UNIQUE' ORDER BY kcu.ordinal_position
    });
    $sth->execute;
    my $constraints;
    while (my $row = $sth->fetchrow_hashref) {
        my $name = $row->{constraint_name};
        my $col  = $self->_lc($row->{column_name});
        push @{$constraints->{$name}}, $col;
    }

    my @uniqs = map { [ $_ => $constraints->{$_} ] } keys %$constraints;
    return \@uniqs;
}

sub _columns_info_for {
    my $self    = shift;
    my ($table) = @_;

    my $result = $self->next::method(@_);

    my $dbh = $self->schema->storage->dbh;

    while (my ($col, $info) = each %$result) {
# get type info
        my $sth = $dbh->prepare(qq{
SELECT character_maximum_length, data_type, datetime_precision
FROM INFORMATION_SCHEMA.COLUMNS
WHERE table_name = @{[ $dbh->quote($table) ]} AND column_name = @{[ $dbh->quote($col) ]}
        });
        $sth->execute;
        my ($char_max_length, $data_type, $datetime_precision) = $sth->fetchrow_array;

        $info->{data_type} = $data_type;

        if (defined $char_max_length) {
            $info->{size} = $char_max_length;
            $info->{size} = 0 if $char_max_length < 0;
        }

# find identities
        $sth = $dbh->prepare(qq{
SELECT column_name 
FROM INFORMATION_SCHEMA.COLUMNS
WHERE columnproperty(object_id(@{[ $dbh->quote($table) ]}, 'U'), @{[ $dbh->quote($col) ]}, 'IsIdentity') = 1
AND table_name = @{[ $dbh->quote($table) ]} AND column_name = @{[ $dbh->quote($col) ]}
        });
        if (try { $sth->execute; $sth->fetchrow_array }) {
            $info->{is_auto_increment} = 1;
            $info->{data_type} =~ s/\s*identity//i;
            delete $info->{size};
        }

# fix types
        if ($data_type eq 'int') {
            $info->{data_type} = 'integer';
        }
        elsif ($data_type eq 'timestamp') {
            $info->{inflate_datetime} = 0;
        }
        elsif ($data_type =~ /^(?:numeric|decimal)\z/) {
            if (ref($info->{size}) && $info->{size}[0] == 18 && $info->{size}[1] == 0) {
                delete $info->{size};
            }
        }
        elsif ($data_type eq 'float') {
            $info->{data_type} = 'double precision';
            delete $info->{size};
        }
        elsif ($data_type =~ /^(?:small)?datetime\z/) {
            # fixup for DBD::Sybase
            if ($info->{default_value} && $info->{default_value} eq '3') {
                delete $info->{default_value};
            }
        }
        elsif ($data_type =~ /^(?:datetime(?:2|offset)|time)\z/) {
            $info->{size} = $datetime_precision;

            delete $info->{size} if $info->{size} == 7;
        }
        elsif ($data_type eq 'varchar'   && $info->{size} == 0) {
            $info->{data_type} = 'text';
            delete $info->{size};
        }
        elsif ($data_type eq 'nvarchar'  && $info->{size} == 0) {
            $info->{data_type} = 'ntext';
            delete $info->{size};
        }
        elsif ($data_type eq 'varbinary' && $info->{size} == 0) {
            $info->{data_type} = 'image';
            delete $info->{size};
        }

        if ($data_type !~ /^(?:n?char|n?varchar|binary|varbinary|numeric|decimal|float|datetime(?:2|offset)|time)\z/) {
            delete $info->{size};
        }

# get default
        $sth = $dbh->prepare(qq{
SELECT column_default
FROM INFORMATION_SCHEMA.COLUMNS
wHERE table_name = @{[ $dbh->quote($table) ]} AND column_name = @{[ $dbh->quote($col) ]}
        });
        my ($default) = eval { $sth->execute; $sth->fetchrow_array };

        if (defined $default) {
            # strip parens
            $default =~ s/^\( (.*) \)\z/$1/x;

            # Literal strings are in ''s, numbers are in ()s (in some versions of
            # MSSQL, in others they are unquoted) everything else is a function.
            $info->{default_value} =
                $default =~ /^['(] (.*) [)']\z/x ? $1 :
                    $default =~ /^\d/ ? $default : \$default;

            if ((eval { lc ${ $info->{default_value} } }||'') eq 'getdate()') {
                ${ $info->{default_value} } = 'current_timestamp';

                my $getdate = 'getdate()';
                $info->{original}{default_value} = \$getdate;
            }
        }
    }

    return $result;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader::DBI::Sybase::Microsoft_SQL_Server>,
L<DBIx::Class::Schema::Loader::DBI::ODBC::Microsoft_SQL_Server>,
L<DBIx::Class::Schema::Loader>, L<DBIx::Class::Schema::Loader::Base>,
L<DBIx::Class::Schema::Loader::DBI>

=head1 AUTHOR

See L<DBIx::Class::Schema::Loader/AUTHOR> and L<DBIx::Class::Schema::Loader/CONTRIBUTORS>.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
# vim:et sts=4 sw=4 tw=0:
