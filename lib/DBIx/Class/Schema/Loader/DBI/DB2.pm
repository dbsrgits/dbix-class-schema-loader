package DBIx::Class::Schema::Loader::DBI::DB2;

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

DBIx::Class::Schema::Loader::DBI::DB2 - DBIx::Class::Schema::Loader::DBI DB2 Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options( db_schema => "MYSCHEMA" );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader::Base>.

=cut

sub _setup {
    my $self = shift;

    $self->next::method(@_);

    my $dbh = $self->schema->storage->dbh;
    $self->{db_schema} ||= $dbh->selectrow_array('VALUES(CURRENT_USER)', {});

    if (not defined $self->preserve_case) {
        $self->preserve_case(0);
    }
    elsif ($self->preserve_case) {
        $self->schema->storage->sql_maker->quote_char('"');
        $self->schema->storage->sql_maker->name_sep('.');
    }
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my @uniqs;

    my $dbh = $self->schema->storage->dbh;

    my $sth = $self->{_cache}->{db2_uniq} ||= $dbh->prepare(
        q{SELECT kcu.COLNAME, kcu.CONSTNAME, kcu.COLSEQ
        FROM SYSCAT.TABCONST as tc
        JOIN SYSCAT.KEYCOLUSE as kcu
        ON tc.CONSTNAME = kcu.CONSTNAME AND tc.TABSCHEMA = kcu.TABSCHEMA
        WHERE tc.TABSCHEMA = ? and tc.TABNAME = ? and tc.TYPE = 'U'}
    ) or die $DBI::errstr;

    $sth->execute($self->db_schema, $self->_uc($table)) or die $DBI::errstr;

    my %keydata;
    while(my $row = $sth->fetchrow_arrayref) {
        my ($col, $constname, $seq) = @$row;
        push(@{$keydata{$constname}}, [ $seq, $self->_lc($col) ]);
    }
    foreach my $keyname (keys %keydata) {
        my @ordered_cols = map { $_->[1] } sort { $a->[0] <=> $b->[0] }
            @{$keydata{$keyname}};
        push(@uniqs, [ $keyname => \@ordered_cols ]);
    }

    $sth->finish;
    
    return \@uniqs;
}

# DBD::DB2 doesn't follow the DBI API for ->tables
sub _tables_list { 
    my ($self, $opts) = @_;
    
    my $dbh = $self->schema->storage->dbh;
    my @tables = map $self->_lc($_), $dbh->tables(
        $self->db_schema ? { TABLE_SCHEM => $self->db_schema } : undef
    );
    s/\Q$self->{_quoter}\E//g for @tables;
    s/^.*\Q$self->{_namesep}\E// for @tables;

    return $self->_filter_tables(\@tables, $opts);
}

sub _table_pk_info {
    my ($self, $table) = @_;
    return $self->next::method($self->_uc($table));
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my $rels = $self->next::method($self->_uc($table));

    foreach my $rel (@$rels) {
        $rel->{remote_table} = $self->_lc($rel->{remote_table});
    }

    return $rels;
}

sub _columns_info_for {
    my $self = shift;
    my ($table) = @_;

    my $result = $self->next::method($self->_uc($table));

    my $dbh = $self->schema->storage->dbh;

    while (my ($col, $info) = each %$result) {
        # check for identities
        my $sth = $dbh->prepare_cached(
            q{
                SELECT COUNT(*)
                FROM syscat.columns
                WHERE tabschema = ? AND tabname = ? AND colname = ?
                AND identity = 'Y' AND generated != ''
            },
            {}, 1);
        $sth->execute($self->db_schema, $self->_uc($table), $self->_uc($col));
        if ($sth->fetchrow_array) {
            $info->{is_auto_increment} = 1;
        }

        my $data_type = $info->{data_type};

        if ($data_type !~ /^(?:(?:var)?(?:char|graphic)|decimal)\z/i) {
            delete $info->{size};
        }

        if ($data_type eq 'double') {
            $info->{data_type} = 'double precision';
        }
        elsif ($data_type eq 'decimal') {
            no warnings 'uninitialized';

            $info->{data_type} = 'numeric';

            my @size = @{ $info->{size} || [] };

            if ($size[0] == 5 && $size[1] == 0) {
                delete $info->{size};
            }
        }
        elsif ($data_type =~ /^(?:((?:var)?char) \(\) for bit data|(long varchar) for bit data)\z/i) {
            my $base_type = lc($1 || $2);

            (my $original_type = $data_type) =~ s/[()]+ //;

            $info->{original}{data_type} = $original_type;

            if ($base_type eq 'long varchar') {
                $info->{data_type} = 'blob';
            }
            else {
                if ($base_type eq 'char') {
                    $info->{data_type} = 'binary';
                }
                elsif ($base_type eq 'varchar') {
                    $info->{data_type} = 'varbinary';
                }

                my ($size) = $dbh->selectrow_array(<<'EOF', {}, $self->db_schema, $self->_uc($table), $self->_uc($col));
SELECT length
FROM syscat.columns
WHERE tabschema = ? AND tabname = ? AND colname = ?
EOF

                $info->{size} = $size if $size;
            }
        }

        if ((eval { lc ${ $info->{default_value} } }||'') =~ /^current (date|time(?:stamp)?)\z/i) {
            my $type = lc($1);

            ${ $info->{default_value} } = 'current_timestamp';

            my $orig_deflt = "current $type";
            $info->{original}{default_value} = \$orig_deflt;
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
