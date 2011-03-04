package DBIx::Class::Schema::Loader::RelBuilder::Compat::v0_040;

use strict;
use warnings;
use mro 'c3';
use base 'DBIx::Class::Schema::Loader::RelBuilder::Compat::v0_05';
use Carp::Clan qw/^DBIx::Class/;
use Lingua::EN::Inflect::Number ();

our $VERSION = '0.07010';

sub _relnames_and_method {
    my ( $self, $local_moniker, $rel, $cond, $uniqs, $counters ) = @_;

    my $remote_moniker = $rel->{remote_source};
    my $remote_table   = $self->{schema}->source( $remote_moniker )->from;

    my $local_table = $self->{schema}->source($local_moniker)->from;
    my $local_cols  = $rel->{local_columns};

    # for single-column case, set the remote relname to just the column name
    my $remote_relname =
        scalar keys %{$cond} == 1
            ? $self->_inflect_singular( values %$cond  )
            : $self->_inflect_singular( lc $remote_table );

    # If more than one rel between this pair of tables, use the local
    # col names to distinguish
    my $local_relname;
    if ($counters->{$remote_moniker} > 1) {
        my $colnames = '_' . join( '_', @$local_cols );
        $remote_relname .= $colnames if keys %$cond > 1;
        $local_relname = $self->_inflect_plural( lc($local_table) . $colnames );
    } else {
        $local_relname = $self->_inflect_plural(lc $local_table);
    }

    return ( $local_relname, $remote_relname, 'has_many' );
}

sub _remote_attrs { }

=head1 NAME

DBIx::Class::Schema::Loader::RelBuilder::Compat::v0_040 - RelBuilder for
compatibility with DBIx::Class::Schema::Loader version 0.04006

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader::Base/naming> and
L<DBIx::Class::Schema::Loader::RelBuilder>.

=head1 AUTHOR

See L<DBIx::Class::Schema::Loader/AUTHOR> and L<DBIx::Class::Schema::Loader/CONTRIBUTORS>.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
