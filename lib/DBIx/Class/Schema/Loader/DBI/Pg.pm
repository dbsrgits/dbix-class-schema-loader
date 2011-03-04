package DBIx::Class::Schema::Loader::DBI::Pg;

use strict;
use warnings;
use base qw/
    DBIx::Class::Schema::Loader::DBI::Component::QuotedDefault
    DBIx::Class::Schema::Loader::DBI
/;
use Carp::Clan qw/^DBIx::Class/;
use mro 'c3';

our $VERSION = '0.07010';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::Pg - DBIx::Class::Schema::Loader::DBI
PostgreSQL Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options( debug => 1 );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader::Base>.

=cut

sub _setup {
    my $self = shift;

    $self->next::method(@_);

    $self->{db_schema} ||= 'public';

    if (not defined $self->preserve_case) {
        $self->preserve_case(0);
    }
    elsif ($self->preserve_case) {
        $self->schema->storage->sql_maker->quote_char('"');
        $self->schema->storage->sql_maker->name_sep('.');
    }
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    # Use the default support if available
    return $self->next::method($table)
        if $DBD::Pg::VERSION >= 1.50;

    my @uniqs;
    my $dbh = $self->schema->storage->dbh;

    # Most of the SQL here is mostly based on
    #   Rose::DB::Object::Metadata::Auto::Pg, after some prodding from
    #   John Siracusa to use his superior SQL code :)

    my $attr_sth = $self->{_cache}->{pg_attr_sth} ||= $dbh->prepare(
        q{SELECT attname FROM pg_catalog.pg_attribute
        WHERE attrelid = ? AND attnum = ?}
    );

    my $uniq_sth = $self->{_cache}->{pg_uniq_sth} ||= $dbh->prepare(
        q{SELECT x.indrelid, i.relname, x.indkey
        FROM
          pg_catalog.pg_index x
          JOIN pg_catalog.pg_class c ON c.oid = x.indrelid
          JOIN pg_catalog.pg_class i ON i.oid = x.indexrelid
          JOIN pg_catalog.pg_constraint con ON con.conname = i.relname
          LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE
          x.indisunique = 't' AND
          c.relkind     = 'r' AND
          i.relkind     = 'i' AND
          con.contype   = 'u' AND
          n.nspname     = ? AND
          c.relname     = ?}
    );

    $uniq_sth->execute($self->db_schema, $table);
    while(my $row = $uniq_sth->fetchrow_arrayref) {
        my ($tableid, $indexname, $col_nums) = @$row;
        $col_nums =~ s/^\s+//;
        my @col_nums = split(/\s+/, $col_nums);
        my @col_names;

        foreach (@col_nums) {
            $attr_sth->execute($tableid, $_);
            my $name_aref = $attr_sth->fetchrow_arrayref;
            push(@col_names, $name_aref->[0]) if $name_aref;
        }

        if(!@col_names) {
            warn "Failed to parse UNIQUE constraint $indexname on $table";
        }
        else {
            push(@uniqs, [ $indexname => \@col_names ]);
        }
    }

    return \@uniqs;
}

sub _table_comment {
    my ( $self, $table ) = @_;
     my ($table_comment) = $self->schema->storage->dbh->selectrow_array(
        q{SELECT obj_description(oid) 
            FROM pg_class 
            WHERE relname=? AND relnamespace=(
                SELECT oid FROM pg_namespace WHERE nspname=?)
        }, undef, $table, $self->db_schema
        );   
    return $table_comment
}


sub _column_comment {
    my ( $self, $table, $column_number ) = @_;
     my ($table_oid) = $self->schema->storage->dbh->selectrow_array(
        q{SELECT oid
            FROM pg_class 
            WHERE relname=? AND relnamespace=(
                SELECT oid FROM pg_namespace WHERE nspname=?)
        }, undef, $table, $self->db_schema
        );   
    return $self->schema->storage->dbh->selectrow_array('SELECT col_description(?,?)', undef, $table_oid,
    $column_number );
}

# Make sure data_type's that don't need it don't have a 'size' column_info, and
# set the correct precision for datetime and varbit types.
sub _columns_info_for {
    my $self = shift;
    my ($table) = @_;

    my $result = $self->next::method(@_);

    while (my ($col, $info) = each %$result) {
        my $data_type = $info->{data_type};

        # these types are fixed size
        # XXX should this be a negative match?
        if ($data_type =~
/^(?:bigint|int8|bigserial|serial8|boolean|bool|box|bytea|cidr|circle|date|double precision|float8|inet|integer|int|int4|line|lseg|macaddr|money|path|point|polygon|real|float4|smallint|int2|serial|serial4|text)\z/i) {
            delete $info->{size};
        }
# for datetime types, check if it has a precision or not
        elsif ($data_type =~ /^(?:interval|time|timestamp)\b/i) {
            if (lc($data_type) eq 'timestamp without time zone') {
                $info->{data_type} = 'timestamp';
            }
            elsif (lc($data_type) eq 'time without time zone') {
                $info->{data_type} = 'time';
            }

            my ($precision) = $self->schema->storage->dbh
                ->selectrow_array(<<EOF, {}, $table, $col);
SELECT datetime_precision
FROM information_schema.columns
WHERE table_name = ? and column_name = ?
EOF

            if ($data_type =~ /^time\b/i) {
                if ((not $precision) || $precision !~ /^\d/) {
                    delete $info->{size};
                }
                else {
                    my ($integer_datetimes) = $self->schema->storage->dbh
                        ->selectrow_array('show integer_datetimes');

                    my $max_precision =
                        $integer_datetimes =~ /^on\z/i ? 6 : 10;

                    if ($precision == $max_precision) {
                        delete $info->{size};
                    }
                    else {
                        $info->{size} = $precision;
                    }
                }
            }
            elsif ((not $precision) || $precision !~ /^\d/ || $precision == 6) {
                delete $info->{size};
            }
            else {
                $info->{size} = $precision;
            }
        }
        elsif ($data_type =~ /^(?:bit(?: varying)?|varbit)\z/i) {
            $info->{data_type} = 'varbit' if $data_type =~ /var/i;

            my ($precision) = $self->schema->storage->dbh
                ->selectrow_array(<<EOF, {}, $table, $col);
SELECT character_maximum_length
FROM information_schema.columns
WHERE table_name = ? and column_name = ?
EOF

            $info->{size} = $precision if $precision;

            $info->{size} = 1 if (not $precision) && lc($data_type) eq 'bit';
        }
        elsif ($data_type =~ /^(?:numeric|decimal)\z/i && (my $size = $info->{size})) {
            $size =~ s/\s*//g;

            my ($scale, $precision) = split /,/, $size;

            $info->{size} = [ $precision, $scale ];
        }
        elsif (lc($data_type) eq 'character varying') {
            $info->{data_type} = 'varchar';

            if (not $info->{size}) {
                $info->{data_type}           = 'text';
                $info->{original}{data_type} = 'varchar';
            }
        }
        elsif (lc($data_type) eq 'character') {
            $info->{data_type} = 'char';
        }
        else {
            my ($typetype) = $self->schema->storage->dbh
                ->selectrow_array(<<EOF, {}, $data_type);
SELECT typtype
FROM pg_catalog.pg_type
WHERE typname = ?
EOF
            if ($typetype eq 'e') {
                # The following will extract a list of allowed values for the
                # enum.
                my $typevalues = $self->schema->storage->dbh
                    ->selectall_arrayref(<<EOF, {}, $info->{data_type});
SELECT e.enumlabel
FROM pg_catalog.pg_enum e
JOIN pg_catalog.pg_type t ON t.oid = e.enumtypid
WHERE t.typname = ?
EOF

                $info->{extra}{list} = [ map { $_->[0] } @$typevalues ];

                # Store its original name in extra for SQLT to pick up.
                $info->{extra}{custom_type_name} = $info->{data_type};

                $info->{data_type} = 'enum';
                
                delete $info->{size};
            }
        }

# process SERIAL columns
        if (ref($info->{default_value}) eq 'SCALAR' && ${ $info->{default_value} } =~ /\bnextval\(['"]([.\w]+)/i) {
            $info->{is_auto_increment} = 1;
            $info->{sequence}          = $1;
            delete $info->{default_value};
        }

# alias now() to current_timestamp for deploying to other DBs
        if ((eval { lc ${ $info->{default_value} } }||'') eq 'now()') {
            # do not use a ref to a constant, that breaks Data::Dump output
            ${$info->{default_value}} = 'current_timestamp';

            my $now = 'now()';
            $info->{original}{default_value} = \$now;
        }
    }

    return $result;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>, L<DBIx::Class::Schema::Loader::Base>,
L<DBIx::Class::Schema::Loader::DBI>

=head1 AUTHOR

See L<DBIx::Class::Schema::Loader/AUTHOR> and L<DBIx::Class::Schema::Loader/CONTRIBUTORS>.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
