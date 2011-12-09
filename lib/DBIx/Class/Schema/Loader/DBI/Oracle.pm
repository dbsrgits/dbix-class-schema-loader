package DBIx::Class::Schema::Loader::DBI::Oracle;

use strict;
use warnings;
use base qw/
    DBIx::Class::Schema::Loader::DBI::Component::QuotedDefault
    DBIx::Class::Schema::Loader::DBI
/;
use mro 'c3';

our $VERSION = '0.07015';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::Oracle - DBIx::Class::Schema::Loader::DBI 
Oracle Implementation.

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader> and L<DBIx::Class::Schema::Loader::Base>.

=cut

sub _setup {
    my $self = shift;

    $self->next::method(@_);

    my ($current_schema) = $self->dbh->selectrow_array('SELECT USER FROM DUAL');

    $self->db_schema([ $current_schema ]) unless $self->db_schema;

    if (@{ $self->db_schema } == 1 && $self->db_schema->[0] ne '%'
        && lc($self->db_schema->[0]) ne lc($current_schema)) {
        $self->dbh->do('ALTER SESSION SET current_schema=' . $self->db_schema->[0]);
    }

    if (not defined $self->preserve_case) {
        $self->preserve_case(0);
    }
    elsif ($self->preserve_case) {
        $self->schema->storage->sql_maker->quote_char('"');
        $self->schema->storage->sql_maker->name_sep('.');
    }
}

sub _build_name_sep { '.' }

sub _system_schemas {
    my $self = shift;

    # From http://www.adp-gmbh.ch/ora/misc/known_schemas.html

    return ($self->next::method(@_), qw/ANONYMOUS APEX_PUBLIC_USER APEX_030200 APPQOSSYS CTXSYS DBSNMP DIP DMSYS EXFSYS LBACSYS MDDATA MDSYS MGMT_VIEW OLAPSYS ORACLE_OCM ORDDATA ORDPLUGINS ORDSYS OUTLN SI_INFORMTN_SCHEMA SPATIAL_CSW_ADMIN_USR SPATIAL_WFS_ADMIN_USR SYS SYSMAN SYSTEM TRACESRV MTSSYS OASPUBLIC OWBSYS OWBSYS_AUDIT WEBSYS WK_PROXY WKSYS WK_TEST WMSYS XDB OSE$HTTP$ADMIN AURORA$JIS$UTILITY$ AURORA$ORB$UNAUTHENTICATED/, qr/^FLOWS_\d\d\d\d\d\d\z/);
}

sub _system_tables {
    my $self = shift;

    return ($self->next::method(@_), 'PLAN_TABLE');
}

sub _dbh_tables {
    my ($self, $schema) = @_;

    return $self->dbh->tables(undef, $schema, '%', 'TABLE,VIEW');
}

sub _filter_tables {
    my $self = shift;

    # silence a warning from older DBD::Oracles in tests
    my $warn_handler = $SIG{__WARN__} || sub { warn @_ };
    local $SIG{__WARN__} = sub {
        $warn_handler->(@_)
        unless $_[0] =~ /^Field \d+ has an Oracle type \(\d+\) which is not explicitly supported/;
    };

    return $self->next::method(@_);
}

sub _table_columns {
    my ($self, $table) = @_;

    my $sth = $self->dbh->column_info(undef, $table->schema, $table, '%');

    return [ map $self->_lc($_->{COLUMN_NAME}), @{ $sth->fetchall_arrayref({ COLUMN_NAME => 1 }) || [] } ];
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my $sth = $self->dbh->prepare_cached(<<'EOF', {}, 1);
SELECT ac.constraint_name, acc.column_name
FROM all_constraints ac, all_cons_columns acc
WHERE acc.table_name=? AND acc.owner = ?
    AND ac.table_name = acc.table_name AND ac.owner = acc.owner
    AND acc.constraint_name = ac.constraint_name
    AND ac.constraint_type='U'
ORDER BY acc.position
EOF

    $sth->execute($table->name, $table->schema);

    my %constr_names;

    while(my $constr = $sth->fetchrow_arrayref) {
        my $constr_name = $self->_lc($constr->[0]);
        my $constr_col  = $self->_lc($constr->[1]);
        push @{$constr_names{$constr_name}}, $constr_col;
    }
    
    my @uniqs = map { [ $_ => $constr_names{$_} ] } keys %constr_names;
    return \@uniqs;
}

sub _table_comment {
    my $self = shift;
    my ($table) = @_;

    my $table_comment = $self->next::method(@_);

    return $table_comment if $table_comment;

    ($table_comment) = $self->dbh->selectrow_array(<<'EOF', {}, $table->schema, $table->name);
SELECT comments FROM all_tab_comments
WHERE owner = ? 
  AND table_name = ?
  AND (table_type = 'TABLE' OR table_type = 'VIEW')
EOF

    return $table_comment
}

sub _column_comment {
    my $self = shift;
    my ($table, $column_number, $column_name) = @_;

    my $column_comment = $self->next::method(@_);

    return $column_comment if $column_comment;

    ($column_comment) = $self->dbh->selectrow_array(<<'EOF', {}, $table->schema, $table->name, $self->_uc($column_name));
SELECT comments FROM all_col_comments
WHERE owner = ? 
  AND table_name = ?
  AND column_name = ?
EOF

    return $column_comment
}

sub _columns_info_for {
    my $self = shift;
    my ($table) = @_;

    my $result = $self->next::method(@_);

    local $self->dbh->{LongReadLen} = 100000;
    local $self->dbh->{LongTruncOk} = 1;

    my $sth = $self->dbh->prepare_cached(<<'EOF', {}, 1);
SELECT trigger_body
FROM all_triggers
WHERE table_name = ? AND table_owner = ?
AND upper(trigger_type) LIKE '%BEFORE EACH ROW%' AND lower(triggering_event) LIKE '%insert%'
EOF

    $sth->execute($table->name, $table->schema);

    while (my ($trigger_body) = $sth->fetchrow_array) {
        if (my ($seq_schema, $seq_name) = $trigger_body =~ /(?:\."?(\w+)"?)?"?(\w+)"?\.nextval/i) {
            if (my ($col_name) = $trigger_body =~ /:new\.(\w+)/i) {
                $col_name = $self->_lc($col_name);

                $result->{$col_name}{is_auto_increment} = 1;

                $seq_schema = $self->_lc($seq_schema || $table->schema);
                $seq_name   = $self->_lc($seq_name);

                $result->{$col_name}{sequence} = ($self->qualify_objects ? ($seq_schema . '.') : '') . $seq_name;
            }
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
