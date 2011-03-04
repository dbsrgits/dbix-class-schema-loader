package DBIx::Class::Schema::Loader::DBI::Sybase;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI::Sybase::Common';
use Carp::Clan qw/^DBIx::Class/;
use mro 'c3';

our $VERSION = '0.07010';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::Sybase - DBIx::Class::Schema::Loader::DBI
Sybase ASE Implementation.

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader> and L<DBIx::Class::Schema::Loader::Base>.

=cut

sub _setup {
    my $self = shift;

    $self->next::method(@_);

    if (not defined $self->preserve_case) {
        $self->preserve_case(1);
    }
}

sub _rebless {
    my $self = shift;

    my $dbh = $self->schema->storage->dbh;
    my $DBMS_VERSION = @{$dbh->selectrow_arrayref(qq{sp_server_info \@attribute_id=1})}[2];
    if ($DBMS_VERSION =~ /^Microsoft /i) {
        $DBMS_VERSION =~ s/\s/_/g;
        my $subclass = "DBIx::Class::Schema::Loader::DBI::Sybase::$DBMS_VERSION";
        if ($self->load_optional_class($subclass) && !$self->isa($subclass)) {
            bless $self, $subclass;
            $self->_rebless;
      }
    }
}

sub _tables_list {
    my ($self, $opts) = @_;

    my $dbh = $self->schema->storage->dbh;

    my $sth = $dbh->table_info(undef, $self->db_schema, undef, "'TABLE','VIEW'");

    my @tables = grep $_ ne 'sysquerymetrics',
              map $_->{table_name}, @{ $sth->fetchall_arrayref({ table_name => 1 }) };

    return $self->_filter_tables(\@tables, $opts);
}

sub _table_columns {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $columns = $dbh->selectcol_arrayref(qq{
SELECT c.name
FROM syscolumns c JOIN sysobjects o
ON c.id = o.id
WHERE o.name = @{[ $dbh->quote($table) ]} AND o.type = 'U'
});

    return $columns;
}

sub _table_pk_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{sp_pkeys @{[ $dbh->quote($table) ]}});
    $sth->execute;

    my @keydata;

    while (my $row = $sth->fetchrow_hashref) {
        push @keydata, $row->{column_name};
    }

    return \@keydata;
}

sub _table_fk_info {
    my ($self, $table) = @_;

    # check if FK_NAME is supported

    my $dbh = $self->schema->storage->dbh;
    local $dbh->{FetchHashKeyName} = 'NAME_lc';
    # hide "Object does not exist in this database." when trying to fetch fkeys
    local $dbh->{syb_err_handler} = sub { return $_[0] == 17461 ? 0 : 1 }; 
    my $sth = $dbh->prepare(qq{sp_fkeys \@fktable_name = @{[ $dbh->quote($table) ]}});
    $sth->execute;
    my $row = $sth->fetchrow_hashref;

    return unless $row;

    if (exists $row->{fk_name}) {
        $sth->finish;
        return $self->_table_fk_info_by_name($table);
    }

    $sth->finish;
    return $self->_table_fk_info_builder($table);
}

sub _table_fk_info_by_name {
    my ($self, $table) = @_;
    my ($local_cols, $remote_cols, $remote_table, @rels);

    my $dbh = $self->schema->storage->dbh;
    local $dbh->{FetchHashKeyName} = 'NAME_lc';
    # hide "Object does not exist in this database." when trying to fetch fkeys
    local $dbh->{syb_err_handler} = sub { return $_[0] == 17461 ? 0 : 1 }; 
    my $sth = $dbh->prepare(qq{sp_fkeys \@fktable_name = @{[ $dbh->quote($table) ]}});
    $sth->execute;

    while (my $row = $sth->fetchrow_hashref) {
        my $fk = $row->{fk_name};
        next unless defined $fk;

        push @{$local_cols->{$fk}}, $row->{fkcolumn_name};
        push @{$remote_cols->{$fk}}, $row->{pkcolumn_name};
        $remote_table->{$fk} = $row->{pktable_name};
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

sub _table_fk_info_builder {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    local $dbh->{FetchHashKeyName} = 'NAME_lc';
    # hide "Object does not exist in this database." when trying to fetch fkeys
    local $dbh->{syb_err_handler} = sub { return 0 if $_[0] == 17461; }; 
    my $sth = $dbh->prepare(qq{sp_fkeys \@fktable_name = @{[ $dbh->quote($table) ]}});
    $sth->execute;

    my @fk_info;
    while (my $row = $sth->fetchrow_hashref) {
        (my $ksq = $row->{key_seq}) =~ s/\s+//g;

        my @keys = qw/pktable_name pkcolumn_name fktable_name fkcolumn_name/;
        my %ds;
        @ds{@keys}   = @{$row}{@keys};
        $ds{key_seq} = $ksq;

        push @{ $fk_info[$ksq] }, \%ds;
    }

    my $max_keys = $#fk_info;
    my @rels;
    for my $level (reverse 1 .. $max_keys) {
        my @level_rels;
        $level_rels[$level] = splice @fk_info, $level, 1;
        my $count = @{ $level_rels[$level] };

        for my $sub_level (reverse 1 .. $level-1) {
            my $total = @{ $fk_info[$sub_level] };

            $level_rels[$sub_level] = [
                splice @{ $fk_info[$sub_level] }, $total-$count, $count
            ];
        }

        while (1) {
            my @rel = map shift @$_, @level_rels[1..$level];

            last unless defined $rel[0];

            my @local_columns  = map $_->{fkcolumn_name}, @rel;
            my @remote_columns = map $_->{pkcolumn_name}, @rel;
            my $remote_table   = $rel[0]->{pktable_name};

            push @rels, {
                local_columns => \@local_columns,
                remote_columns => \@remote_columns,
                remote_table => $remote_table
            };
        }
    }

    return \@rels;
}

sub _table_uniq_info {
    no warnings 'uninitialized'; # for presumably XS weirdness with null operations
    my ($self, $table) = @_;

    local $SIG{__WARN__} = sub { warn @_
        unless $_[0] =~ /^Formula for Calculation:|^(?:--?|\+|=) Number of (?:self )?references|^Total Number of Referential Constraints|^Details:|^\s*$/ };

    my $dbh = $self->schema->storage->dbh;
    local $dbh->{FetchHashKeyName} = 'NAME_lc';
    my $sth = $dbh->prepare(qq{sp_helpconstraint \@objname=@{[ $dbh->quote($table) ]}, \@nomsg='nomsg'});
    eval { $sth->execute };
    return if $@;

    my $constraints;
    while (my $row = $sth->fetchrow_hashref) {
        if (exists $row->{constraint_type}) {
            my $type = $row->{constraint_type} || '';
            if ($type =~ /^unique/i) {
                my $name = $row->{constraint_name};
                push @{$constraints->{$name}},
                    ( split /,/, $row->{constraint_keys} );
            }
        } else {
            my $def = $row->{definition} || next;
            next unless $def =~ /^unique/i;
            my $name = $row->{name};
            my ($keys) = $def =~ /\((.*)\)/;
            $keys =~ s/\s*//g;
            my @keys = split /,/ => $keys;
            push @{$constraints->{$name}}, @keys;
        }
    }

    my @uniqs = map { [ $_ => $constraints->{$_} ] } keys %$constraints;
    return \@uniqs;
}

# get the correct data types, defaults and size
sub _columns_info_for {
    my $self    = shift;
    my ($table) = @_;
    my $result  = $self->next::method(@_);

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{
SELECT c.name name, bt.name base_type, ut.name user_type, cm.text deflt, c.prec prec, c.scale scale, c.length len
FROM syscolumns c
JOIN sysobjects o ON c.id = o.id
LEFT JOIN systypes bt ON c.type     = bt.type 
LEFT JOIN systypes ut ON c.usertype = ut.usertype
LEFT JOIN syscomments cm
    ON cm.id = CASE WHEN c.cdefault = 0 THEN c.computedcol ELSE c.cdefault END
WHERE o.name = @{[ $dbh->quote($table) ]} AND o.type = 'U'
});
    $sth->execute;
    local $dbh->{FetchHashKeyName} = 'NAME_lc';
    my $info = $sth->fetchall_hashref('name');

    while (my ($col, $res) = each %$result) {
        my $data_type = $res->{data_type} = $info->{$col}{user_type} || $info->{$col}{base_type};

        if ($data_type && $data_type =~ /^timestamp\z/i) {
            $res->{inflate_datetime} = 0;
        }

        if (my $default = $info->{$col}{deflt}) {
            if ($default =~ /^AS \s+ (\S+)/ix) {
                my $function = $1;
                $res->{default_value} = \$function;

                if ($function =~ /^getdate\b/) {
                    $res->{inflate_datetime} = 1;
                }

                delete $res->{size};
                $res->{data_type} = undef;
            }
            elsif ($default =~ /^DEFAULT \s+ (\S+)/ix) {
                my ($constant_default) = $1 =~ /^['"\[\]]?(.*?)['"\[\]]?\z/;
                $res->{default_value} = $constant_default;
            }
        }

        if (my $data_type = $res->{data_type}) {
            if ($data_type eq 'int') {
                $data_type = $res->{data_type} = 'integer';
            }
            elsif ($data_type eq 'decimal') {
                $data_type = $res->{data_type} = 'numeric';
            }

            if ($data_type =~ /^(?:text|unitext|image|bigint|integer|smallint|tinyint|real|double|double precision|float|date|time|datetime|smalldatetime|money|smallmoney|timestamp|bit)\z/i) {
                delete $res->{size};
            }
            elsif ($data_type eq 'numeric') {
                my ($prec, $scale) = @{$info->{$col}}{qw/prec scale/};

                if ($prec == 18 && $scale == 0) {
                    delete $res->{size};
                }
                else {
                    $res->{size} = [ $prec, $scale ];
                }
            }
            elsif ($data_type =~ /^(?:unichar|univarchar)\z/i) {
                $res->{size} /= 2;
            }
        }

        if ($data_type eq 'float') {
            $res->{data_type} = $info->{$col}{len} <= 4 ? 'real' : 'double precision';
        }
    }

    return $result;
}

sub _extra_column_info {
    my ($self, $table, $column, $info, $dbi_info) = @_;
    my %extra_info;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{SELECT name FROM syscolumns WHERE id = (SELECT id FROM sysobjects WHERE name = @{[ $dbh->quote($table) ]}) AND (status & 0x80) = 0x80 AND name = @{[ $dbh->quote($column) ]}});
    $sth->execute();

    if ($sth->fetchrow_array) {
        $extra_info{is_auto_increment} = 1;
    }

    return \%extra_info;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader::DBI::Sybase::Common>,
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
