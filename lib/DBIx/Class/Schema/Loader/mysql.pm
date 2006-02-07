package DBIx::Class::Schema::Loader::mysql;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::Generic';
use Class::C3;

=head1 NAME

DBIx::Class::Schema::Loader::mysql - DBIx::Schema::Class::Loader mysql Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->load_from_connection(
    dsn       => "dbi:mysql:dbname",
    user      => "root",
    password  => "",
  );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader>.

=cut

sub _db_classes {
    return qw/DBIx::Class::PK::Auto::MySQL/;
}

sub _load_relationships {
    my $self   = shift;
    my @tables = $self->tables;
    my $dbh    = $self->schema->storage->dbh;

    my $quoter = $dbh->get_info(29) || q{`};

    foreach my $table (@tables) {
        my $query = "SHOW CREATE TABLE ${table}";
        my $sth   = $dbh->prepare($query)
          or die("Cannot get table definition: $table");
        $sth->execute;
        my $table_def = $sth->fetchrow_arrayref->[1] || '';
        
        my (@reldata) = ($table_def =~ /CONSTRAINT `.*` FOREIGN KEY \(`(.*)`\) REFERENCES `(.*)` \(`(.*)`\)/ig);

        while (scalar @reldata > 0) {
            my $cols = shift @reldata;
            my $f_table = shift @reldata;
            my $f_cols = shift @reldata;

            my @cols = map { s/$quoter//; $_ } split(/\s*,\s*/,$cols);
            my @f_cols = map { s/$quoter//; $_ } split(/\s*,\s*/,$f_cols);
            die "Mismatched column count in rel for $table => $f_table"
              if @cols != @f_cols;
            
            my $cond = {};
            for(my $i = 0; $i < @cols; $i++) {
                $cond->{$f_cols[$i]} = $cols[$i];
            }

            eval { $self->_make_cond_rel( $table, $f_table, $cond) };
            warn qq/\# belongs_to_many failed "$@"\n\n/ if $@ && $self->debug;
        }
        
        $sth->finish;
    }
}

sub _tables {
    my $self = shift;
    my $dbh    = $self->schema->storage->dbh;
    my @tables;
    my $quoter = $dbh->get_info(29) || q{`};
    foreach my $table ( $dbh->tables ) {
        $table =~ s/$quoter//g;
        push @tables, $1
          if $table =~ /\A(\w+)\z/;
    }
    return @tables;
}

sub _table_info {
    my ( $self, $table ) = @_;
    my $dbh    = $self->schema->storage->dbh;

    # MySQL 4.x doesn't support quoted tables
    my $query = "DESCRIBE $table";
    my $sth = $dbh->prepare($query) or die("Cannot get table status: $table");
    $sth->execute;
    my ( @cols, @pri );
    while ( my $hash = $sth->fetchrow_hashref ) {
        my ($col) = $hash->{Field} =~ /(\w+)/;
        push @cols, $col;
        push @pri, $col if $hash->{Key} eq "PRI";
    }

    return ( \@cols, \@pri );
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
