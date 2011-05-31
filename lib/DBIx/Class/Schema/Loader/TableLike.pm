package DBIx::Class::Schema::Loader::TableLike;

use strict;
use warnings;
use base 'Class::Accessor::Grouped';

=head1 NAME

DBIx::Class::Schema::Loader::TableLike - Base Class for Tables and Views in
L<DBIx::Class::Schema::Loader>

=head1 METHODS

=head2 name

Name of the object.

=head2 schema

The schema (or owner) of the object.

=cut

__PACKAGE__->mk_group_accessors(simple => qw/
    name
    schema
/);

use overload
    '""' => 'name';

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>, L<DBIx::Class::Schema::Loader::Base>

=head1 AUTHOR

See L<DBIx::Class::Schema::Loader/AUTHOR> and L<DBIx::Class::Schema::Loader/CONTRIBUTORS>.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
# vim:et sts=4 sw=4 tw=0:
