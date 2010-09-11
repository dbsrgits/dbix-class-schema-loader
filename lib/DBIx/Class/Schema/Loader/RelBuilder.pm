package DBIx::Class::Schema::Loader::RelBuilder;

use strict;
use warnings;
use mro 'c3';
use Carp::Clan qw/^DBIx::Class/;
use Scalar::Util ();

use Lingua::EN::Inflect::Phrase ();
use DBIx::Class::Schema::Loader::Utils 'split_name';

our $VERSION = '0.07002';

=head1 NAME

DBIx::Class::Schema::Loader::RelBuilder - Builds relationships for DBIx::Class::Schema::Loader

=head1 SYNOPSIS

See L<DBIx::Class::Schema::Loader> and L<DBIx::Class::Schema::Loader::Base>.

=head1 DESCRIPTION

This class builds relationships for L<DBIx::Class::Schema::Loader>.  This
is module is not (yet) for external use.

=head1 METHODS

=head2 new

Arguments: $base object

=head2 generate_code

Arguments: local_moniker (scalar), fk_info (arrayref)

This generates the code for the relationships of a given table.

C<local_moniker> is the moniker name of the table which had the REFERENCES
statements.  The fk_info arrayref's contents should take the form:

    [
        {
            local_columns => [ 'col2', 'col3' ],
            remote_columns => [ 'col5', 'col7' ],
            remote_moniker => 'AnotherTableMoniker',
        },
        {
            local_columns => [ 'col1', 'col4' ],
            remote_columns => [ 'col1', 'col2' ],
            remote_moniker => 'YetAnotherTableMoniker',
        },
        # ...
    ],

This method will return the generated relationships as a hashref keyed on the
class names.  The values are arrayrefs of hashes containing method name and
arguments, like so:

  {
      'Some::Source::Class' => [
          { method => 'belongs_to', arguments => [ 'col1', 'Another::Source::Class' ],
          { method => 'has_many', arguments => [ 'anothers', 'Yet::Another::Source::Class', 'col15' ],
      ],
      'Another::Source::Class' => [
          # ...
      ],
      # ...
  }

=cut


sub new {
    my ( $class, $base ) = @_;

    # from old POD about this constructor:
    # C<$schema_class> should be a schema class name, where the source
    # classes have already been set up and registered.  Column info,
    # primary key, and unique constraints will be drawn from this
    # schema for all of the existing source monikers.

    # Options inflect_plural and inflect_singular are optional, and
    # are better documented in L<DBIx::Class::Schema::Loader::Base>.

    my $self = {
        base               => $base,
        schema             => $base->schema,
        inflect_plural     => $base->inflect_plural,
        inflect_singular   => $base->inflect_singular,
        relationship_attrs => $base->relationship_attrs,
    };

    Scalar::Util::weaken $self->{base}; #< don't leak

    # validate the relationship_attrs arg
    if( defined $self->{relationship_attrs} ) {
	ref $self->{relationship_attrs} eq 'HASH'
	    or croak "relationship_attrs must be a hashref";
    }

    return bless $self => $class;
}


# pluralize a relationship name
sub _inflect_plural {
    my ($self, $relname) = @_;

    return '' if !defined $relname || $relname eq '';

    if( ref $self->{inflect_plural} eq 'HASH' ) {
        return $self->{inflect_plural}->{$relname}
            if exists $self->{inflect_plural}->{$relname};
    }
    elsif( ref $self->{inflect_plural} eq 'CODE' ) {
        my $inflected = $self->{inflect_plural}->($relname);
        return $inflected if $inflected;
    }

    return $self->_to_PL($relname);
}

# Singularize a relationship name
sub _inflect_singular {
    my ($self, $relname) = @_;

    return '' if !defined $relname || $relname eq '';

    if( ref $self->{inflect_singular} eq 'HASH' ) {
        return $self->{inflect_singular}->{$relname}
            if exists $self->{inflect_singular}->{$relname};
    }
    elsif( ref $self->{inflect_singular} eq 'CODE' ) {
        my $inflected = $self->{inflect_singular}->($relname);
        return $inflected if $inflected;
    }

    return $self->_to_S($relname);
}

sub _to_PL {
    my ($self, $name) = @_;

    $name =~ s/_/ /g;
    my $plural = Lingua::EN::Inflect::Phrase::to_PL($name);
    $plural =~ s/ /_/g;

    return $plural;
}

sub _to_S {
    my ($self, $name) = @_;

    $name =~ s/_/ /g;
    my $singular = Lingua::EN::Inflect::Phrase::to_S($name);
    $singular =~ s/ /_/g;

    return $singular;
}

sub _default_relationship_attrs { +{
    has_many => {
        cascade_delete => 0,
        cascade_copy   => 0,
    },
    might_have => {
        cascade_delete => 0,
        cascade_copy   => 0,
    },
    belongs_to => {
        on_delete => 'CASCADE',
        on_update => 'CASCADE',
        is_deferrable => 1,
    },
} }

# accessor for options to be passed to each generated relationship
# type.  take single argument, the relationship type name, and returns
# either a hashref (if some options are set), or nothing
sub _relationship_attrs {
    my ( $self, $reltype ) = @_;
    my $r = $self->{relationship_attrs};

    my %composite = (
        %{ $self->_default_relationship_attrs->{$reltype} || {} },
        %{ $r->{all} || {} }
    );

    if( my $specific = $r->{$reltype} ) {
	while( my ($k,$v) = each %$specific ) {
	    $composite{$k} = $v;
	}
    }
    return \%composite;
}

sub _array_eq {
    my ($self, $a, $b) = @_;

    return unless @$a == @$b;

    for (my $i = 0; $i < @$a; $i++) {
        return unless $a->[$i] eq $b->[$i];
    }
    return 1;
}

sub _remote_attrs {
    my ($self, $local_moniker, $local_cols) = @_;

    # get our base set of attrs from _relationship_attrs, if present
    my $attrs = $self->_relationship_attrs('belongs_to') || {};

    # If the referring column is nullable, make 'belongs_to' an
    # outer join, unless explicitly set by relationship_attrs
    my $nullable = grep { $self->{schema}->source($local_moniker)->column_info($_)->{is_nullable} } @$local_cols;
    $attrs->{join_type} = 'LEFT' if $nullable && !defined $attrs->{join_type};

    return $attrs;
}

sub _sanitize_name {
    my ($self, $name) = @_;

    if (ref $name) {
        # scalar ref for weird table name (like one containing a '.')
        ($name = $$name) =~ s/\W+/_/g;
    }
    else {
        # remove 'schema.' prefix if any
        $name =~ s/^[^.]+\.//;
    }

    return $name;
}

sub _normalize_name {
    my ($self, $name) = @_;

    $name = $self->_sanitize_name($name);

    my @words = split_name $name;

    return join '_', map lc, @words;
}

sub _remote_relname {
    my ($self, $remote_table, $cond) = @_;

    my $remote_relname;
    # for single-column case, set the remote relname to the column
    # name, to make filter accessors work, but strip trailing _id
    if(scalar keys %{$cond} == 1) {
        my ($col) = values %{$cond};
        $col = $self->_normalize_name($col);
        $col =~ s/_id$//;
        $remote_relname = $self->_inflect_singular($col);
    }
    else {
        $remote_relname = $self->_inflect_singular($self->_normalize_name($remote_table));
    }

    return $remote_relname;
}

sub generate_code {
    my ($self, $local_moniker, $rels, $uniqs) = @_;

    my $all_code = {};

    my $local_class = $self->{schema}->class($local_moniker);

    my %counters;
    foreach my $rel (@$rels) {
        next if !$rel->{remote_source};
        $counters{$rel->{remote_source}}++;
    }

    foreach my $rel (@$rels) {
        my $remote_moniker = $rel->{remote_source}
            or next;

        my $remote_class   = $self->{schema}->class($remote_moniker);
        my $remote_obj     = $self->{schema}->source($remote_moniker);
        my $remote_cols    = $rel->{remote_columns} || [ $remote_obj->primary_columns ];

        my $local_cols     = $rel->{local_columns};

        if($#$local_cols != $#$remote_cols) {
            croak "Column count mismatch: $local_moniker (@$local_cols) "
                . "$remote_moniker (@$remote_cols)";
        }

        my %cond;
        foreach my $i (0 .. $#$local_cols) {
            $cond{$remote_cols->[$i]} = $local_cols->[$i];
        }

        my ( $local_relname, $remote_relname, $remote_method ) =
            $self->_relnames_and_method( $local_moniker, $rel, \%cond,  $uniqs, \%counters );

        push(@{$all_code->{$local_class}},
            { method => 'belongs_to',
              args => [ $remote_relname,
                        $remote_class,
                        \%cond,
                        $self->_remote_attrs($local_moniker, $local_cols),
              ],
            }
        );

        my %rev_cond = reverse %cond;
        for (keys %rev_cond) {
            $rev_cond{"foreign.$_"} = "self.".$rev_cond{$_};
            delete $rev_cond{$_};
        }

        push(@{$all_code->{$remote_class}},
            { method => $remote_method,
              args => [ $local_relname,
                        $local_class,
                        \%rev_cond,
			$self->_relationship_attrs($remote_method),
              ],
            }
        );
    }

    return $all_code;
}

sub _relnames_and_method {
    my ( $self, $local_moniker, $rel, $cond, $uniqs, $counters ) = @_;

    my $remote_moniker = $rel->{remote_source};
    my $remote_obj     = $self->{schema}->source( $remote_moniker );
    my $remote_class   = $self->{schema}->class(  $remote_moniker );
    my $remote_relname = $self->_remote_relname( $remote_obj->from, $cond);

    my $local_cols  = $rel->{local_columns};
    my $local_table = $self->{schema}->source($local_moniker)->from;

    # If more than one rel between this pair of tables, use the local
    # col names to distinguish
    my ($local_relname, $local_relname_uninflected);
    if ( $counters->{$remote_moniker} > 1) {
        my $colnames = q{_} . $self->_normalize_name(join '_', @$local_cols);
        $remote_relname .= $colnames if keys %$cond > 1;

        $local_relname = $self->_normalize_name($local_table . $colnames);
        $local_relname =~ s/_id$//;

        $local_relname_uninflected = $local_relname;
        $local_relname = $self->_inflect_plural($local_relname);
    } else {
        $local_relname_uninflected = $self->_normalize_name($local_table);
        $local_relname = $self->_inflect_plural($self->_normalize_name($local_table));
    }

    my $remote_method = 'has_many';

    # If the local columns have a UNIQUE constraint, this is a one-to-one rel
    my $local_source = $self->{schema}->source($local_moniker);
    if ($self->_array_eq([ $local_source->primary_columns ], $local_cols) ||
            grep { $self->_array_eq($_->[1], $local_cols) } @$uniqs) {
        $remote_method = 'might_have';
        $local_relname = $self->_inflect_singular($local_relname_uninflected);
    }

    return ( $local_relname, $remote_relname, $remote_method );
}

=head1 AUTHOR

See L<DBIx::Class::Schema::Loader/AUTHOR> and L<DBIx::Class::Schema::Loader/CONTRIBUTORS>.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
# vim:et sts=4 sw=4 tw=0:
