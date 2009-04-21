package DBIx::Class::Schema::Loader::DBI::Sybase;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI';
use Carp::Clan qw/^DBIx::Class/;
use Class::C3;

our $VERSION = '0.04999_06';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::Sybase - DBIx::Class::Schema::Loader::DBI Sybase Implementation.

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
    $self->{db_schema} ||= 'dbo';
}

sub _rebless {
    my $self = shift;

    my $dbh = $self->schema->storage->dbh;
    my $DBMS_VERSION = @{$dbh->selectrow_arrayref(qq{sp_server_info \@attribute_id=1})}[2];
    if ($DBMS_VERSION =~ /^Microsoft /i) {
        my $subclass = 'DBIx::Class::Schema::Loader::DBI::MSSQL';
        if ($self->load_optional_class($subclass) && !$self->isa($subclass)) {
            bless $self, $subclass;
            $self->_rebless;
      }
    }
}

sub _table_columns {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $columns = $dbh->selectcol_arrayref(qq{SELECT name FROM syscolumns WHERE id = (SELECT id FROM sysobjects WHERE name = '$table' AND type = 'U')});

    return $columns;
}

sub _table_pk_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{sp_pkeys '$table'});
    $sth->execute;

    my @keydata;

    while (my $row = $sth->fetchrow_hashref) {
        push @keydata, lc $row->{column_name};
    }

    return \@keydata;
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my ($local_cols, $remote_cols, $remote_table, @rels);
    my $dbh = $self->schema->storage->dbh;
    # hide "Object does not exist in this database." when trying to fetch fkeys
    $dbh->{syb_err_handler} = sub { return 0 if $_[0] == 17461; }; 
    my $sth = $dbh->prepare(qq{sp_fkeys \@FKTABLE_NAME = '$table'});
    $sth->execute;

    while (my $row = $sth->fetchrow_hashref) {
        next unless $row->{FK_NAME};
        my $fk = $row->{FK_NAME};
        push @{$local_cols->{$fk}}, lc $row->{FKCOLUMN_NAME};
        push @{$remote_cols->{$fk}}, lc $row->{PKCOLUMN_NAME};
        $remote_table->{$fk} = $row->{PKTABLE_NAME};
    }

    foreach my $fk (keys %$remote_table) {
        push @rels, {
                     local_columns => \@{$local_cols->{$fk}},
                     remote_columns => \@{$remote_cols->{$fk}},
                     remote_table => $remote_table->{$fk},
                    };

    }
    return \@rels;
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{sp_helpconstraint \@objname='$table', \@nomsg='nomsg'});
    $sth->execute;

    my $constraints;
    while (my $row = $sth->fetchrow_hashref) {
        my $type = $row->{constraint_type} || '';
        if ($type =~ /^unique/i) {
            my $name = lc $row->{constraint_name};
            push @{$constraints->{$name}}, ( split /,/, lc $row->{constraint_keys} );
        }
    }

    my @uniqs = map { [ $_ => $constraints->{$_} ] } keys %$constraints;
    return \@uniqs;
}

sub _extra_column_info {
    my ($self, $info) = @_;
    my %extra_info;

    my ($table, $column) = @$info{qw/TABLE_NAME COLUMN_NAME/};

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{SELECT name FROM syscolumns WHERE id = (SELECT id FROM sysobjects WHERE name = '$table') AND (status & 0x80) = 0x80 AND name = '$column'});
    $sth->execute();

    if ($sth->fetchrow_array) {
        $extra_info{is_auto_increment} = 1;
    }

    return \%extra_info;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>, L<DBIx::Class::Schema::Loader::Base>,
L<DBIx::Class::Schema::Loader::DBI>

=head1 AUTHOR

Justin Hunter C<justin.d.hunter@gmail.com>

=cut

1;
