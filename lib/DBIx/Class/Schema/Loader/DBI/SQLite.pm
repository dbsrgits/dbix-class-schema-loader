package DBIx::Class::Schema::Loader::DBI::SQLite;

use strict;
use warnings;
use base qw/
    DBIx::Class::Schema::Loader::DBI::Component::QuotedDefault
    DBIx::Class::Schema::Loader::DBI
/;
use Carp::Clan qw/^DBIx::Class/;
use Text::Balanced qw( extract_bracketed );
use Class::C3;

our $VERSION = '0.06000';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::SQLite - DBIx::Class::Schema::Loader::DBI SQLite Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options( debug => 1 );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader::Base>.

=head1 METHODS

=head2 rescan

SQLite will fail all further commands on a connection if the
underlying schema has been modified.  Therefore, any runtime
changes requiring C<rescan> also require us to re-connect
to the database.  The C<rescan> method here handles that
reconnection for you, but beware that this must occur for
any other open sqlite connections as well.

=cut

sub rescan {
    my ($self, $schema) = @_;

    $schema->storage->disconnect if $schema->storage;
    $self->next::method($schema);
}

sub _extra_column_info {
    my ($self, $table, $col_name, $info, $dbi_info) = @_;
    my %extra_info;

    my $dbh = $self->schema->storage->dbh;
    my $has_autoinc = eval {
      my $get_seq = $self->{_cache}{sqlite_sequence}
        ||= $dbh->prepare(q{SELECT count(*) FROM sqlite_sequence WHERE name = ?});
      $get_seq->execute($table);
      my ($ret) = $get_seq->fetchrow_array;
      $get_seq->finish;
      $ret;
    };

    if (!$@ && $has_autoinc) {
        my $sth = $dbh->prepare(
            "pragma table_info(" . $dbh->quote_identifier($table) . ")"
        );
        $sth->execute;
        my $cols = $sth->fetchall_hashref('name');
        if ($cols->{$col_name}{pk}) {
            $extra_info{is_auto_increment} = 1;
        }
    }

    return \%extra_info;
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(
        "pragma foreign_key_list(" . $dbh->quote_identifier($table) . ")"
    );
    $sth->execute;

    my @rels;
    while (my $fk = $sth->fetchrow_hashref) {
        my $rel = $rels[ $fk->{id} ] ||= {
            local_columns => [],
            remote_columns => undef,
            remote_table => lc $fk->{table}
        };

        push @{ $rel->{local_columns} }, lc $fk->{from};
        push @{ $rel->{remote_columns} }, lc $fk->{to} if defined $fk->{to};
        warn "This is supposed to be the same rel but remote_table changed from ",
            $rel->{remote_table}, " to ", $fk->{table}
            if $rel->{remote_table} ne lc $fk->{table};
    }
    $sth->finish;
    return \@rels;
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(
        "pragma index_list(" . $dbh->quote($table) . ")"
    );
    $sth->execute;

    my @uniqs;
    while (my $idx = $sth->fetchrow_hashref) {
        next unless $idx->{unique};
        my $name = $idx->{name};

        my $get_idx_sth = $dbh->prepare("pragma index_info(" . $dbh->quote($name) . ")");
        $get_idx_sth->execute;
        my @cols;
        while (my $idx_row = $get_idx_sth->fetchrow_hashref) {
            push @cols, lc $idx_row->{name};
        }
        $get_idx_sth->finish;
        push @uniqs, [ $name => \@cols ];
    }
    $sth->finish;
    return \@uniqs;
}

sub _tables_list {
    my ($self, $opts) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare("SELECT * FROM sqlite_master");
    $sth->execute;
    my @tables;
    while ( my $row = $sth->fetchrow_hashref ) {
        next unless $row->{type} =~ /^(?:table|view)\z/i;
        next if $row->{tbl_name} =~ /^sqlite_/;
        push @tables, $row->{tbl_name};
    }
    $sth->finish;
    return $self->_filter_tables(\@tables, $opts);
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
