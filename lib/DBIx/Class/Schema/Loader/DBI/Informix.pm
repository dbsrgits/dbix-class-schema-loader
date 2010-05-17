package DBIx::Class::Schema::Loader::DBI::Informix;

use strict;
use warnings;
use Class::C3;
use base qw/DBIx::Class::Schema::Loader::DBI/;
use namespace::autoclean;
use Carp::Clan qw/^DBIx::Class/;
use Scalar::Util 'looks_like_number';

our $VERSION = '0.07000';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::Informix - DBIx::Class::Schema::Loader::DBI
Informix Implementation.

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader> and L<DBIx::Class::Schema::Loader::Base>.

=cut

sub _setup {
    my $self = shift;

    $self->next::method(@_);

    if (not defined $self->preserve_case) {
        $self->preserve_case(0);
    }
    elsif ($self->preserve_case) {
        $self->schema->storage->sql_maker->quote_char('"');
        $self->schema->storage->sql_maker->name_sep('.');
    }
}

sub _tables_list {
    my ($self, $opts) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(<<'EOF');
select tabname from systables t
where t.owner <> 'informix' and t.owner <> '' and t.tabname <> ' VERSION'
EOF
    $sth->execute;

    my @tables = map @$_, @{ $sth->fetchall_arrayref };

    return $self->_filter_tables(\@tables, $opts);
}

sub _constraints_for {
    my ($self, $table, $type) = @_;

    my $dbh = $self->schema->storage->dbh;
    local $dbh->{FetchHashKeyName} = 'NAME_lc';

    my $sth = $dbh->prepare(<<'EOF');
select c.constrname, i.*
from sysconstraints c
join systables t on t.tabid = c.tabid
join sysindexes i on c.idxname = i.idxname
where t.tabname = ? and c.constrtype = ?
EOF
    $sth->execute($table, $type);
    my $indexes = $sth->fetchall_hashref('constrname');
    $sth->finish;

    my $cols = $self->_colnames_by_colno($table);

    my $constraints;
    while (my ($constr_name, $idx_def) = each %$indexes) {
        $constraints->{$constr_name} = $self->_idx_colnames($idx_def, $cols);
    }

    return $constraints;
}

sub _idx_colnames {
    my ($self, $idx_info, $table_cols_by_colno) = @_;

    return [ map $self->_lc($table_cols_by_colno->{$_}), grep $_, map $idx_info->{$_}, map "part$_", (1..16) ];
}

sub _colnames_by_colno {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    local $dbh->{FetchHashKeyName} = 'NAME_lc';

    my $sth = $dbh->prepare(<<'EOF');
select c.colname, c.colno
from syscolumns c
join systables t on c.tabid = t.tabid
where t.tabname = ?
EOF
    $sth->execute($table);
    my $cols = $sth->fetchall_hashref('colno');
    $cols = { map +($_, $cols->{$_}{colname}), keys %$cols };

    return $cols;
}

sub _table_pk_info {
    my ($self, $table) = @_;

    my $pk = (values %{ $self->_constraints_for($table, 'P') || {} })[0];

    return $pk;
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my $constraints = $self->_constraints_for($table, 'U');

    my @uniqs = map { [ $_ => $constraints->{$_} ] } keys %$constraints;
    return \@uniqs;
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my $local_columns = $self->_constraints_for($table, 'R');

    my $dbh = $self->schema->storage->dbh;
    local $dbh->{FetchHashKeyName} = 'NAME_lc';

    my $sth = $dbh->prepare(<<'EOF');
select c.constrname local_constraint, rt.tabname remote_table, rc.constrname remote_constraint, ri.*
from sysconstraints c
join systables t on c.tabid = t.tabid
join sysreferences r on c.constrid = r.constrid
join sysconstraints rc on rc.constrid = r.primary
join systables rt on r.ptabid = rt.tabid
join sysindexes ri on rc.idxname = ri.idxname
where t.tabname = ? and c.constrtype = 'R'
EOF
    $sth->execute($table);
    my $remotes = $sth->fetchall_hashref('local_constraint');
    $sth->finish;

    my @rels;

    while (my ($local_constraint, $remote_info) = each %$remotes) {
        push @rels, {
            local_columns => $local_columns->{$local_constraint},
            remote_columns => $self->_idx_colnames($remote_info, $self->_colnames_by_colno($remote_info->{remote_table})),
            remote_table => $remote_info->{remote_table},
        };
    }

    return \@rels;
}

sub _columns_info_for {
    my $self = shift;
    my ($table) = @_;

    my $result = $self->next::method(@_);

    my $dbh = $self->schema->storage->dbh;
    local $dbh->{FetchHashKeyName} = 'NAME_lc';

    my $sth = $dbh->prepare(<<'EOF');
select c.colname, c.coltype, d.type deflt_type, d.default deflt
from syscolumns c
join systables t on c.tabid = t.tabid
left join sysdefaults d on t.tabid = d.tabid and c.colno = d.colno
where t.tabname = ?
EOF
    $sth->execute($table);
    my $cols = $sth->fetchall_hashref('colname');
    $sth->finish;

    while (my ($col, $info) = each %$cols) {
        my $type = $info->{coltype} % 256;

        if ($type == 6) { # SERIAL
            $result->{$col}{is_auto_increment} = 1;
        }

        if (looks_like_number $result->{$col}{data_type}) {
            if ($type == 7) {
                $result->{$col}{data_type} = 'date';
            }
            elsif ($type == 10) {
                $result->{$col}{data_type} = 'datetime year to fraction(5)';
            }
        }

        my ($default_type, $default) = @{$info}{qw/deflt_type deflt/};

        next unless $default_type;

        if ($default_type eq 'C') {
            my $current = 'CURRENT YEAR TO FRACTION(5)';
            $result->{$col}{default_value} = \$current;
        }
        elsif ($default_type eq 'T') {
            my $today = 'TODAY';
            $result->{$col}{default_value} = \$today;
        }
        else {
            $default = (split ' ', $default, 2)[-1];

            $default =~ s/\s+\z// if looks_like_number $default;

            # remove trailing 0s in floating point defaults
            # disabled, this is unsafe since it might be a varchar default
            #$default =~ s/0+\z// if $default =~ /^\d+\.\d+\z/;

            $result->{$col}{default_value} = $default;
        }
    }

    return $result;
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
