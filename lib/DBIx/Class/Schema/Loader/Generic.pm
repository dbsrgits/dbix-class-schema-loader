package DBIx::Class::Schema::Loader::Generic;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use Class::C3;
use Carp;
use Lingua::EN::Inflect;
use UNIVERSAL::require;
require DBIx::Class;

# The first group are all arguments which are may be defaulted within,
# The last two (classes, monikers) are generated locally:

__PACKAGE__->mk_ro_accessors(qw/
                                schema
                                connect_info
                                exclude
                                constraint
                                additional_classes
                                additional_base_classes
                                left_base_classes
                                components
                                resultset_components
                                relationships
                                inflect_map
                                moniker_map
                                db_schema
                                drop_db_schema
                                debug

                                classes
                                monikers
                             /);

=head1 NAME

DBIx::Class::Schema::Loader::Generic - Generic DBIx::Class::Schema::Loader Implementation.

=head1 SYNOPSIS

See L<DBIx::Class::Schema::Loader>

=head1 DESCRIPTION

This is the base class for the vendor-specific C<DBIx::Class::Schema::*>
classes, and implements the common functionality between them.

=head1 OPTIONS

Available constructor options are:

=head2 connect_info

Identical to the connect_info arguments to C<connect> and C<connection>
that are mentioned in L<DBIx::Class::Schema>.

An arrayref of connection information.  For DBI-based Schemas,
this takes the form:

  connect_info => [ $dsn, $user, $pass, { AutoCommit => 1 } ],

=head2 additional_base_classes

List of additional base classes your table classes will use.

=head2 left_base_classes

List of additional base classes, that need to be leftmost.

=head2 additional_classes

List of additional classes which your table classes will use.

=head2 components

List of additional components to be loaded into your table classes.
A good example would be C<ResultSetManager>.

=head2 resultset_components

List of additional resultset components to be loaded into your table
classes.  A good example would be C<AlwaysRS>.  Component
C<ResultSetManager> will be automatically added to the above
C<components> list if this option is set.

=head2 constraint

Only load tables matching regex.

=head2 exclude

Exclude tables matching regex.

=head2 debug

Enable debug messages.

=head2 relationships

Try to automatically detect/setup has_a and has_many relationships.

=head2 moniker_map

Overrides the default tablename -> moniker translation.  Can be either
a hashref of table => moniker names, or a coderef for a translator
function taking a single scalar table name argument and returning
a scalar moniker.  If the hash entry does not exist, or the function
returns a false/undef value, the code falls back to default behavior
for that table name.

=head2 inflect_map

Just like L</moniker_map> above, but for inflecting (pluralizing)
relationship names.

=head2 inflect

Deprecated.  Equivalent to L</inflect_map>, but previously only took
a hashref argument, not a coderef.  If you set C<inflect> to anything,
that setting will be copied to L</inflect_map>.

=head2 dsn

DEPRECATED, use L</connect_info> instead.

DBI Data Source Name.

=head2 user

DEPRECATED, use L</connect_info> instead.

Username.

=head2 password

DEPRECATED, use L</connect_info> instead.

Password.

=head2 options

DEPRECATED, use L</connect_info> instead.

DBI connection options hashref, like:

  { AutoCommit => 1 }

=head1 METHODS

=cut

# ensure that a peice of object data is a valid arrayref, creating
# an empty one or encapsulating whatever's there.
sub _ensure_arrayref {
    my $self = shift;

    foreach (@_) {
        $self->{$_} ||= [];
        $self->{$_} = [ $self->{$_} ]
            unless ref $self->{$_} eq 'ARRAY';
    }
}

=head2 new

Constructor for L<DBIx::Class::Schema::Loader::Generic>, used internally
by L<DBIx::Class::Schema::Loader>.

=cut

sub new {
    my ( $class, %args ) = @_;

    my $self = { %args };

    bless $self => $class;

    $self->{db_schema}  ||= '';
    $self->{constraint} ||= '.*';
    $self->_ensure_arrayref(qw/additional_classes
                               additional_base_classes
                               left_base_classes
                               components
                               resultset_components
                               connect_info/);

    push(@{$self->{components}}, 'ResultSetManager')
        if @{$self->{resultset_components}};

    $self->{monikers} = {};
    $self->{classes} = {};

    # Support deprecated argument name
    $self->{inflect_map} ||= $self->{inflect};

    # Support deprecated connect_info args, even mixed
    #  with a valid partially-filled connect_info
    $self->{connect_info}->[0] ||= $self->{dsn};
    $self->{connect_info}->[1] ||= $self->{user};
    $self->{connect_info}->[2] ||= $self->{password};
    $self->{connect_info}->[3] ||= $self->{options};

    $self;
}

=head2 load

Does the actual schema-construction work, used internally by
L<DBIx::Class::Schema::Loader> right after object construction.

=cut

sub load {
    my $self = shift;

    $self->schema->connection(@{$self->connect_info});

    warn qq/\### START DBIx::Class::Schema::Loader dump ###\n/
        if $self->debug;

    $self->_load_classes;
    $self->_load_relationships if $self->relationships;

    warn qq/\### END DBIx::Class::Schema::Loader dump ###\n/
        if $self->debug;
    $self->schema->storage->disconnect;

    $self;
}

# Overload in your driver class
sub _db_classes { croak "ABSTRACT METHOD" }

# Inflect a relationship name
sub _inflect_relname {
    my ($self, $relname) = @_;

    if( ref $self->{inflect_map} eq 'HASH' ) {
        return $self->inflect_map->{$relname}
            if exists $self->inflect_map->{$relname};
    }
    elsif( ref $self->{inflect_map} eq 'CODE' ) {
        my $inflected = $self->inflect_map->($relname);
        return $inflected if $inflected;
    }

    return Lingua::EN::Inflect::PL($relname);
}

# Set up a simple relation with just a local col and foreign table
sub _make_simple_rel {
    my ($self, $table, $other, $col) = @_;

    my $table_class = $self->classes->{$table};
    my $other_class = $self->classes->{$other};
    my $table_relname = $self->_inflect_relname(lc $table);

    warn qq/\# Belongs_to relationship\n/ if $self->debug;
    warn qq/$table_class->belongs_to( '$col' => '$other_class' );\n\n/
      if $self->debug;
    $table_class->belongs_to( $col => $other_class );

    warn qq/\# Has_many relationship\n/ if $self->debug;
    warn qq/$other_class->has_many( '$table_relname' => '$table_class',/
      .  qq/$col);\n\n/
      if $self->debug;

    $other_class->has_many( $table_relname => $table_class, $col);
}

# not a class method, just a helper for cond_rel XXX
sub _stringify_hash {
    my $href = shift;

    return '{ ' .
           join(q{, }, map("$_ => $href->{$_}", keys %$href))
           . ' }';
}

# Set up a complex relation based on a hashref condition
sub _make_cond_rel {
    my ( $self, $table, $other, $cond ) = @_;

    my $table_class = $self->classes->{$table};
    my $other_class = $self->classes->{$other};
    my $table_relname = $self->_inflect_relname(lc $table);
    my $other_relname = lc $other;

    # for single-column case, set the relname to the column name,
    # to make filter accessors work
    if(scalar keys %$cond == 1) {
        my ($col) = keys %$cond;
        $other_relname = $cond->{$col};
    }

    my $rev_cond = { reverse %$cond };

    for (keys %$rev_cond) {
        $rev_cond->{"foreign.$_"} = "self.".$rev_cond->{$_};
        delete $rev_cond->{$_};
    }

    my $cond_printable = _stringify_hash($cond)
        if $self->debug;
    my $rev_cond_printable = _stringify_hash($rev_cond)
        if $self->debug;

    warn qq/\# Belongs_to relationship\n/ if $self->debug;

    warn qq/$table_class->belongs_to( '$other_relname' => '$other_class',/
      .  qq/$cond_printable);\n\n/
      if $self->debug;

    $table_class->belongs_to( $other_relname => $other_class, $cond);

    warn qq/\# Has_many relationship\n/ if $self->debug;

    warn qq/$other_class->has_many( '$table_relname' => '$table_class',/
      .  qq/$rev_cond_printable);\n\n/
      .  qq/);\n\n/
      if $self->debug;

    $other_class->has_many( $table_relname => $table_class, $rev_cond);
}

sub _use {
    my $self = shift;
    my $target = shift;

    foreach (@_) {
        $_->require or croak ($_ . "->require: $@");
        eval "package $target; use $_;";
        croak "use $_: $@" if $@;
    }
}

sub _inject {
    my $self = shift;
    my $target = shift;
    my $schema = $self->schema;

    foreach (@_) {
        $_->require or croak ($_ . "->require: $@");
        $schema->inject_base($target, $_);
    }
}

# Load and setup classes
sub _load_classes {
    my $self = shift;

    my @tables     = $self->_tables();
    my @db_classes = $self->_db_classes();
    my $schema     = $self->schema;

    foreach my $table (@tables) {
        my $constraint = $self->constraint;
        my $exclude = $self->exclude;

        next unless $table =~ /$constraint/;
        next if defined $exclude && $table =~ /$exclude/;

        my ($db_schema, $tbl) = split /\./, $table;
        my $tablename = lc $table;
        if($tbl) {
            $tablename = $self->drop_db_schema ? $tbl : lc $table;
        }
        my $lc_tblname = lc $tablename;

        my $table_moniker = $self->_table2moniker($db_schema, $tbl);
        my $table_class = $schema . q{::} . $table_moniker;

        { no strict 'refs';
          @{"${table_class}::ISA"} = qw/DBIx::Class/;
        }
        $self->_use   ($table_class, @{$self->additional_classes});
        $self->_inject($table_class, @{$self->additional_base_classes});
        $table_class->load_components(@{$self->components}, @db_classes, 'Core');
        $table_class->load_resultset_components(@{$self->resultset_components})
            if @{$self->resultset_components};
        $self->_inject($table_class, @{$self->left_base_classes});

        warn qq/\# Initializing table "$tablename" as "$table_class"\n/
            if $self->debug;
        $table_class->table($lc_tblname);

        my ( $cols, $pks ) = $self->_table_info($table);
        carp("$table has no primary key") unless @$pks;
        $table_class->add_columns(@$cols);
        $table_class->set_primary_key(@$pks) if @$pks;

        warn qq/$table_class->table('$tablename');\n/ if $self->debug;
        my $columns = join "', '", @$cols;
        warn qq/$table_class->add_columns('$columns')\n/ if $self->debug;
        my $primaries = join "', '", @$pks;
        warn qq/$table_class->set_primary_key('$primaries')\n/
            if $self->debug && @$pks;

        $table_class->require;
        if($@ && $@ !~ /^Can't locate /) {
            croak "Failed to load external class definition"
                  . "for '$table_class': $@";
        }
        elsif(!$@) {
            warn qq/# Loaded external class definition for '$table_class'\n/
                if $self->debug;
        }

        $schema->register_class($table_moniker, $table_class);
        $self->classes->{$lc_tblname} = $table_class;
        $self->monikers->{$lc_tblname} = $table_moniker;
    }
}

=head2 tables

Returns a sorted list of loaded tables, using the original database table
names.  Actually generated from the keys of the C<monikers> hash below.

  my @tables = $schema->loader->tables;

=cut

sub tables {
    my $self = shift;

    return sort keys %{ $self->monikers };
}

# Find and setup relationships
sub _load_relationships {
    my $self = shift;

    my $dbh = $self->schema->storage->dbh;
    my $quoter = $dbh->get_info(29) || q{"};
    foreach my $table ( $self->tables ) {
        my $rels = {};
        my $sth = $dbh->foreign_key_info( '',
            $self->db_schema, '', '', '', $table );
        next if !$sth;
        while(my $raw_rel = $sth->fetchrow_hashref) {
            my $uk_tbl  = lc $raw_rel->{UK_TABLE_NAME};
            my $uk_col  = lc $raw_rel->{UK_COLUMN_NAME};
            my $fk_col  = lc $raw_rel->{FK_COLUMN_NAME};
            my $relid   = lc $raw_rel->{UK_NAME};
            $uk_tbl =~ s/$quoter//g;
            $uk_col =~ s/$quoter//g;
            $fk_col =~ s/$quoter//g;
            $relid  =~ s/$quoter//g;
            $rels->{$relid}->{tbl} = $uk_tbl;
            $rels->{$relid}->{cols}->{$uk_col} = $fk_col;
        }

        foreach my $relid (keys %$rels) {
            my $reltbl = $rels->{$relid}->{tbl};
            my $cond   = $rels->{$relid}->{cols};
            eval { $self->_make_cond_rel( $table, $reltbl, $cond ) };
              warn qq/\# belongs_to_many failed "$@"\n\n/
                if $@ && $self->debug;
        }
    }
}

# Make a moniker from a table
sub _table2moniker {
    my ( $self, $db_schema, $table ) = @_;

    my $db_schema_ns;

    if($table) {
        $db_schema = ucfirst lc $db_schema;
        $db_schema_ns = $db_schema if(!$self->drop_db_schema);
    } else {
        $table = $db_schema;
    }

    my $moniker;

    if( ref $self->moniker_map eq 'HASH' ) {
        $moniker = $self->moniker_map->{$table};
    }
    elsif( ref $self->moniker_map eq 'CODE' ) {
        $moniker = $self->moniker_map->($table);
    }

    $moniker ||= join '', map ucfirst, split /[\W_]+/, lc $table;

    $moniker = $db_schema_ns ? $db_schema_ns . $moniker : $moniker;

    return $moniker;
}

# Overload in driver class
sub _tables { croak "ABSTRACT METHOD" }

sub _table_info { croak "ABSTRACT METHOD" }

=head2 monikers

Returns a hashref of loaded table-to-moniker mappings for the original
database table names.

  my $monikers = $schema->loader->monikers;
  my $foo_tbl_moniker = $monikers->{foo_tbl};
  # -or-
  my $foo_tbl_moniker = $schema->loader->monikers->{foo_tbl};
  # $foo_tbl_moniker would look like "FooTbl"

=head2 classes

Returns a hashref of table-to-classname mappings for the original database
table names.  You probably shouldn't be using this for any normal or simple
usage of your Schema.  The usual way to run queries on your tables is via
C<$schema-E<gt>resultset('FooTbl')>, where C<FooTbl> is a moniker as
returned by C<monikers> above.

  my $classes = $schema->loader->classes;
  my $foo_tbl_class = $classes->{foo_tbl};
  # -or-
  my $foo_tbl_class = $schema->loader->classes->{foo_tbl};
  # $foo_tbl_class would look like "My::Schema::FooTbl",
  #   assuming the schema class is "My::Schema"

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
