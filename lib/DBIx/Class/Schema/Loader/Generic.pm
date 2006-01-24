package DBIx::Class::Schema::Loader::Generic;

use strict;
use warnings;

use base qw/DBIx::Class::Schema/;

use Carp;
use Lingua::EN::Inflect;

require DBIx::Class::Core;

__PACKAGE__->mk_classdata('loader_data');

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
        _additional      => $additional,
        _additional_base => $additional_base,
        _left_base       => $left_base,
        _constraint      => $args{constraint} || '.*',
        _exclude         => $args{exclude},
        _relationships   => $args{relationships},
        _inflect         => $args{inflect},
        _db_schema       => $args{db_schema} || '',
        _drop_db_schema  => $args{drop_db_schema},
        TABLE_CLASSES    => {},
        MONIKERS         => {},
    });

    $class->connection(@{$class->loader_data->{_datasource}});
    warn qq/\### START DBIx::Class::Schema::Loader dump ###\n/ if $class->debug_loader;
    $class->_load_classes;
    $class->_relationships                            if $class->loader_data->{_relationships};
    warn qq/\### END DBIx::Class::Schema::Loader dump ###\n/ if $class->debug_loader;
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

=head3 moniker

Returns the moniker for a given literal table name.  Used
as $schema->resultset($moniker), etc.

=cut
sub moniker {
    my ( $class, $table ) = @_;
    return $class->loader_data->{MONIKERS}->{$table};
}

=head3 debug_loader

Overload to enable Loader debug messages.

=cut

sub debug_loader { 0 }

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
    use Data::Dumper;

    my ( $class, $table, $other, $cond ) = @_;
    my $table_class = $class->_find_table_class($table);
    my $other_class = $class->_find_table_class($other);

    my $table_relname = lc $table;
    my $other_relname = lc $other;

    if(my $inflections = $class->loader_data->{_inflect}) {
        $table_relname = $inflections->{$table_relname}
          if exists $inflections->{$table_relname};
    }
    else {
        $table_relname = Lingua::EN::Inflect::PL($table_relname);
    }

    # for single-column case, set the relname to the column name,
    # to make filter accessors work
    if(scalar keys %$cond == 1) {
        my ($col) = keys %$cond;
        $other_relname = $cond->{$col};
    }

    my $rev_cond = { reverse %$cond };

    warn qq/\# Belongs_to relationship\n/ if $class->debug_loader;

    warn qq/$table_class->belongs_to( '$other_relname' => '$other_class',/
      .  Dumper($cond)
      .  qq/);\n\n/
      if $class->debug_loader;

    $table_class->belongs_to( $other_relname => $other_class, $cond);

    warn qq/\# Has_many relationship\n/ if $class->debug_loader;

    warn qq/$other_class->has_many( '$table_relname' => '$table_class',/
      .  Dumper($rev_cond)
      .  qq/);\n\n/
      if $class->debug_loader;

    $other_class->has_many( $table_relname => $table_class, $rev_cond);
}

# Load and setup classes
sub _load_classes {
    my $class = shift;

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

        my ($db_schema, $tbl) = split /\./, $table;
        my $tablename = lc $table;
        if($tbl) {
            $tablename = $class->loader_data->{_drop_db_schema} ? $tbl : lc $table;
        }

        my $table_moniker = $class->_table2moniker($db_schema, $tbl);
        my $table_class = "$class\::$table_moniker";

        $class->inject_base( $table_class, 'DBIx::Class::Core' );
        $_->require for @db_classes;
        $class->inject_base( $table_class, $_ ) for @db_classes;
        warn qq/\# Initializing table "$tablename" as "$table_class"\n/ if $class->debug_loader;
        $table_class->table(lc $tablename);

        my ( $cols, $pks ) = $class->_table_info($table);
        carp("$table has no primary key") unless @$pks;
        $table_class->add_columns(@$cols);
        $table_class->set_primary_key(@$pks) if @$pks;

        my $code = "package $table_class;\n$additional_base$additional$left_base";
        warn qq/$code/                        if $class->debug_loader;
        warn qq/$table_class->table('$tablename');\n/ if $class->debug_loader;
        my $columns = join "', '", @$cols;
        warn qq/$table_class->add_columns('$columns')\n/ if $class->debug_loader;
        my $primaries = join "', '", @$pks;
        warn qq/$table_class->set_primary_key('$primaries')\n/ if $class->debug_loader && @$pks;
        eval $code;
        croak qq/Couldn't load additional classes "$@"/ if $@;
        unshift @{"$table_class\::ISA"}, $_ foreach ( @{ $class->loader_data->{_left_base} } );

        $class->register_class($table_moniker, $table_class);
        $class->loader_data->{TABLE_CLASSES}->{lc $tablename} = $table_class;
        $class->loader_data->{MONIKERS}->{lc $tablename} = $table_moniker;
    }
}

# Find and setup relationships
sub _relationships {
    my $class = shift;
    my $dbh = $class->storage->dbh;
    my $quoter = $dbh->get_info(29) || q{"};
    foreach my $table ( $class->tables ) {
        my $rels = {};
        my $sth = $dbh->foreign_key_info( '',
            $class->loader_data->{_db_schema}, '', '', '', $table );
        next if !$sth;
        while(my $raw_rel = $sth->fetchrow_hashref) {
            my $uk_tbl  = lc $raw_rel->{UK_TABLE_NAME};
            my $uk_col  = lc $raw_rel->{UK_COLUMN_NAME};
            my $fk_col  = lc $raw_rel->{FK_COLUMN_NAME};
            $uk_tbl =~ s/$quoter//g;
            $uk_col =~ s/$quoter//g;
            $fk_col =~ s/$quoter//g;
            $rels->{$uk_tbl}->{$uk_col} = $fk_col;
        }

        foreach my $reltbl (keys %$rels) {
            my $cond = $rels->{$reltbl};
            eval { $class->_belongs_to_many( $table, $reltbl, $cond ) };
              warn qq/\# belongs_to_many failed "$@"\n\n/
                if $@ && $class->debug_loader;
        }
    }
}

# Make a moniker from a table
sub _table2moniker {
    my ( $class, $db_schema, $table ) = @_;

    my $db_schema_ns;

    if($table) {
        $db_schema = ucfirst lc $db_schema;
        $db_schema_ns = $db_schema if(!$class->loader_data->{_drop_db_schema});
    } else {
        $table = $db_schema;
    }

    my $moniker = join '', map ucfirst, split /[\W_]+/, lc $table;
    $moniker = $db_schema_ns ? $db_schema_ns . $moniker : $moniker;

    return $moniker;
}

# Overload in driver class
sub _tables { croak "ABSTRACT METHOD" }

sub _table_info { croak "ABSTRACT METHOD" }

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
