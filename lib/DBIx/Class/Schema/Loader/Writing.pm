package DBIx::Class::Schema::Loader::Writing;

# Empty. POD only.

1;

=head1 NAME                                                                     
                                                                                
DBIx::Class::Schema::Loader::Writing - Loader subclass writing guide

=head1 SYNOPSIS

  package DBIx::Class::Schema::Loader::Foo;

  # THIS IS JUST A TEMPLATE TO GET YOU STARTED.

  use strict;
  use base 'DBIx::Class::Schema::Loader::Generic';
  use Carp;

  sub _loader_db_classes {
      return qw/DBIx::Class::PK::Auto::Foo/;
          # You may want to return more, or less, than this.
  }

  sub _loader_tables {
      my $class = shift;
      my $dbh = $class->storage->dbh;
      return $dbh->tables; # Your DBD may need something different
  }

  sub _loader_table_info {
      my ( $class, $table ) = @_;
      ...
      return ( \@cols, \@primary );
  }

  sub _loader_relationships {
      my $class = shift;
      ...
      $class->_loader_make_relations($table, $f_key, $f_table, $f_column);
          # For each relationship you want to set up ($f_column is
          # optional, default is $f_table's primary key)
      ...
  }

=cut
