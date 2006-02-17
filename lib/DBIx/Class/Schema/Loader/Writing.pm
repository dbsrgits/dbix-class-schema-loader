package DBIx::Class::Schema::Loader::Writing;

# Empty. POD only.

1;

=head1 NAME                                                                     
                                                                                
DBIx::Class::Schema::Loader::Writing - Loader subclass writing guide

=head1 SYNOPSIS

  package DBIx::Class::Schema::Loader::Foo;

  # THIS IS JUST A TEMPLATE TO GET YOU STARTED.

  use strict;
  use warnings;
  use base 'DBIx::Class::Schema::Loader::Generic';
  use Class::C3;

  sub _db_classes {
      return qw/PK::Auto::Foo/;
          # You may want to return more, or less, than this.
  }

  sub _tables {
      my $self = shift;
      my $dbh = $self->schema->storage->dbh;
      return $dbh->tables; # Your DBD may need something different
  }

  sub _table_info {
      my ( $self, $table ) = @_;
      ...
      return ( \@cols, \@primary );
  }

  sub _load_relationships {
      my $self = shift;
      ...

      # make a simple relationship, where $table($column)
      #  references the PK of $f_table:
      $self->_make_simple_rel($table, $f_table, $column);

      # make a relationship with a complex condition-clause:
      $self->_make_cond_rel($table, $f_table,
          { foo => bar, baz => xaa } );

      ...
  }

  1;

=cut
