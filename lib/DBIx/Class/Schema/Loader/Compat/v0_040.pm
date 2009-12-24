package DBIx::Class::Schema::Loader::Compat::v0_040;

use strict;
use warnings;
use Class::C3;

use base 'DBIx::Class::Schema::Loader::Base';

use DBIx::Class::Schema::Loader::RelBuilder::Compat::v0_040;

# Make a moniker from a table
sub _default_table2moniker {
    my ($self, $table) = @_;

    return join '', map ucfirst, split /[\W_]+/, lc $table;
}

sub _relbuilder {
	my ($self) = @_;
    $self->{relbuilder} ||=
      DBIx::Class::Schema::Loader::RelBuilder::Compat::v0_040->new(
          $self->schema, $self->inflect_plural, $self->inflect_singular
      );
}

1;

=head1 NAME

DBIx::Class::Schema::Loader::Compat::v0_040 - Compatibility for DBIx::Class::Schema::Loader
version 0.04006

=head1 DESCRIPTION

Dumps from the old version are auto-detected, and the compat layer is turned
on. See also L<DBIx::Class::Schema::Loader::Base/namingg>.

=cut
