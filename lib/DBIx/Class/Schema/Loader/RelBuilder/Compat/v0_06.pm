package DBIx::Class::Schema::Loader::RelBuilder::Compat::v0_06;

use strict;
use warnings;
use Class::C3;
use base 'DBIx::Class::Schema::Loader::RelBuilder';
use Carp::Clan qw/^DBIx::Class/;
use Lingua::EN::Inflect::Phrase ();

our $VERSION = '0.07000';

sub _normalize_name {
    my ($self, $name) = @_;

    return lc $name;
}

=head1 NAME

DBIx::Class::Schema::Loader::RelBuilder::Compat::v0_06 - RelBuilder for
compatibility with DBIx::Class::Schema::Loader version 0.06001

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
# vim:et sts=4 sw=4 tw=0:
