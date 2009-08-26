package DBIx::Class::Schema::Loader::Compat::v0_040;

use strict;
use warnings;
use Class::C3;
use DBIx::Class::Schema::Loader::RelBuilder::Compat::v0_040;

# Make a moniker from a table
sub _default_table2moniker {
    my ($self, $table) = @_;

    return join '', map ucfirst, split /[\W_]+/, lc $table;
}

sub _relbuilder {
	my ($self) = @_;
    $self->{relbuilder} ||= DBIx::Class::Schema::Loader::RelBuilder::v04Compat->new(
        $self->schema, $self->inflect_plural, $self->inflect_singular
    );
}

1;
