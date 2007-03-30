package DBIx::Class::Schema::Loader::DBI::Oracle;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI';
use Carp::Clan qw/^DBIx::Class/;
use Class::C3;

our $VERSION = '0.03999_01';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::Oracle - DBIx::Class::Schema::Loader::DBI 
Oracle Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options( debug => 1 );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader::Base>.

This module is considered experimental and not well tested yet.

=cut

sub _table_columns {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;

    my $sth = $dbh->prepare($self->schema->storage->sql_maker->select($table, undef, \'1 = 0'));
    $sth->execute;
    return \@{$sth->{NAME_lc}};
}

sub _tables_list { 
    my $self = shift;

    my $dbh = $self->schema->storage->dbh;

    my @tables;
    for my $table ( $dbh->tables(undef, $self->db_schema, '%', 'TABLE,VIEW') ) { #catalog, schema, table, type
        my $quoter = $dbh->get_info(29);
        $table =~ s/$quoter//g;

        # remove "user." (schema) prefixes
        $table =~ s/\w+\.//;

        next if $table eq 'PLAN_TABLE';
        $table = lc $table;
        push @tables, $1
          if $table =~ /\A(\w+)\z/;
    }
    return @tables;
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my @uniqs;
    my $dbh = $self->schema->storage->dbh;

    my $sth = $dbh->prepare_cached(
        qq{SELECT constraint_name, ucc.column_name FROM user_constraints JOIN user_cons_columns ucc USING (constraint_name) WHERE ucc.table_name=? AND constraint_type='U'}
    ,{}, 1);

    $sth->execute(uc $table);
    my %constr_names;
    while(my $constr = $sth->fetchrow_arrayref) {
        my $constr_name = $constr->[0];
        my $constr_def  = $constr->[1];
        $constr_name =~ s/\Q$self->{_quoter}\E//;
        $constr_def =~ s/\Q$self->{_quoter}\E//;
        push @{$constr_names{$constr_name}}, lc $constr_def;
    }
    map {
        push(@uniqs, [ lc $_ => $constr_names{$_} ]);
    } keys %constr_names;

    return \@uniqs;
}

sub _table_pk_info {
    my ( $self, $table ) = @_;
    return $self->SUPER::_table_pk_info(uc $table);
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->foreign_key_info( '', '', '', '',
        $self->db_schema, uc $table );
    return [] if !$sth;

    my %rels;

    my $i = 1; # for unnamed rels, which hopefully have only 1 column ...
    while(my $raw_rel = $sth->fetchrow_arrayref) {
        my $uk_tbl  = lc $raw_rel->[2];
        my $uk_col  = lc $raw_rel->[3];
        my $fk_col  = lc $raw_rel->[7];
        my $relid   = ($raw_rel->[11] || ( "__dcsld__" . $i++ ));
        $uk_tbl =~ s/\Q$self->{_quoter}\E//g;
        $uk_col =~ s/\Q$self->{_quoter}\E//g;
        $fk_col =~ s/\Q$self->{_quoter}\E//g;
        $relid  =~ s/\Q$self->{_quoter}\E//g;
        $rels{$relid}->{tbl} = $uk_tbl;
        $rels{$relid}->{cols}->{$uk_col} = $fk_col;
    }

    my @rels;
    foreach my $relid (keys %rels) {
        push(@rels, {
            remote_columns => [ keys   %{$rels{$relid}->{cols}} ],
            local_columns  => [ values %{$rels{$relid}->{cols}} ],
            remote_table   => $rels{$relid}->{tbl},
        });
    }

    return \@rels;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>, L<DBIx::Class::Schema::Loader::Base>,
L<DBIx::Class::Schema::Loader::DBI>

=head1 AUTHOR

TSUNODA Kazuya C<drk@drk7.jp>

=cut

1;
