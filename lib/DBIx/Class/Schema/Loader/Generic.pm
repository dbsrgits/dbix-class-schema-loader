package DBIx::Class::Schema::Loader::Generic;

use strict;
use warnings;

use base qw/DBIx::Class::Schema/;

use Carp;
use Lingua::EN::Inflect;

require DBIx::Class::Core;

__PACKAGE__->mk_classaccessor('_loader_inflect');
__PACKAGE__->mk_classaccessor('_loader_db_schema');
__PACKAGE__->mk_classaccessor('_loader_drop_db_schema');
__PACKAGE__->mk_classaccessor('_loader_classes' => {} );
__PACKAGE__->mk_classaccessor('_loader_monikers' => {} );
__PACKAGE__->mk_classaccessor('_loader_debug' => 0);

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

    $class->_loader_debug(1) if $args{debug};
    $class->_loader_inflect($args{inflect});
    $class->_loader_db_schema($args{db_schema} || '');
    $class->_loader_drop_db_schema($args{drop_db_schema});

    my $additional = $args{additional_classes} || [];
    $additional = [$additional] unless ref $additional eq 'ARRAY';

    my $additional_base = $args{additional_base_classes} || [];
    $additional_base = [$additional_base]
      unless ref $additional_base eq 'ARRAY';

    my $left_base = $args{left_base_classes} || [];
    $left_base = [$left_base] unless ref $left_base eq 'ARRAY';

    my %load_classes_args = (
        additional      => $additional,
        additional_base => $additional_base,
        left_base       => $left_base,
        constraint      => $args{constraint} || '.*',
        exclude         => $args{exclude},
    );

    $class->connection($args{dsn}, $args{user},
                       $args{password}, $args{options});

    warn qq/\### START DBIx::Class::Schema::Loader dump ###\n/
        if $class->_loader_debug;

    $class->_loader_load_classes(%load_classes_args);
    $class->_loader_relationships if $args{relationships};

    warn qq/\### END DBIx::Class::Schema::Loader dump ###\n/
        if $class->_loader_debug;
    $class->storage->dbh->disconnect; # XXX this should be ->storage->disconnect later?

    1;
}

# The original table class name during Loader,
sub _loader_find_table_class {
    my ( $class, $table ) = @_;
    return $class->_loader_classes->{$table};
}

# Returns the moniker for a given table name,
# for use in $conn->resultset($moniker)

=head3 moniker

Returns the moniker for a given literal table name.  Used
as $schema->resultset($moniker), etc.

=cut
sub moniker {
    my ( $class, $table ) = @_;
    return $class->_loader_monikers->{$table};
}

=head3 tables

Returns a sorted list of tables.

    my @tables = $loader->tables;

=cut

sub tables {
    my $class = shift;
    return sort keys %{ $class->_loader_monikers };
}

# Overload in your driver class
sub _loader_db_classes { croak "ABSTRACT METHOD" }

# not a class method.
sub _loader_stringify_hash {
    my $href = shift;

    return '{ ' .
           join(q{, }, map("$_ => $href->{$_}", keys %$href))
           . ' }';
}

# Setup has_a and has_many relationships
sub _loader_make_relations {

    my ( $class, $table, $other, $cond ) = @_;
    my $table_class = $class->_loader_find_table_class($table);
    my $other_class = $class->_loader_find_table_class($other);

    my $table_relname = lc $table;
    my $other_relname = lc $other;

    if(my $inflections = $class->_loader_inflect) {
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

    my $cond_printable = _loader_stringify_hash($cond)
        if $class->_loader_debug;
    my $rev_cond_printable = _loader_stringify_hash($rev_cond)
        if $class->_loader_debug;

    warn qq/\# Belongs_to relationship\n/ if $class->_loader_debug;

    warn qq/$table_class->belongs_to( '$other_relname' => '$other_class',/
      .  qq/$cond_printable);\n\n/
      if $class->_loader_debug;

    $table_class->belongs_to( $other_relname => $other_class, $cond);

    warn qq/\# Has_many relationship\n/ if $class->_loader_debug;

    warn qq/$other_class->has_many( '$table_relname' => '$table_class',/
      .  qq/$rev_cond_printable);\n\n/
      .  qq/);\n\n/
      if $class->_loader_debug;

    $other_class->has_many( $table_relname => $table_class, $rev_cond);
}

# Load and setup classes
sub _loader_load_classes {
    my ($class, %args)  = @_;

    my $additional      = join '',
                          map "use $_;\n", @{$args{additional}};

    my @tables          = $class->_loader_tables();
    my @db_classes      = $class->_loader_db_classes();

    foreach my $table (@tables) {
        next unless $table =~ /$args{constraint}/;
        next if defined $args{exclude} && $table =~ /$args{exclude}/;

        my ($db_schema, $tbl) = split /\./, $table;
        my $tablename = lc $table;
        if($tbl) {
            $tablename = $class->_loader_drop_db_schema ? $tbl : lc $table;
        }
	my $lc_tblname = lc $tablename;

        my $table_moniker = $class->_loader_table2moniker($db_schema, $tbl);
        my $table_class = "$class\::$table_moniker";

        # XXX all of this needs require/eval error checking
        $class->inject_base( $table_class, 'DBIx::Class::Core' );
        $_->require for @db_classes;
        $class->inject_base( $table_class, $_ ) for @db_classes;
        $class->inject_base( $table_class, $_ ) for @{$args{additional_base}};
        eval "package $table_class;$_;"         for @{$args{additional}};
        $class->inject_base( $table_class, $_ ) for @{$args{left_base}};

        warn qq/\# Initializing table "$tablename" as "$table_class"\n/ if $class->_loader_debug;
        $table_class->table($lc_tblname);

        my ( $cols, $pks ) = $class->_loader_table_info($table);
        carp("$table has no primary key") unless @$pks;
        $table_class->add_columns(@$cols);
        $table_class->set_primary_key(@$pks) if @$pks;

        warn qq/$table_class->table('$tablename');\n/ if $class->_loader_debug;
        my $columns = join "', '", @$cols;
        warn qq/$table_class->add_columns('$columns')\n/ if $class->_loader_debug;
        my $primaries = join "', '", @$pks;
        warn qq/$table_class->set_primary_key('$primaries')\n/ if $class->_loader_debug && @$pks;

        $class->register_class($table_moniker, $table_class);
        $class->_loader_classes->{$lc_tblname} = $table_class;
        $class->_loader_monikers->{$lc_tblname} = $table_moniker;
    }
}

# Find and setup relationships
sub _loader_relationships {
    my $class = shift;
    my $dbh = $class->storage->dbh;
    my $quoter = $dbh->get_info(29) || q{"};
    foreach my $table ( $class->tables ) {
        my $rels = {};
        my $sth = $dbh->foreign_key_info( '',
            $class->_loader_db_schema, '', '', '', $table );
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
            eval { $class->_loader_make_relations( $table, $reltbl, $cond ) };
              warn qq/\# belongs_to_many failed "$@"\n\n/
                if $@ && $class->_loader_debug;
        }
    }
}

# Make a moniker from a table
sub _loader_table2moniker {
    my ( $class, $db_schema, $table ) = @_;

    my $db_schema_ns;

    if($table) {
        $db_schema = ucfirst lc $db_schema;
        $db_schema_ns = $db_schema if(!$class->_loader_drop_db_schema);
    } else {
        $table = $db_schema;
    }

    my $moniker = join '', map ucfirst, split /[\W_]+/, lc $table;
    $moniker = $db_schema_ns ? $db_schema_ns . $moniker : $moniker;

    return $moniker;
}

# Overload in driver class
sub _loader_tables { croak "ABSTRACT METHOD" }

sub _loader_table_info { croak "ABSTRACT METHOD" }

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
