package DBIx::Class::Schema::Loader::Generic;

use strict;
use warnings;

use base qw/DBIx::Class::Schema/;

use Carp;
use Lingua::EN::Inflect;

require DBIx::Class::Core;

__PACKAGE__->mk_classdata('loader_data');

# XXX convert all usage of $class/$self->debug to ->debug_loader

=head1 NAME

DBIx::Class::Schema::Loader::Generic - Generic DBIx::Class::Schema::Loader Implementation.

=head1 SYNOPSIS

See L<DBIx::Class::Schema::Loader>

=head1 DESCRIPTION

=head2 OPTIONS

Available constructor options are:

=head3 additional_base_classes

List of additional base classes your table classes will use.

=head3 left_base_classes

List of additional base classes, that need to be leftmost.

=head3 additional_classes

List of additional classes which your table classes will use.

=head3 constraint

Only load tables matching regex.

=head3 exclude

Exclude tables matching regex.

=head3 debug

Enable debug messages.

=head3 dsn

DBI Data Source Name.

=head3 namespace

Namespace under which your table classes will be initialized.

=head3 password

Password.

=head3 relationships

Try to automatically detect/setup has_a and has_many relationships.

=head3 inflect

An hashref, which contains exceptions to Lingua::EN::Inflect::PL().
Useful for foreign language column names.

=head3 user

Username.

=head2 METHODS

=cut

=head3 new

Not intended to be called directly.  This is used internally by the
C<new()> method in L<DBIx::Class::Schema::Loader>.

=cut

sub _load_from_connection {
    my ( $class, %args ) = @_;
    if ( $args{debug} ) {
        no strict 'refs';
        *{"$class\::debug_loader"} = sub { 1 };
    }
    my $additional = $args{additional_classes} || [];
    $additional = [$additional] unless ref $additional eq 'ARRAY';
    my $additional_base = $args{additional_base_classes} || [];
    $additional_base = [$additional_base]
      unless ref $additional_base eq 'ARRAY';
    my $left_base = $args{left_base_classes} || [];
    $left_base = [$left_base] unless ref $left_base eq 'ARRAY';
    $class->loader_data({
        _datasource =>
          [ $args{dsn}, $args{user}, $args{password}, $args{options} ],
        _namespace       => $args{namespace} || $class,
        _additional      => $additional,
        _additional_base => $additional_base,
        _left_base       => $left_base,
        _constraint      => $args{constraint} || '.*',
        _exclude         => $args{exclude},
        _relationships   => $args{relationships},
        _inflect         => $args{inflect},
        _db_schema       => $args{db_schema},
        _drop_db_schema  => $args{drop_db_schema},
        TABLE_CLASSES    => {},
        MONIKERS         => {},
    });

    $class->connection(@{$class->loader_data->{_datasource}});
    warn qq/\### START DBIx::Class::Schema::Loader dump ###\n/ if $class->debug;
    $class->_load_classes;
    $class->_relationships                            if $class->loader_data->{_relationships};
    warn qq/\### END DBIx::Class::Schema::Loader dump ###\n/ if $class->debug;
    $class->storage->dbh->disconnect; # XXX this should be ->storage->disconnect later?

    1;
}

# The original table class name during Loader,
sub _find_table_class {
    my ( $class, $table ) = @_;
    return $class->loader_data->{TABLE_CLASSES}->{$table};
}

# Returns the moniker for a given table name,
# for use in $conn->resultset($moniker)
sub moniker {
    my ( $class, $table ) = @_;
    return $class->loader_data->{MONIKERS}->{$table};
}

=head3 debug

Overload to enable debug messages.

=cut

sub debug { 0 }

=head3 tables

Returns a sorted list of tables.

    my @tables = $loader->tables;

=cut

sub tables {
    my $class = shift;
    return sort keys %{ $class->loader_data->{MONIKERS} };
}

# Overload in your driver class
sub _db_classes { croak "ABSTRACT METHOD" }

# Setup has_a and has_many relationships
sub _belongs_to_many {
    my ( $class, $table, $column, $other, $other_column ) = @_;
    my $table_class = $class->_find_table_class($table);
    my $other_class = $class->_find_table_class($other);

    warn qq/\# Belongs_to relationship\n/ if $class->debug;

    if($other_column) {
        warn qq/$table_class->belongs_to( '$column' => '$other_class',/
          .  qq/ { "foreign.$other_column" => "self.$column" },/
          .  qq/ { accessor => 'filter' });\n\n/
          if $class->debug;
        $table_class->belongs_to( $column => $other_class, 
          { "foreign.$other_column" => "self.$column" },
          { accessor => 'filter' }
        );
    }
    else {
        warn qq/$table_class->belongs_to( '$column' => '$other_class' );\n\n/
          if $class->debug;
        $table_class->belongs_to( $column => $other_class );
    }

    my ($table_class_base) = $table_class =~ /.*::(.+)/;
    my $plural = Lingua::EN::Inflect::PL( lc $table_class_base );
    $plural = $class->loader_data->{_inflect}->{ lc $table_class_base }
      if $class->loader_data->{_inflect}
      and exists $class->loader_data->{_inflect}->{ lc $table_class_base };

    warn qq/\# Has_many relationship\n/ if $class->debug;

    if($other_column) {
        warn qq/$other_class->has_many( '$plural' => '$table_class',/
          .  qq/ { "foreign.$column" => "self.$other_column" } );\n\n/
          if $class->debug;
        $other_class->has_many( $plural => $table_class,
                                { "foreign.$column" => "self.$other_column" }
                              );
    }
    else {
        warn qq/$other_class->has_many( '$plural' => '$table_class',/
          .  qq/'$other_column' );\n\n/
          if $class->debug;
        $other_class->has_many( $plural => $table_class, $column );
    }
}

