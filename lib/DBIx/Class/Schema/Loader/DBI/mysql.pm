package DBIx::Class::Schema::Loader::DBI::mysql;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI';
use Carp::Clan qw/^DBIx::Class/;
use Class::C3;

our $VERSION = '0.06000';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::mysql - DBIx::Class::Schema::Loader::DBI mysql Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options( debug => 1 );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader::Base>.

=cut

sub _tables_list { 
    my ($self, $opts) = @_;

    return $self->next::method($opts, undef, undef);
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $table_def_ref = $dbh->selectrow_arrayref("SHOW CREATE TABLE `$table`")
        or croak ("Cannot get table definition for $table");
    my $table_def = $table_def_ref->[1] || '';

    my $qt = qr/["`]/;

    my (@reldata) = ($table_def =~
        /CONSTRAINT $qt.*$qt FOREIGN KEY \($qt(.*)$qt\) REFERENCES $qt(.*)$qt \($qt(.*)$qt\)/ig
    );

    my @rels;
    while (scalar @reldata > 0) {
        my $cols = shift @reldata;
        my $f_table = shift @reldata;
        my $f_cols = shift @reldata;

        my @cols   = map { s/(?: \Q$self->{_quoter}\E | $qt )//x; lc $_ }
            split(/\s*,\s*/, $cols);

        my @f_cols = map { s/(?: \Q$self->{_quoter}\E | $qt )//x; lc $_ }
            split(/\s*,\s*/, $f_cols);

        push(@rels, {
            local_columns => \@cols,
            remote_columns => \@f_cols,
            remote_table => $f_table
        });
    }

    return \@rels;
}

# primary and unique info comes from the same sql statement,
#   so cache it here for both routines to use
sub _mysql_table_get_keys {
    my ($self, $table) = @_;

    if(!exists($self->{_cache}->{_mysql_keys}->{$table})) {
        my %keydata;
        my $dbh = $self->schema->storage->dbh;
        my $sth = $dbh->prepare('SHOW INDEX FROM '.$self->_table_as_sql($table));
        $sth->execute;
        while(my $row = $sth->fetchrow_hashref) {
            next if $row->{Non_unique};
            push(@{$keydata{$row->{Key_name}}},
                [ $row->{Seq_in_index}, lc $row->{Column_name} ]
            );
        }
        foreach my $keyname (keys %keydata) {
            my @ordered_cols = map { $_->[1] } sort { $a->[0] <=> $b->[0] }
                @{$keydata{$keyname}};
            $keydata{$keyname} = \@ordered_cols;
        }
        $self->{_cache}->{_mysql_keys}->{$table} = \%keydata;
    }

    return $self->{_cache}->{_mysql_keys}->{$table};
}

sub _table_pk_info {
    my ( $self, $table ) = @_;

    return $self->_mysql_table_get_keys($table)->{PRIMARY};
}

sub _table_uniq_info {
    my ( $self, $table ) = @_;

    my @uniqs;
    my $keydata = $self->_mysql_table_get_keys($table);
    foreach my $keyname (keys %$keydata) {
        next if $keyname eq 'PRIMARY';
        push(@uniqs, [ $keyname => $keydata->{$keyname} ]);
    }

    return \@uniqs;
}

sub _columns_info_for {
    my $self = shift;
    my ($table) = @_;

    my $result = $self->next::method(@_);

    my $dbh = $self->schema->storage->dbh;

    while (my ($col, $info) = each %$result) {
        delete $info->{size}
            unless $info->{data_type} =~ /^(?: (?:var)?(?:char(?:acter)?|binary) | bit | year)\z/ix;

        if ($info->{data_type} eq 'int') {
            $info->{data_type} = 'integer';
        }
        elsif ($info->{data_type} eq 'double') {
            $info->{data_type} = 'double precision';
        }

        my ($precision, $scale, $column_type) = eval { $dbh->selectrow_array(<<'EOF', {}, lc $table, lc $col) };
SELECT numeric_precision, numeric_scale, column_type
FROM information_schema.columns
WHERE lower(table_name) = ? AND lower(column_name) = ?
EOF
        $column_type = '' if not defined $column_type;

        if ($info->{data_type} eq 'bit' && (not exists $info->{size})) {
            $info->{size} = $precision if defined $precision;
        }
        elsif ($info->{data_type} =~ /^(?:float|double precision|decimal)\z/) {
            if (defined $precision && defined $scale) {
                if ($precision == 10 && $scale == 0) {
                    delete $info->{size};
                }
                else {
                    $info->{size} = [$precision,$scale];
                }
            }
        }
        elsif ($info->{data_type} eq 'year') {
            if ($column_type =~ /\(2\)/) {
                $info->{size} = 2;
            }
            elsif ($column_type =~ /\(4\)/ || $info->{size} == 4) {
                delete $info->{size};
            }
        }
    }

    return $result;
}

sub _extra_column_info {
    no warnings 'uninitialized';
    my ($self, $table, $col, $info, $dbi_info) = @_;
    my %extra_info;

    if ($dbi_info->{mysql_is_auto_increment}) {
        $extra_info{is_auto_increment} = 1
    }
    if ($dbi_info->{mysql_type_name} =~ /\bunsigned\b/i) {
        $extra_info{extra}{unsigned} = 1;
    }
    if ($dbi_info->{mysql_values}) {
        $extra_info{extra}{list} = $dbi_info->{mysql_values};
    }
    if (   $dbi_info->{COLUMN_DEF}      =~ /^CURRENT_TIMESTAMP\z/i
        && $dbi_info->{mysql_type_name} =~ /^TIMESTAMP\z/i) {

        $extra_info{default_value} = \'CURRENT_TIMESTAMP';
    }

    return \%extra_info;
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
