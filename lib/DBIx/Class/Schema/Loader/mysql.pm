package DBIx::Class::Schema::Loader::mysql;

use strict;
use base 'DBIx::Class::Schema::Loader::Generic';
use Carp;

=head1 NAME

DBIx::Class::Schema::Loader::mysql - DBIx::Schema::Class::Loader mysql Implementation.

=head1 SYNOPSIS

  use DBIx::Class::Schema::Loader;

  # $loader is a DBIx::Class::Schema::Loader::mysql
  my $loader = DBIx::Class::Schema::Loader->new(
    dsn       => "dbi:mysql:dbname",
    user      => "root",
    password  => "",
  );

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader>.

=cut

sub _db_classes {
    return qw/DBIx::Class::PK::Auto::MySQL/;
}

sub _relationships {
    my $class   = shift;
    my @tables = $class->tables;
    my $dbh    = $class->storage->dbh;
    my $dsn    = $class->loader_data->{_datasource}[0];
    my %conn   =
      $dsn =~ m/\Adbi:\w+(?:\(.*?\))?:(.+)\z/i
      && index( $1, '=' ) >= 0
      ? split( /[=;]/, $1 )
      : ( database => $1 );
    my $dbname = $conn{database} || $conn{dbname} || $conn{db};
    die("Can't figure out the table name automatically.") if !$dbname;

    my $quoter = $dbh->get_info(29);

    foreach my $table (@tables) {
        my $query = "SHOW CREATE TABLE ${dbname}.${table}";
        my $sth   = $dbh->prepare($query)
          or die("Cannot get table definition: $table");
        $sth->execute;
        my $table_def = $sth->fetchrow_arrayref->[1] || '';
        
        my (@reldata) = ($table_def =~ /CONSTRAINT `.*` FOREIGN KEY \(`(.*)`\) REFERENCES `(.*)` \(`(.*)`\)/g);

        while (scalar @reldata > 0) {
            my $cols = shift @reldata;
            my $f_table = shift @reldata;
            my $f_cols = shift @reldata;

            my @cols = map { s/$quoter//; $_ } split(/\s*,\s*/,$cols);
            my @f_cols = map { s/$quoter//; $_ } split(/\s*,\s*/,$f_cols);
            die "Mismatched column count in rel for $table => $f_table"
              if @cols != @f_cols;
            
            my $cond = {};
            for(my $i = 0 ; $i < @cols; $i++) {
                $cond->{$f_cols[$i]} = $cols[$i];
            }

            eval { $class->_belongs_to_many( $table, $f_table, $cond) };
            warn qq/\# belongs_to_many failed "$@"\n\n/ if $@ && $class->debug_loader;
        }
        
        $sth->finish;
    }
}

sub _tables {
    my $class = shift;
    my $dbh    = $class->storage->dbh;
    my @tables;
    foreach my $table ( $dbh->tables ) {
        my $quoter = $dbh->get_info(29);
        $table =~ s/$quoter//g if ($quoter);
        push @tables, $1
          if $table =~ /\A(\w+)\z/;
    }
    return @tables;
}

sub _table_info {
    my ( $class, $table ) = @_;
    my $dbh    = $class->storage->dbh;

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
