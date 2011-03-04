package DBIx::Class::Schema::Loader::DBI::Oracle;

use strict;
use warnings;
use base qw/
    DBIx::Class::Schema::Loader::DBI::Component::QuotedDefault
    DBIx::Class::Schema::Loader::DBI
/;
use Carp::Clan qw/^DBIx::Class/;
use mro 'c3';

our $VERSION = '0.07010';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::Oracle - DBIx::Class::Schema::Loader::DBI 
Oracle Implementation.

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader::Base>.

=cut

sub _setup {
    my $self = shift;

    $self->next::method(@_);

    my $dbh = $self->schema->storage->dbh;

    my ($current_schema) = $dbh->selectrow_array('SELECT USER FROM DUAL', {});

    $self->{db_schema} ||= $current_schema;

    if (lc($self->db_schema) ne lc($current_schema)) {
        $dbh->do('ALTER SESSION SET current_schema=' . $self->db_schema);
    }

    if (not defined $self->preserve_case) {
        $self->preserve_case(0);
    }
    elsif ($self->preserve_case) {
        $self->schema->storage->sql_maker->quote_char('"');
        $self->schema->storage->sql_maker->name_sep('.');
    }
}

sub _table_as_sql {
    my ($self, $table) = @_;

    return $self->_quote_table_name($table);
}

sub _tables_list { 
    my ($self, $opts) = @_;

    my $dbh = $self->schema->storage->dbh;

    my @tables;
    for my $table ( $dbh->tables(undef, $self->db_schema, '%', 'TABLE,VIEW') ) { #catalog, schema, table, type
        my $quoter = $dbh->get_info(29);
        $table =~ s/$quoter//g;

        # remove "user." (schema) prefixes
        $table =~ s/\w+\.//;

        next if $table eq 'PLAN_TABLE';
        $table = $self->_lc($table);
        push @tables, $1
          if $table =~ /\A(\w+)\z/;
    }

    {
        # silence a warning from older DBD::Oracles in tests
        my $warn_handler = $SIG{__WARN__} || sub { warn @_ };
        local $SIG{__WARN__} = sub {
            $warn_handler->(@_)
            unless $_[0] =~ /^Field \d+ has an Oracle type \(\d+\) which is not explicitly supported/;
        };

        return $self->_filter_tables(\@tables, $opts);
    }
}

sub _table_columns {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;

    my $sth = $dbh->column_info(undef, $self->db_schema, $self->_uc($table), '%');

    return [ map $self->_lc($_->{COLUMN_NAME}), @{ $sth->fetchall_arrayref({ COLUMN_NAME => 1 }) || [] } ];
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;

    my $sth = $dbh->prepare_cached(
        q{
            SELECT constraint_name, acc.column_name
            FROM all_constraints JOIN all_cons_columns acc USING (constraint_name)
            WHERE acc.table_name=? and acc.owner = ? AND constraint_type='U'
            ORDER BY acc.position
        },
        {}, 1);

    $sth->execute($self->_uc($table),$self->{db_schema} );
    my %constr_names;
    while(my $constr = $sth->fetchrow_arrayref) {
        my $constr_name = $self->_lc($constr->[0]);
        my $constr_col  = $self->_lc($constr->[1]);
        $constr_name =~ s/\Q$self->{_quoter}\E//;
        $constr_col  =~ s/\Q$self->{_quoter}\E//;
        push @{$constr_names{$constr_name}}, $constr_col;
    }
    
    my @uniqs = map { [ $_ => $constr_names{$_} ] } keys %constr_names;
    return \@uniqs;
}

sub _table_comment {
    my ( $self, $table ) = @_;
     my ($table_comment) = $self->schema->storage->dbh->selectrow_array(
        q{
            SELECT comments FROM all_tab_comments
            WHERE owner = ? 
              AND table_name = ?
              AND table_type = 'TABLE'
        }, undef, $self->db_schema, $self->_uc($table)
    );

    return $table_comment
}

sub _column_comment {
    my ( $self, $table, $column_number, $column_name ) = @_;
    my ($column_comment) = $self->schema->storage->dbh->selectrow_array(
        q{
            SELECT comments FROM all_col_comments
            WHERE owner = ? 
              AND table_name = ?
              AND column_name = ?
        }, undef, $self->db_schema, $self->_uc( $table ), $self->_uc( $column_name )
    );
    return $column_comment
}

sub _table_pk_info {
    my ($self, $table) = (shift, shift);

    return $self->next::method($self->_uc($table), @_);
}

sub _table_fk_info {
    my ($self, $table) = (shift, shift);

    my $rels = $self->next::method($self->_uc($table), @_);

    foreach my $rel (@$rels) {
        $rel->{remote_table} = $self->_lc($rel->{remote_table});
    }

    return $rels;
}

sub _columns_info_for {
    my ($self, $table) = (shift, shift);

    my $result = $self->next::method($self->_uc($table), @_);

    my $dbh = $self->schema->storage->dbh;

    local $dbh->{LongReadLen} = 100000;
    local $dbh->{LongTruncOk} = 1;

    my $sth = $dbh->prepare_cached(q{
SELECT atc.column_name, ut.trigger_body
FROM all_triggers ut
JOIN all_trigger_cols atc USING (trigger_name)
WHERE atc.table_name = ?
AND lower(column_usage) LIKE '%new%' AND lower(column_usage) LIKE '%out%'
AND upper(trigger_type) LIKE '%BEFORE EACH ROW%' AND lower(triggering_event) LIKE '%insert%'
    }, {}, 1);

    $sth->execute($self->_uc($table));

    while (my ($col_name, $trigger_body) = $sth->fetchrow_array) {
        $col_name = $self->_lc($col_name);

        $result->{$col_name}{is_auto_increment} = 1;

        if (my ($seq_schema, $seq_name) = $trigger_body =~ /(?:\."?(\w+)"?)?"?(\w+)"?\.nextval/i) {
            $seq_schema = $self->_lc($seq_schema || $self->db_schema);
            $seq_name   = $self->_lc($seq_name);

            $result->{$col_name}{sequence} = ($self->qualify_objects ? ($seq_schema . '.') : '') . $seq_name;
        }
    }

    while (my ($col, $info) = each %$result) {
        no warnings 'uninitialized';

        if ($info->{data_type} =~ /^(?:n?[cb]lob|long(?: raw)?|bfile|date|binary_(?:float|double)|rowid)\z/i) {
            delete $info->{size};
        }

        if ($info->{data_type} =~ /^n(?:var)?char2?\z/i) {
            $info->{size} = $info->{size} / 2;
        }
        elsif (lc($info->{data_type}) eq 'number') {
            $info->{original}{data_type} = 'number';
            $info->{data_type}           = 'numeric';

            if (eval { $info->{size}[0] == 38 && $info->{size}[1] == 0 }) {
                $info->{original}{size} = $info->{size};

                $info->{data_type} = 'integer';
                delete $info->{size};
            }
        }
        elsif (my ($precision) = $info->{data_type} =~ /^timestamp\((\d+)\)(?: with (?:local )?time zone)?\z/i) {
            $info->{data_type} = join ' ', $info->{data_type} =~ /[a-z]+/ig;

            if ($precision == 6) {
                delete $info->{size};
            }
            else {
                $info->{size} = $precision;
            }
        }
        elsif (($precision) = $info->{data_type} =~ /^interval year\((\d+)\) to month\z/i) {
            $info->{data_type} = join ' ', $info->{data_type} =~ /[a-z]+/ig;

            if ($precision == 2) {
                delete $info->{size};
            }
            else {
                $info->{size} = $precision;
            }
        }
        elsif (my ($day_precision, $second_precision) = $info->{data_type} =~ /^interval day\((\d+)\) to second\((\d+)\)\z/i) {
            $info->{data_type} = join ' ', $info->{data_type} =~ /[a-z]+/ig;

            if ($day_precision == 2 && $second_precision == 6) {
                delete $info->{size};
            }
            else {
                $info->{size} = [ $day_precision, $second_precision ];
            }
        }
        elsif (lc($info->{data_type}) eq 'float') {
            $info->{original}{data_type} = 'float';
            $info->{original}{size}      = $info->{size};

            if ($info->{size} <= 63) {
                $info->{data_type} = 'real';
            }
            else {
                $info->{data_type} = 'double precision';
            }
            delete $info->{size};
        }
        elsif (lc($info->{data_type}) eq 'urowid' && $info->{size} == 4000) {
            delete $info->{size};
        }
        elsif (lc($info->{data_type}) eq 'date') {
            $info->{data_type}           = 'datetime';
            $info->{original}{data_type} = 'date';
        }
        elsif (lc($info->{data_type}) eq 'binary_float') {
            $info->{data_type}           = 'real';
            $info->{original}{data_type} = 'binary_float';
        } 
        elsif (lc($info->{data_type}) eq 'binary_double') {
            $info->{data_type}           = 'double precision';
            $info->{original}{data_type} = 'binary_double';
        } 

        if ((eval { lc(${ $info->{default_value} }) }||'') eq 'sysdate') {
            my $current_timestamp  = 'current_timestamp';
            $info->{default_value} = \$current_timestamp;

            my $sysdate = 'sysdate';
            $info->{original}{default_value} = \$sysdate;
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
# vim:et sts=4 sw=4 tw=0:
