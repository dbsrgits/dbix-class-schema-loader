package DBIx::Class::Schema::Loader::DBI::Sybase;

use strict;
use warnings;
use base qw/
    DBIx::Class::Schema::Loader::DBI
    DBIx::Class::Schema::Loader::DBI::Sybase::Common
/;
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

sub _is_case_sensitive { 1 }

sub _setup {
    my $self = shift;

    $self->next::method(@_);
    $self->{db_schema} ||= $self->_build_db_schema;
    $self->_set_quote_char_and_name_sep;
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
        push @keydata, $row->{column_name};
    }

    return \@keydata;
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my ($local_cols, $remote_cols, $remote_table, @rels);
    my $dbh = $self->schema->storage->dbh;

    local $dbh->{FetchHashKeyName} = 'NAME_lc';

    # hide "Object does not exist in this database." when trying to fetch fkeys
    $dbh->{syb_err_handler} = sub { return 0 if $_[0] == 17461; }; 
    my $sth = $dbh->prepare(qq{sp_fkeys \@fktable_name = '$table'});
    $sth->execute;

    while (my $row = $sth->fetchrow_hashref) {
        my $fk = $row->{fk_name} ||
'fk_'.$row->{fktable_name}.'_'.$row->{pktable_name};

        push @{$local_cols->{$fk}}, $row->{fkcolumn_name};
        push @{$remote_cols->{$fk}}, $row->{pkcolumn_name};
        $remote_table->{$fk} = $row->{pktable_name};
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
        if (exists $row->{constraint_type}) {
            my $type = $row->{constraint_type} || '';
            if ($type =~ /^unique/i) {
                my $name = $row->{constraint_name};
                push @{$constraints->{$name}},
                    ( split /,/, $row->{constraint_keys} );
            }
        } else {
            my $def = $row->{definition} || next;
            next unless $def =~ /^unique/i;
            my $name = $row->{name};
            my ($keys) = $def =~ /\((.*)\)/;
            $keys =~ s/\s*//g;
            my @keys = split /,/ => $keys;
            push @{$constraints->{$name}}, @keys;
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
