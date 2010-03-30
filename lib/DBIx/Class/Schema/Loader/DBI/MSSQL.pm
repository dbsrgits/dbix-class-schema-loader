package DBIx::Class::Schema::Loader::DBI::MSSQL;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI::Sybase::Common';
use Carp::Clan qw/^DBIx::Class/;
use Class::C3;

__PACKAGE__->mk_group_accessors('simple', qw/
    case_sensitive_collation
/);

our $VERSION = '0.06000';

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

If you are using FreeTDS with C<tds version> set to C<8.0> the collation
detection may fail, and Loader will default to case-insensitive mode. C<tds
version> C<7.0> will work fine.

If this happens set:

    case_sensitive_collation => 1

in your Loader options to override it.

=cut

sub _is_case_sensitive {
    my $self = shift;

    return $self->case_sensitive_collation ? 1 : 0;
}

sub _setup {
    my $self = shift;

    $self->next::method;

    return if defined $self->case_sensitive_collation;

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
        || eval { $dbh->selectrow_array("SELECT databasepropertyex(DB_NAME(), 'Collation')") };

    if (not $collation_name) {
        warn <<'EOF';

WARNING: MSSQL Collation detection failed. Defaulting to case-insensitive mode.
Override the 'case_sensitive_collation' attribute in your Loader options if
needed.
EOF
        $self->case_sensitive_collation(0);
        return;
    }

    my $case_sensitive = $collation_name =~ /_(?:CS|BIN2?)(?:_|\z)/;

    $self->case_sensitive_collation($case_sensitive ? 1 : 0);
}

sub _lc {
    my ($self, $name) = @_;

    return $self->case_sensitive_collation ? $name : lc($name);
}

sub _tables_list {
    my ($self, $opts) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(<<'EOF');
SELECT t.table_name
FROM INFORMATION_SCHEMA.TABLES t
WHERE lower(t.table_schema) = ?
EOF
    $sth->execute(lc $self->db_schema);

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
wHERE lower(ccu.table_name) = @{[ $dbh->quote(lc $table) ]} AND constraint_type = 'UNIQUE' ORDER BY kcu.ordinal_position
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

    while (my ($col, $info) = each %$result) {
        my $dbh = $self->schema->storage->dbh;

        my $sth = $dbh->prepare(qq{
SELECT column_name 
FROM INFORMATION_SCHEMA.COLUMNS
WHERE columnproperty(object_id(@{[ $dbh->quote(lc $table) ]}, 'U'), @{[ $dbh->quote(lc $col) ]}, 'IsIdentity') = 1
AND lower(table_name) = @{[ $dbh->quote(lc $table) ]} AND lower(column_name) = @{[ $dbh->quote(lc $col) ]}
        });
        if (eval { $sth->execute; $sth->fetchrow_array }) {
            $info->{is_auto_increment} = 1;
            $info->{data_type} =~ s/\s*identity//i;
            delete $info->{size};
        }

# get default
        $sth = $dbh->prepare(qq{
SELECT column_default
FROM INFORMATION_SCHEMA.COLUMNS
wHERE lower(table_name) = @{[ $dbh->quote(lc $table) ]} AND lower(column_name) = @{[ $dbh->quote(lc $col) ]}
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
