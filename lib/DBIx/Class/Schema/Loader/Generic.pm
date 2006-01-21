package DBIx::Class::Schema::Loader::Generic;

use strict;
use base 'DBIx::Class::Componentised';
use Carp;
use Lingua::EN::Inflect;
use UNIVERSAL::require;
use DBIx::Class::Storage::DBI;
require DBIx::Class::Core;
require DBIx::Class::Schema;

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

sub new {
    my ( $class, %args ) = @_;
    if ( $args{debug} ) {
        no strict 'refs';
        *{"$class\::debug"} = sub { 1 };
    }
    my $additional = $args{additional_classes} || [];
    $additional = [$additional] unless ref $additional eq 'ARRAY';
    my $additional_base = $args{additional_base_classes} || [];
    $additional_base = [$additional_base]
      unless ref $additional_base eq 'ARRAY';
    my $left_base = $args{left_base_classes} || [];
    $left_base = [$left_base] unless ref $left_base eq 'ARRAY';
    my $self = bless {
        _datasource =>
          [ $args{dsn}, $args{user}, $args{password}, $args{options} ],
        _namespace       => $args{namespace},
        _additional      => $additional,
        _additional_base => $additional_base,
        _left_base       => $left_base,
        _constraint      => $args{constraint} || '.*',
        _exclude         => $args{exclude},
        _relationships   => $args{relationships},
        _inflect         => $args{inflect},
        _db_schema       => $args{schema},
        _drop_db_schema  => $args{dropschema},
        _schema_class    => "$args{namespace}\::_schema",
        TABLE_CLASSES    => {},
        MONIKERS         => {},
    }, $class;
    warn qq/\### START DBIx::Class::Schema::Loader dump ###\n/ if $self->debug;
    $self->_load_classes;
    $self->_relationships                            if $self->{_relationships};
    warn qq/\### END DBIx::Class::Schema::Loader dump ###\n/ if $self->debug;
    $self->{_storage}->dbh->disconnect;
    $self;
}

# The original table class name during Loader,
sub _find_table_class {
    my ( $self, $table ) = @_;
    return $self->{TABLE_CLASSES}->{$table};
}

# Returns the moniker for a given table name,
# for use in $conn->resultset($moniker)
sub moniker {
    my ( $self, $table ) = @_;
    return $self->{MONIKERS}->{$table};
}

sub connect {
    my $self = shift;
    return $self->{_schema_class}->connect(@_) if(@_);
    return $self->{_schema_class}->connect(@{$self->{_datasource}});
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
    my $self = shift;
    return sort keys %{ $self->{MONIKERS} };
}

# Overload in your driver class
sub _db_classes { croak "ABSTRACT METHOD" }

# Setup has_a and has_many relationships
sub _belongs_to_many {
    my ( $self, $table, $column, $other, $other_column ) = @_;
    my $table_class = $self->_find_table_class($table);
    my $other_class = $self->_find_table_class($other);

    warn qq/\# Belongs_to relationship\n/ if $self->debug;

    if($other_column) {
        warn qq/$table_class->belongs_to( '$column' => '$other_class',/
          .  qq/ { "foreign.$other_column" => "self.$column" },/
          .  qq/ { accessor => 'filter' });\n\n/
          if $self->debug;
        $table_class->belongs_to( $column => $other_class, 
          { "foreign.$other_column" => "self.$column" },
          { accessor => 'filter' }
        );
    }
    else {
        warn qq/$table_class->belongs_to( '$column' => '$other_class' );\n\n/
          if $self->debug;
        $table_class->belongs_to( $column => $other_class );
    }

    my ($table_class_base) = $table_class =~ /.*::(.+)/;
    my $plural = Lingua::EN::Inflect::PL( lc $table_class_base );
    $plural = $self->{_inflect}->{ lc $table_class_base }
      if $self->{_inflect}
      and exists $self->{_inflect}->{ lc $table_class_base };

    warn qq/\# Has_many relationship\n/ if $self->debug;

    if($other_column) {
        warn qq/$other_class->has_many( '$plural' => '$table_class',/
          .  qq/ { "foreign.$column" => "self.$other_column" } );\n\n/
          if $self->debug;
        $other_class->has_many( $plural => $table_class,
                                { "foreign.$column" => "self.$other_column" }
                              );
    }
    else {
        warn qq/$other_class->has_many( '$plural' => '$table_class',/
          .  qq/'$other_column' );\n\n/
          if $self->debug;
        $other_class->has_many( $plural => $table_class, $column );
    }
}

# Load and setup classes
sub _load_classes {
    my $self            = shift;

    my $namespace      = $self->{_namespace};
    my $schema_class   = $self->{_schema_class};
    $self->inject_base( $schema_class, 'DBIx::Class::Schema' );
    $self->{_storage} = $schema_class->storage(DBIx::Class::Storage::DBI->new());
    $schema_class->storage->connect_info($self->{_datasource});

    my @tables          = $self->_tables();
    my @db_classes      = $self->_db_classes();
    my $additional      = join '', map "use $_;\n", @{ $self->{_additional} };
    my $additional_base = join '', map "use base '$_';\n",
      @{ $self->{_additional_base} };
    my $left_base  = join '', map "use base '$_';\n", @{ $self->{_left_base} };
    my $constraint = $self->{_constraint};
    my $exclude    = $self->{_exclude};

    foreach my $table (@tables) {
        next unless $table =~ /$constraint/;
        next if ( defined $exclude && $table =~ /$exclude/ );

        my $table = lc $table;
        my $table_name_db_schema = $table;
        my $table_name_only = $table_name_db_schema;
        my ($db_schema, $tbl) = split /\./, $table;
        if($tbl) {
            $table_name_db_schema = $tbl if $self->{_drop_db_schema};
            $table_name_only = $tbl;
        }
        else {
            undef $db_schema;
        }

        my $subclass = $self->_table2subclass($db_schema, $table_name_only);
        my $class = $namespace . '::' . $subclass;

        $self->inject_base( $class, 'DBIx::Class::Core' );
        $_->require for @db_classes;
        $self->inject_base( $class, $_ ) for @db_classes;
        warn qq/\# Initializing table "$table_name_db_schema" as "$class"\n/ if $self->debug;
        $class->table(lc $table_name_db_schema);

        my ( $cols, $pks ) = $self->_table_info($table_name_db_schema);
        carp("$table has no primary key") unless @$pks;
        $class->add_columns(@$cols);
        $class->set_primary_key(@$pks) if @$pks;

        my $code = "package $class;\n$additional_base$additional$left_base";
        warn qq/$code/                        if $self->debug;
        warn qq/$class->table('$table_name_db_schema');\n/ if $self->debug;
        my $columns = join "', '", @$cols;
        warn qq/$class->add_columns('$columns')\n/ if $self->debug;
        my $primaries = join "', '", @$pks;
        warn qq/$class->set_primary_key('$primaries')\n/ if $self->debug && @$pks;
        eval $code;
        croak qq/Couldn't load additional classes "$@"/ if $@;
        unshift @{"$class\::ISA"}, $_ foreach ( @{ $self->{_left_base} } );

        $schema_class->register_class($subclass, $class);
        $self->{TABLE_CLASSES}->{$table_name_db_schema} = $class;
        $self->{MONIKERS}->{$table_name_db_schema} = $subclass;
    }
}

# Find and setup relationships
sub _relationships {
    my $self = shift;
    my $dbh = $self->{_storage}->dbh;
    foreach my $table ( $self->tables ) {
        my $quoter = $dbh->get_info(29) || q{"};
        if ( my $sth = $dbh->foreign_key_info( '', '', '', '', '', $table ) ) {
            for my $res ( @{ $sth->fetchall_arrayref( {} ) } ) {
                my $column = $res->{FK_COLUMN_NAME};
                my $other  = $res->{UK_TABLE_NAME};
                my $other_column  = $res->{UK_COLUMN_NAME};
                $column =~ s/$quoter//g;
                $other =~ s/$quoter//g;
                $other_column =~ s/$quoter//g;
                eval { $self->_belongs_to_many( $table, $column, $other,
                  $other_column ) };
                warn qq/\# belongs_to_many failed "$@"\n\n/
                  if $@ && $self->debug;
            }
        }
    }
}

# Make a subclass (dbix moniker) from a table
sub _table2subclass {
    my ( $self, $db_schema, $table ) = @_;

    my $subclass = join '', map ucfirst, split /[\W_]+/, $table;

    if($db_schema && !$self->{_drop_db_schema}) {
        $subclass = (ucfirst lc $db_schema) . '-' . $subclass;
    }

    $subclass;
}

# Overload in driver class
sub _tables { croak "ABSTRACT METHOD" }

sub _table_info { croak "ABSTRACT METHOD" }

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
