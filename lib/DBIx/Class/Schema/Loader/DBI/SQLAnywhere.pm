package DBIx::Class::Schema::Loader::DBI::SQLAnywhere;

use strict;
use warnings;
use mro 'c3';
use base qw/
    DBIx::Class::Schema::Loader::DBI::Component::QuotedDefault
    DBIx::Class::Schema::Loader::DBI
/;
use Carp::Clan qw/^DBIx::Class/;

our $VERSION = '0.07010';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::SQLAnywhere - DBIx::Class::Schema::Loader::DBI
SQL Anywhere Implementation.

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader> and L<DBIx::Class::Schema::Loader::Base>.

=cut

sub _setup {
    my $self = shift;

    $self->next::method(@_);

    $self->{db_schema} ||=
        ($self->schema->storage->dbh->selectrow_array('select user'))[0];
}

sub _tables_list {
    my ($self, $opts) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(<<'EOF');
select t.table_name from systab t
join sysuser u on u.user_id = t.creator
where u.user_name = ?
EOF
    $sth->execute($self->db_schema);

    my @tables = map @$_, @{ $sth->fetchall_arrayref };

    return $self->_filter_tables(\@tables, $opts);
}

sub _columns_info_for {
    my $self    = shift;
    my ($table) = @_;

    my $result = $self->next::method(@_);

    my $dbh = $self->schema->storage->dbh;

    while (my ($col, $info) = each %$result) {
        my $def = $info->{default_value};
        if (ref $def eq 'SCALAR' && $$def eq 'autoincrement') {
            delete $info->{default_value};
            $info->{is_auto_increment} = 1;
        }

        my ($user_type) = $dbh->selectrow_array(<<'EOF', {}, $table, $col);
SELECT ut.type_name
FROM systabcol tc
JOIN systab t ON tc.table_id = t.table_id
JOIN sysusertype ut on tc.user_type = ut.type_id
WHERE t.table_name = ? AND lower(tc.column_name) = ?
EOF
        $info->{data_type} = $user_type if defined $user_type;

        if ($info->{data_type} eq 'double') {
            $info->{data_type} = 'double precision';
        }

        if ($info->{data_type} =~ /^(?:char|varchar|binary|varbinary)\z/ && ref($info->{size}) eq 'ARRAY') {
            $info->{size} = $info->{size}[0];
        }
        elsif ($info->{data_type} !~ /^(?:char|varchar|binary|varbinary|numeric|decimal)\z/) {
            delete $info->{size};
        }

        my $sth = $dbh->prepare(<<'EOF');
SELECT tc.width, tc.scale
FROM systabcol tc
JOIN systab t ON t.table_id = tc.table_id
WHERE t.table_name = ? AND tc.column_name = ?
EOF
        $sth->execute($table, $col);
        my ($width, $scale) = $sth->fetchrow_array;
        $sth->finish;

        if ($info->{data_type} =~ /^(?:numeric|decimal)\z/) {
            # We do not check for the default precision/scale, because they can be changed as PUBLIC database options.
            $info->{size} = [$width, $scale];
        }
        elsif ($info->{data_type} =~ /^(?:n(?:varchar|char) | varbit)\z/x) {
            $info->{size} = $width;
        }
        elsif ($info->{data_type} eq 'float') {
            $info->{data_type} = 'real';
        }

        delete $info->{default_value} if ref($info->{default_value}) eq 'SCALAR' && ${ $info->{default_value} } eq 'NULL';

        if ((eval { lc ${ $info->{default_value} } }||'') eq 'current timestamp') {
            ${ $info->{default_value} } = 'current_timestamp';

            my $orig_deflt = 'current timestamp';
            $info->{original}{default_value} = \$orig_deflt;
        }
    }

    return $result;
}

sub _table_pk_info {
    my ($self, $table) = @_;
    my $dbh = $self->schema->storage->dbh;
    local $dbh->{FetchHashKeyName} = 'NAME_lc';
    my $sth = $dbh->prepare(qq{sp_pkeys ?});
    $sth->execute($table);

    my @keydata;

    while (my $row = $sth->fetchrow_hashref) {
        push @keydata, $self->_lc($row->{column_name});
    }

    return \@keydata;
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my ($local_cols, $remote_cols, $remote_table, @rels);
    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(<<'EOF');
select fki.index_name fk_name, fktc.column_name local_column, pkt.table_name remote_table, pktc.column_name remote_column
from sysfkey fk
join systab    pkt  on fk.primary_table_id = pkt.table_id
join systab    fkt  on fk.foreign_table_id = fkt.table_id
join sysidx    pki  on fk.primary_table_id = pki.table_id  and fk.primary_index_id    = pki.index_id
join sysidx    fki  on fk.foreign_table_id = fki.table_id  and fk.foreign_index_id    = fki.index_id
join sysidxcol fkic on fkt.table_id        = fkic.table_id and fki.index_id           = fkic.index_id
join systabcol pktc on pkt.table_id        = pktc.table_id and fkic.primary_column_id = pktc.column_id
join systabcol fktc on fkt.table_id        = fktc.table_id and fkic.column_id         = fktc.column_id
where fkt.table_name = ?
EOF
    $sth->execute($table);

    while (my ($fk, $local_col, $remote_tab, $remote_col) = $sth->fetchrow_array) {
        push @{$local_cols->{$fk}},  $self->_lc($local_col);
        push @{$remote_cols->{$fk}}, $self->_lc($remote_col);
        $remote_table->{$fk} = $remote_tab;
    }

    foreach my $fk (keys %$remote_table) {
        push @rels, {
            local_columns => $local_cols->{$fk},
            remote_columns => $remote_cols->{$fk},
            remote_table => $remote_table->{$fk},
        };
    }
    return \@rels;
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(<<'EOF');
select c.constraint_name, tc.column_name
from sysconstraint c
join systab t on c.table_object_id = t.object_id
join sysidx i on c.ref_object_id = i.object_id
join sysidxcol ic on i.table_id = ic.table_id and i.index_id = ic.index_id
join systabcol tc on ic.table_id = tc.table_id and ic.column_id = tc.column_id
where c.constraint_type = 'U' and t.table_name = ?
EOF
    $sth->execute($table);

    my $constraints;
    while (my ($constraint_name, $column) = $sth->fetchrow_array) {
        push @{$constraints->{$constraint_name}}, $self->_lc($column);
    }

    my @uniqs = map { [ $_ => $constraints->{$_} ] } keys %$constraints;
    return \@uniqs;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>, L<DBIx::Class::Schema::Loader::Base>,
L<DBIx::Class::Schema::Loader::DBI>

=head1 AUTHOR

See L<DBIx::Class::Schema::Loader/AUTHOR> and L<DBIx::Class::Schema::Loader/CONTRIBUTORS>.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
# vim:et sw=4 sts=4 tw=0:
