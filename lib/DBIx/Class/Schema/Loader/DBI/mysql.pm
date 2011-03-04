package DBIx::Class::Schema::Loader::DBI::mysql;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI';
use Carp::Clan qw/^DBIx::Class/;
use mro 'c3';

our $VERSION = '0.07010';

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

sub _setup {
    my $self = shift;

    $self->next::method(@_);

    if (not defined $self->preserve_case) {
        $self->preserve_case(0);
    }
}

sub _tables_list { 
    my ($self, $opts) = @_;

    return $self->next::method($opts, undef, undef);
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;

    my $table_def_ref = eval { $dbh->selectrow_arrayref("SHOW CREATE TABLE `$table`") };
    my $table_def = $table_def_ref->[1];

    return [] if not $table_def;

    my $qt = qr/["`]/;

    my (@reldata) = ($table_def =~
        /CONSTRAINT $qt.*$qt FOREIGN KEY \($qt(.*)$qt\) REFERENCES $qt(.*)$qt \($qt(.*)$qt\)/ig
    );

    my @rels;
    while (scalar @reldata > 0) {
        my $cols = shift @reldata;
        my $f_table = shift @reldata;
        my $f_cols = shift @reldata;

        my @cols   = map { s/(?: \Q$self->{_quoter}\E | $qt )//x; $self->_lc($_) }
            split(/$qt?\s*$qt?,$qt?\s*$qt?/, $cols);

        my @f_cols = map { s/(?: \Q$self->{_quoter}\E | $qt )//x; $self->_lc($_) }
            split(/$qt?\s*$qt?,$qt?\s*$qt?/, $f_cols);

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
                [ $row->{Seq_in_index}, $self->_lc($row->{Column_name}) ]
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
        delete $info->{size} if $info->{data_type} !~ /^(?: (?:var)?(?:char(?:acter)?|binary) | bit | year)\z/ix;

        if ($info->{data_type} eq 'int') {
            $info->{data_type} = 'integer';
        }
        elsif ($info->{data_type} eq 'double') {
            $info->{data_type} = 'double precision';
        }

        # information_schema is available in 5.0+
        my ($precision, $scale, $column_type, $default) = eval { $dbh->selectrow_array(<<'EOF', {}, $table, $col) };
SELECT numeric_precision, numeric_scale, column_type, column_default
FROM information_schema.columns
WHERE table_name = ? AND column_name = ?
EOF
        my $has_information_schema = not defined $@;

        $column_type = '' if not defined $column_type;

        if ($info->{data_type} eq 'bit' && (not exists $info->{size})) {
            $info->{size} = $precision if defined $precision;
        }
        elsif ($info->{data_type} =~ /^(?:float|double precision|decimal)\z/i) {
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
        elsif ($info->{data_type} =~ /^(?:date(?:time)?|timestamp)\z/) {
            if (not (defined $self->datetime_undef_if_invalid && $self->datetime_undef_if_invalid == 0)) {
                $info->{datetime_undef_if_invalid} = 1;
            }
        }

        # Sometimes apparently there's a bug where default_value gets set to ''
        # for things that don't actually have or support that default (like ints.)
        if (exists $info->{default_value} && $info->{default_value} eq '') {
            if ($has_information_schema) {
                if (not defined $default) {
                    delete $info->{default_value};
                }
            }
            else { # just check if it's a char/text type, otherwise remove
                delete $info->{default_value} unless $info->{data_type} =~ /char|text/i;
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
    if (   lc($dbi_info->{COLUMN_DEF})      eq 'current_timestamp'
        && lc($dbi_info->{mysql_type_name}) eq 'timestamp') {

        my $current_timestamp = 'current_timestamp';
        $extra_info{default_value} = \$current_timestamp;
    }

    return \%extra_info;
}

sub _dbh_column_info {
    my $self = shift;

    local $SIG{__WARN__} = sub { warn @_
        unless $_[0] =~ /^column_info: unrecognized column type/ };

    $self->next::method(@_);
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