# Load and setup classes
sub _load_classes {
    my $class = shift;

    my $namespace    = $class->loader_data->{_namespace};

    my @tables          = $class->_tables();
    my @db_classes      = $class->_db_classes();
    my $additional      = join '', map "use $_;\n", @{ $class->loader_data->{_additional} };
    my $additional_base = join '', map "use base '$_';\n",
      @{ $class->loader_data->{_additional_base} };
    my $left_base  = join '', map "use base '$_';\n", @{ $class->loader_data->{_left_base} };
    my $constraint = $class->loader_data->{_constraint};
    my $exclude    = $class->loader_data->{_exclude};

    foreach my $table (@tables) {
        next unless $table =~ /$constraint/;
        next if ( defined $exclude && $table =~ /$exclude/ );

        my $table = lc $table;
        my $table_name_db_schema = $table;
        my $table_name_only = $table_name_db_schema;
        my ($db_schema, $tbl) = split /\./, $table;
        if($tbl) {
            $table_name_db_schema = $tbl if $class->loader_data->{_drop_db_schema};
            $table_name_only = $tbl;
        }
        else {
            undef $db_schema;
        }

        my $table_subclass = $class->_table2subclass($db_schema, $table_name_only);
        my $table_class = $namespace . '::' . $table_subclass;

        $class->inject_base( $table_class, 'DBIx::Class::Core' );
        $_->require for @db_classes;
        $class->inject_base( $table_class, $_ ) for @db_classes;
        warn qq/\# Initializing table "$table_name_db_schema" as "$table_class"\n/ if $class->debug;
        $table_class->table(lc $table_name_db_schema);

        my ( $cols, $pks ) = $class->_table_info($table_name_db_schema);
        carp("$table has no primary key") unless @$pks;
        $table_class->add_columns(@$cols);
        $table_class->set_primary_key(@$pks) if @$pks;

        my $code = "package $table_class;\n$additional_base$additional$left_base";
        warn qq/$code/                        if $class->debug;
        warn qq/$table_class->table('$table_name_db_schema');\n/ if $class->debug;
        my $columns = join "', '", @$cols;
        warn qq/$table_class->add_columns('$columns')\n/ if $class->debug;
        my $primaries = join "', '", @$pks;
        warn qq/$table_class->set_primary_key('$primaries')\n/ if $class->debug && @$pks;
        eval $code;
        croak qq/Couldn't load additional classes "$@"/ if $@;
        unshift @{"$table_class\::ISA"}, $_ foreach ( @{ $class->loader_data->{_left_base} } );

        $class->register_class($table_subclass, $table_class);
        $class->loader_data->{TABLE_CLASSES}->{$table_name_db_schema} = $table_class;
        $class->loader_data->{MONIKERS}->{$table_name_db_schema} = $table_subclass;
    }
}

# Find and setup relationships
sub _relationships {
    my $class = shift;
    my $dbh = $class->storage->dbh;
    foreach my $table ( $class->tables ) {
        my $quoter = $dbh->get_info(29) || q{"};
        if ( my $sth = $dbh->foreign_key_info( '', '', '', '', '', $table ) ) {
            for my $res ( @{ $sth->fetchall_arrayref( {} ) } ) {
                my $column = $res->{FK_COLUMN_NAME};
                my $other  = $res->{UK_TABLE_NAME};
                my $other_column  = $res->{UK_COLUMN_NAME};
                $column =~ s/$quoter//g;
                $other =~ s/$quoter//g;
                $other_column =~ s/$quoter//g;
                eval { $class->_belongs_to_many( $table, $column, $other,
                  $other_column ) };
                warn qq/\# belongs_to_many failed "$@"\n\n/
                  if $@ && $class->debug;
            }
        }
    }
}

# Make a subclass (dbix moniker) from a table
sub _table2subclass {
    my ( $class, $db_schema, $table ) = @_;

    my $table_subclass = join '', map ucfirst, split /[\W_]+/, $table;

    if($db_schema && !$class->loader_data->{_drop_db_schema}) {
        $table_subclass = (ucfirst lc $db_schema) . '-' . $table_subclass;
    }

    $table_subclass;
}

# Overload in driver class
sub _tables { croak "ABSTRACT METHOD" }

sub _table_info { croak "ABSTRACT METHOD" }

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
