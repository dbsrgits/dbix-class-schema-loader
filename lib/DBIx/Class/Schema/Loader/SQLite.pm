package DBIx::Class::Schema::Loader::SQLite;

use strict;
use warnings;
use base qw/DBIx::Class::Schema::Loader::Generic/;
use Class::C3;
use Text::Balanced qw( extract_bracketed );

=head1 NAME

DBIx::Class::Schema::Loader::SQLite - DBIx::Class::Schema::Loader SQLite Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->load_from_connection(
    dsn       => "dbi:SQLite:dbname=/path/to/dbfile",
  );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader>.

=cut

sub _db_classes {
    return qw/DBIx::Class::PK::Auto::SQLite/;
}

# XXX this really needs a re-factor
sub _load_relationships {
    my $self = shift;
    foreach my $table ( $self->tables ) {

        my $dbh = $self->schema->storage->dbh;
        my $sth = $dbh->prepare(<<"");
SELECT sql FROM sqlite_master WHERE tbl_name = ?

        $sth->execute($table);
        my ($sql) = $sth->fetchrow_array;
        $sth->finish;

        # Cut "CREATE TABLE ( )" blabla...
        $sql =~ /^[\w\s]+\((.*)\)$/si;
        my $cols = $1;

        # strip single-line comments
        $cols =~ s/\-\-.*\n/\n/g;

        # temporarily replace any commas inside parens,
        # so we don't incorrectly split on them below
        my $cols_no_bracketed_commas = $cols;
        while ( my $extracted =
            ( extract_bracketed( $cols, "()", "[^(]*" ) )[0] )
        {
            my $replacement = $extracted;
            $replacement              =~ s/,/--comma--/g;
            $replacement              =~ s/^\(//;
            $replacement              =~ s/\)$//;
            $cols_no_bracketed_commas =~ s/$extracted/$replacement/m;
        }

        # Split column definitions
        for my $col ( split /,/, $cols_no_bracketed_commas ) {

            # put the paren-bracketed commas back, to help
            # find multi-col fks below
            $col =~ s/\-\-comma\-\-/,/g;

            $col =~ s/^\s*FOREIGN\s+KEY\s*//i;

            # Strip punctuations around key and table names
            $col =~ s/[\[\]'"]/ /g;
            $col =~ s/^\s+//gs;

            # Grab reference
            chomp $col;
	    next if $col !~ /^(.*)\s+REFERENCES\s+(\w+) (?: \s* \( (.*) \) )? /ix;

            my ($cols, $f_table, $f_cols) = ($1, $2, $3);

            if($cols =~ /^\(/) { # Table-level
                $cols =~ s/^\(\s*//;
                $cols =~ s/\s*\)$//;
            }
            else {               # Inline
                $cols =~ s/\s+.*$//;
            }

            my $cond;

            if($f_cols) {
                my @cols = map { s/\s*//g; $_ } split(/\s*,\s*/,$cols);
                my @f_cols = map { s/\s*//g; $_ } split(/\s*,\s*/,$f_cols);
                die "Mismatched column count in rel for $table => $f_table"
                  if @cols != @f_cols;
                $cond = {};
                for(my $i = 0 ; $i < @cols; $i++) {
                    $cond->{$f_cols[$i]} = $cols[$i];
                }
                eval { $self->_make_cond_rel( $table, $f_table, $cond ) };
            }
            else {
                eval { $self->_make_simple_rel( $table, $f_table, $cols ) };
            }

            warn qq/\# belongs_to_many failed "$@"\n\n/
              if $@ && $self->debug;
        }
    }
}

sub _tables {
    my $self = shift;
    my $dbh = $self->schema->storage->dbh;
    my $sth  = $dbh->prepare("SELECT * FROM sqlite_master");
    $sth->execute;
    my @tables;
    while ( my $row = $sth->fetchrow_hashref ) {
        next unless lc( $row->{type} ) eq 'table';
        push @tables, $row->{tbl_name};
    }
    return @tables;
}

sub _table_info {
    my ( $self, $table ) = @_;

    # find all columns.
    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare("PRAGMA table_info('$table')");
    $sth->execute();
    my @columns;
    while ( my $row = $sth->fetchrow_hashref ) {
        push @columns, $row->{name};
    }
    $sth->finish;

    # find primary key. so complex ;-(
    $sth = $dbh->prepare(<<'SQL');
SELECT sql FROM sqlite_master WHERE tbl_name = ?
SQL
    $sth->execute($table);
    my ($sql) = $sth->fetchrow_array;
    $sth->finish;
    my ($primary) = $sql =~ m/
    (?:\(|\,) # either a ( to start the definition or a , for next
    \s*       # maybe some whitespace
    (\w+)     # the col name
    [^,]*     # anything but the end or a ',' for next column
    PRIMARY\sKEY/sxi;
    my @pks;

    if ($primary) {
        @pks = ($primary);
    }
    else {
        my ($pks) = $sql =~ m/PRIMARY\s+KEY\s*\(\s*([^)]+)\s*\)/i;
        @pks = split( m/\s*\,\s*/, $pks ) if $pks;
    }
    return ( \@columns, \@pks );
}

=head1 SEE ALSO

L<DBIx::Schema::Class::Loader>

=cut

1;
