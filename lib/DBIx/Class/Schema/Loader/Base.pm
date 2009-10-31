package DBIx::Class::Schema::Loader::Base;

use strict;
use warnings;
use base qw/Class::Accessor::Fast Class::C3::Componentised/;
use Class::C3;
use Carp::Clan qw/^DBIx::Class/;
use DBIx::Class::Schema::Loader::RelBuilder;
use Data::Dump qw/ dump /;
use POSIX qw//;
use File::Spec qw//;
use Cwd qw//;
use Digest::MD5 qw//;
use Lingua::EN::Inflect::Number qw//;
use File::Temp qw//;
use Class::Unload;
require DBIx::Class;

our $VERSION = '0.04999_10';

__PACKAGE__->mk_ro_accessors(qw/
                                schema
                                schema_class

                                exclude
                                constraint
                                additional_classes
                                additional_base_classes
                                left_base_classes
                                components
                                resultset_components
                                skip_relationships
                                moniker_map
                                inflect_singular
                                inflect_plural
                                debug
                                dump_directory
                                dump_overwrite
                                really_erase_my_files
                                use_namespaces
                                result_namespace
                                resultset_namespace
                                default_resultset_class
                                schema_base_class
                                result_base_class

                                db_schema
                                _tables
                                classes
                                monikers
                             /);

=head1 NAME

DBIx::Class::Schema::Loader::Base - Base DBIx::Class::Schema::Loader Implementation.

=head1 SYNOPSIS

See L<DBIx::Class::Schema::Loader>

=head1 DESCRIPTION

This is the base class for the storage-specific C<DBIx::Class::Schema::*>
classes, and implements the common functionality between them.

=head1 CONSTRUCTOR OPTIONS

These constructor options are the base options for
L<DBIx::Class::Schema::Loader/loader_options>.  Available constructor options are:

=head2 skip_relationships

Skip setting up relationships.  The default is to attempt the loading
of relationships.

=head2 debug

If set to true, each constructive L<DBIx::Class> statement the loader
decides to execute will be C<warn>-ed before execution.

=head2 db_schema

Set the name of the schema to load (schema in the sense that your database
vendor means it).  Does not currently support loading more than one schema
name.

=head2 constraint

Only load tables matching regex.  Best specified as a qr// regex.

=head2 exclude

Exclude tables matching regex.  Best specified as a qr// regex.

=head2 moniker_map

Overrides the default table name to moniker translation.  Can be either
a hashref of table keys and moniker values, or a coderef for a translator
function taking a single scalar table name argument and returning
a scalar moniker.  If the hash entry does not exist, or the function
returns a false value, the code falls back to default behavior
for that table name.

The default behavior is: C<join '', map ucfirst, split /[\W_]+/, lc $table>,
which is to say: lowercase everything, split up the table name into chunks
anywhere a non-alpha-numeric character occurs, change the case of first letter
of each chunk to upper case, and put the chunks back together.  Examples:

    Table Name  | Moniker Name
    ---------------------------
    luser       | Luser
    luser_group | LuserGroup
    luser-opts  | LuserOpts

=head2 inflect_plural

Just like L</moniker_map> above (can be hash/code-ref, falls back to default
if hash key does not exist or coderef returns false), but acts as a map
for pluralizing relationship names.  The default behavior is to utilize
L<Lingua::EN::Inflect::Number/to_PL>.

=head2 inflect_singular

As L</inflect_plural> above, but for singularizing relationship names.
Default behavior is to utilize L<Lingua::EN::Inflect::Number/to_S>.

=head2 schema_base_class

Base class for your schema classes. Defaults to 'DBIx::Class::Schema'.

=head2 result_base_class

Base class for your table classes (aka result classes). Defaults to 'DBIx::Class'.

=head2 additional_base_classes

List of additional base classes all of your table classes will use.

=head2 left_base_classes

List of additional base classes all of your table classes will use
that need to be leftmost.

=head2 additional_classes

List of additional classes which all of your table classes will use.

=head2 components

List of additional components to be loaded into all of your table
classes.  A good example would be C<ResultSetManager>.

=head2 resultset_components

List of additional ResultSet components to be loaded into your table
classes.  A good example would be C<AlwaysRS>.  Component
C<ResultSetManager> will be automatically added to the above
C<components> list if this option is set.

=head2 use_namespaces

Generate result class names suitable for
L<DBIx::Class::Schema/load_namespaces> and call that instead of
L<DBIx::Class::Schema/load_classes>. When using this option you can also
specify any of the options for C<load_namespaces> (i.e. C<result_namespace>,
C<resultset_namespace>, C<default_resultset_class>), and they will be added
to the call (and the generated result class names adjusted appropriately).

=head2 dump_directory

This option is designed to be a tool to help you transition from this
loader to a manually-defined schema when you decide it's time to do so.

The value of this option is a perl libdir pathname.  Within
that directory this module will create a baseline manual
L<DBIx::Class::Schema> module set, based on what it creates at runtime
in memory.

The created schema class will have the same classname as the one on
which you are setting this option (and the ResultSource classes will be
based on this name as well).

Normally you wouldn't hard-code this setting in your schema class, as it
is meant for one-time manual usage.

See L<DBIx::Class::Schema::Loader/dump_to_dir> for examples of the
recommended way to access this functionality.

=head2 dump_overwrite

Deprecated.  See L</really_erase_my_files> below, which does *not* mean
the same thing as the old C<dump_overwrite> setting from previous releases.

=head2 really_erase_my_files

Default false.  If true, Loader will unconditionally delete any existing
files before creating the new ones from scratch when dumping a schema to disk.

The default behavior is instead to only replace the top portion of the
file, up to and including the final stanza which contains
C<# DO NOT MODIFY THIS OR ANYTHING ABOVE!>
leaving any customizations you placed after that as they were.

When C<really_erase_my_files> is not set, if the output file already exists,
but the aforementioned final stanza is not found, or the checksum
contained there does not match the generated contents, Loader will
croak and not touch the file.

You should really be using version control on your schema classes (and all
of the rest of your code for that matter).  Don't blame me if a bug in this
code wipes something out when it shouldn't have, you've been warned.

=head1 METHODS

None of these methods are intended for direct invocation by regular
users of L<DBIx::Class::Schema::Loader>.  Anything you can find here
can also be found via standard L<DBIx::Class::Schema> methods somehow.

=cut

# ensure that a peice of object data is a valid arrayref, creating
# an empty one or encapsulating whatever's there.
sub _ensure_arrayref {
    my $self = shift;

    foreach (@_) {
        $self->{$_} ||= [];
        $self->{$_} = [ $self->{$_} ]
            unless ref $self->{$_} eq 'ARRAY';
    }
}

=head2 new

Constructor for L<DBIx::Class::Schema::Loader::Base>, used internally
by L<DBIx::Class::Schema::Loader>.

=cut

sub new {
    my ( $class, %args ) = @_;

    my $self = { %args };

    bless $self => $class;

    $self->_ensure_arrayref(qw/additional_classes
                               additional_base_classes
                               left_base_classes
                               components
                               resultset_components
                              /);

    push(@{$self->{components}}, 'ResultSetManager')
        if @{$self->{resultset_components}};

    $self->{monikers} = {};
    $self->{classes} = {};

    $self->{schema_class} ||= ( ref $self->{schema} || $self->{schema} );
    $self->{schema} ||= $self->{schema_class};

    croak "dump_overwrite is deprecated.  Please read the"
        . " DBIx::Class::Schema::Loader::Base documentation"
            if $self->{dump_overwrite};

    $self->{dynamic} = ! $self->{dump_directory};
    $self->{temp_directory} ||= File::Temp::tempdir( 'dbicXXXX',
                                                     TMPDIR  => 1,
                                                     CLEANUP => 1,
                                                   );

    $self->{dump_directory} ||= $self->{temp_directory};

    $self->{relbuilder} = DBIx::Class::Schema::Loader::RelBuilder->new(
        $self->schema, $self->inflect_plural, $self->inflect_singular
    ) if !$self->{skip_relationships};

    $self;
}

sub _find_file_in_inc {
    my ($self, $file) = @_;

    foreach my $prefix (@INC) {
        my $fullpath = File::Spec->catfile($prefix, $file);
        return $fullpath if -f $fullpath
            and Cwd::abs_path($fullpath) ne
                Cwd::abs_path(File::Spec->catfile($self->dump_directory, $file)) || '';
    }

    return;
}

sub _load_external {
    my ($self, $class) = @_;

    my $class_path = $class;
    $class_path =~ s{::}{/}g;
    $class_path .= '.pm';

    my $real_inc_path = $self->_find_file_in_inc($class_path);

    return if !$real_inc_path;

    # If we make it to here, we loaded an external definition
    warn qq/# Loaded external class definition for '$class'\n/
        if $self->debug;

    croak 'Failed to locate actual external module file for '
          . "'$class'"
              if !$real_inc_path;
    open(my $fh, '<', $real_inc_path)
        or croak "Failed to open '$real_inc_path' for reading: $!";
    $self->_ext_stmt($class,
         qq|# These lines were loaded from '$real_inc_path' found in \@INC.\n|
        .qq|# They are now part of the custom portion of this file\n|
        .qq|# for you to hand-edit.  If you do not either delete\n|
        .qq|# this section or remove that file from \@INC, this section\n|
        .qq|# will be repeated redundantly when you re-create this\n|
        .qq|# file again via Loader!\n|
    );
    while(<$fh>) {
        chomp;
        $self->_ext_stmt($class, $_);
    }
    $self->_ext_stmt($class,
        qq|# End of lines loaded from '$real_inc_path' |
    );
    close($fh)
        or croak "Failed to close $real_inc_path: $!";
}

=head2 load

Does the actual schema-construction work.

=cut

sub load {
    my $self = shift;

    $self->_load_tables($self->_tables_list);
}

=head2 rescan

Arguments: schema

Rescan the database for newly added tables.  Does
not process drops or changes.  Returns a list of
the newly added table monikers.

The schema argument should be the schema class
or object to be affected.  It should probably
be derived from the original schema_class used
during L</load>.

=cut

sub rescan {
    my ($self, $schema) = @_;

    $self->{schema} = $schema;
    $self->{relbuilder}{schema} = $schema;

    my @created;
    my @current = $self->_tables_list;
    foreach my $table ($self->_tables_list) {
        if(!exists $self->{_tables}->{$table}) {
            push(@created, $table);
        }
    }

    my $loaded = $self->_load_tables(@created);

    return map { $self->monikers->{$_} } @$loaded;
}

sub _load_tables {
    my ($self, @tables) = @_;

    # First, use _tables_list with constraint and exclude
    #  to get a list of tables to operate on

    my $constraint   = $self->constraint;
    my $exclude      = $self->exclude;

    @tables = grep { /$constraint/ } @tables if $constraint;
    @tables = grep { ! /$exclude/ } @tables if $exclude;

    # Save the new tables to the tables list
    foreach (@tables) {
        $self->{_tables}->{$_} = 1;
    }

    $self->_make_src_class($_) for @tables;
    $self->_setup_src_meta($_) for @tables;

    if(!$self->skip_relationships) {
        # The relationship loader needs a working schema
        $self->{quiet} = 1;
        local $self->{dump_directory} = $self->{temp_directory};
        $self->_reload_classes(@tables);
        $self->_load_relationships($_) for @tables;
        $self->{quiet} = 0;

        # Remove that temp dir from INC so it doesn't get reloaded
        @INC = grep { $_ ne $self->{dump_directory} } @INC;
    }

    $self->_load_external($_)
        for map { $self->classes->{$_} } @tables;

    $self->_reload_classes(@tables);

    # Drop temporary cache
    delete $self->{_cache};

    return \@tables;
}

sub _reload_classes {
    my ($self, @tables) = @_;

    $self->_dump_to_dir(map { $self->classes->{$_} } @tables);

    unshift @INC, $self->dump_directory;
    
    my @to_register;
    my %have_source = map { $_ => $self->schema->source($_) }
        $self->schema->sources;

    for my $table (@tables) {
        my $moniker = $self->monikers->{$table};
        my $class = $self->classes->{$table};
        
        {
            no warnings 'redefine';
            local *Class::C3::reinitialize = sub {};
            use warnings;

            Class::Unload->unload($class);
            my ($source, $resultset_class);
            if (
                ($source = $have_source{$moniker})
                && ($resultset_class = $source->resultset_class)
                && ($resultset_class ne 'DBIx::Class::ResultSet')
            ) {
                my $has_file = Class::Inspector->loaded_filename($resultset_class);
                Class::Unload->unload($resultset_class);
                $self->ensure_class_loaded($resultset_class) if $has_file;
            }
            $self->ensure_class_loaded($class);
        }
        push @to_register, [$moniker, $class];
    }

    Class::C3->reinitialize;
    for (@to_register) {
        $self->schema->register_class(@$_);
    }
}

sub _get_dump_filename {
    my ($self, $class) = (@_);

    $class =~ s{::}{/}g;
    return $self->dump_directory . q{/} . $class . q{.pm};
}

sub _ensure_dump_subdirs {
    my ($self, $class) = (@_);

    my @name_parts = split(/::/, $class);
    pop @name_parts; # we don't care about the very last element,
                     # which is a filename

    my $dir = $self->dump_directory;
    while (1) {
        if(!-d $dir) {
            mkdir($dir) or croak "mkdir('$dir') failed: $!";
        }
        last if !@name_parts;
        $dir = File::Spec->catdir($dir, shift @name_parts);
    }
}

sub _dump_to_dir {
    my ($self, @classes) = @_;

    my $schema_class = $self->schema_class;
    my $schema_base_class = $self->schema_base_class || 'DBIx::Class::Schema';

    my $target_dir = $self->dump_directory;
    warn "Dumping manual schema for $schema_class to directory $target_dir ...\n"
        unless $self->{dynamic} or $self->{quiet};

    my $schema_text =
          qq|package $schema_class;\n\n|
        . qq|# Created by DBIx::Class::Schema::Loader\n|
        . qq|# DO NOT MODIFY THE FIRST PART OF THIS FILE\n\n|
        . qq|use strict;\nuse warnings;\n\n|
        . qq|use base '$schema_base_class';\n\n|;

    if ($self->use_namespaces) {
        $schema_text .= qq|__PACKAGE__->load_namespaces|;
        my $namespace_options;
        for my $attr (qw(result_namespace
                         resultset_namespace
                         default_resultset_class)) {
            if ($self->$attr) {
                $namespace_options .= qq|    $attr => '| . $self->$attr . qq|',\n|
            }
        }
        $schema_text .= qq|(\n$namespace_options)| if $namespace_options;
        $schema_text .= qq|;\n|;
    }
    else {
        $schema_text .= qq|__PACKAGE__->load_classes;\n|;
    }

    $self->_write_classfile($schema_class, $schema_text);

    my $result_base_class = $self->result_base_class || 'DBIx::Class';

    foreach my $src_class (@classes) {
        my $src_text = 
              qq|package $src_class;\n\n|
            . qq|# Created by DBIx::Class::Schema::Loader\n|
            . qq|# DO NOT MODIFY THE FIRST PART OF THIS FILE\n\n|
            . qq|use strict;\nuse warnings;\n\n|
            . qq|use base '$result_base_class';\n\n|;

        $self->_write_classfile($src_class, $src_text);
    }

    warn "Schema dump completed.\n" unless $self->{dynamic} or $self->{quiet};

}

sub _sig_comment {
    my ($self, $version, $ts) = @_;
    return qq|\n\n# Created by DBIx::Class::Schema::Loader|
         . qq| v| . $version
         . q| @ | . $ts 
         . qq|\n# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:|;
}

sub _write_classfile {
    my ($self, $class, $text) = @_;

    my $filename = $self->_get_dump_filename($class);
    $self->_ensure_dump_subdirs($class);

    if (-f $filename && $self->really_erase_my_files) {
        warn "Deleting existing file '$filename' due to "
            . "'really_erase_my_files' setting\n" unless $self->{quiet};
        unlink($filename);
    }    

    my ($custom_content, $old_md5, $old_ver, $old_ts) = $self->_get_custom_content($class, $filename);

    $text .= qq|$_\n|
        for @{$self->{_dump_storage}->{$class} || []};

    # Check and see if the dump is infact differnt

    my $compare_to;
    if ($old_md5) {
      $compare_to = $text . $self->_sig_comment($old_ver, $old_ts);
      

      if (Digest::MD5::md5_base64($compare_to) eq $old_md5) {
        return;
      }
    }

    $text .= $self->_sig_comment(
      $DBIx::Class::Schema::Loader::VERSION, 
      POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime)
    );

    open(my $fh, '>', $filename)
        or croak "Cannot open '$filename' for writing: $!";

    # Write the top half and its MD5 sum
    print $fh $text . Digest::MD5::md5_base64($text) . "\n";

    # Write out anything loaded via external partial class file in @INC
    print $fh qq|$_\n|
        for @{$self->{_ext_storage}->{$class} || []};

    # Write out any custom content the user has added
    print $fh $custom_content;

    close($fh)
        or croak "Error closing '$filename': $!";
}

sub _default_custom_content {
    return qq|\n\n# You can replace this text with custom|
         . qq| content, and it will be preserved on regeneration|
         . qq|\n1;\n|;
}

sub _get_custom_content {
    my ($self, $class, $filename) = @_;

    return ($self->_default_custom_content) if ! -f $filename;

    open(my $fh, '<', $filename)
        or croak "Cannot open '$filename' for reading: $!";

    my $mark_re = 
        qr{^(# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:)([A-Za-z0-9/+]{22})\n};

    my $buffer = '';
    my ($md5, $ts, $ver);
    while(<$fh>) {
        if(!$md5 && /$mark_re/) {
            $md5 = $2;
            my $line = $1;

            # Pull out the previous version and timestamp
            ($ver, $ts) = $buffer =~ m/# Created by DBIx::Class::Schema::Loader v(.*?) @ (.*?)$/s;

            $buffer .= $line;
            croak "Checksum mismatch in '$filename'"
                if Digest::MD5::md5_base64($buffer) ne $md5;

            $buffer = '';
        }
        else {
            $buffer .= $_;
        }
    }

    croak "Cannot not overwrite '$filename' without 'really_erase_my_files',"
        . " it does not appear to have been generated by Loader"
            if !$md5;

    # Default custom content:
    $buffer ||= $self->_default_custom_content;

    return ($buffer, $md5, $ver, $ts);
}

sub _use {
    my $self = shift;
    my $target = shift;

    foreach (@_) {
        warn "$target: use $_;" if $self->debug;
        $self->_raw_stmt($target, "use $_;");
    }
}

sub _inject {
    my $self = shift;
    my $target = shift;
    my $schema_class = $self->schema_class;

    my $blist = join(q{ }, @_);
    warn "$target: use base qw/ $blist /;" if $self->debug && @_;
    $self->_raw_stmt($target, "use base qw/ $blist /;") if @_;
}

# Create class with applicable bases, setup monikers, etc
sub _make_src_class {
    my ($self, $table) = @_;

    my $schema       = $self->schema;
    my $schema_class = $self->schema_class;

    my $table_moniker = $self->_table2moniker($table);
    my @result_namespace = ($schema_class);
    if ($self->use_namespaces) {
        my $result_namespace = $self->result_namespace || 'Result';
        if ($result_namespace =~ /^\+(.*)/) {
            # Fully qualified namespace
            @result_namespace =  ($1)
        }
        else {
            # Relative namespace
            push @result_namespace, $result_namespace;
        }
    }
    my $table_class = join(q{::}, @result_namespace, $table_moniker);

    my $table_normalized = lc $table;
    $self->classes->{$table} = $table_class;
    $self->classes->{$table_normalized} = $table_class;
    $self->monikers->{$table} = $table_moniker;
    $self->monikers->{$table_normalized} = $table_moniker;

    $self->_use   ($table_class, @{$self->additional_classes});
    $self->_inject($table_class, @{$self->left_base_classes});

    $self->_dbic_stmt($table_class, 'load_components', @{$self->components}, 'Core');

    $self->_dbic_stmt($table_class, 'load_resultset_components', @{$self->resultset_components})
        if @{$self->resultset_components};
    $self->_inject($table_class, @{$self->additional_base_classes});
}

# Set up metadata (cols, pks, etc)
sub _setup_src_meta {
    my ($self, $table) = @_;

    my $schema       = $self->schema;
    my $schema_class = $self->schema_class;

    my $table_class = $self->classes->{$table};
    my $table_moniker = $self->monikers->{$table};

    my $table_name = $table;
    my $name_sep   = $self->schema->storage->sql_maker->name_sep;

    if ($name_sep && $table_name =~ /\Q$name_sep\E/) {
        $table_name = \ $self->_quote_table_name($table_name);
    }

    $self->_dbic_stmt($table_class,'table',$table_name);

    my $cols = $self->_table_columns($table);
    my $col_info;
    eval { $col_info = $self->_columns_info_for($table) };
    if($@) {
        $self->_dbic_stmt($table_class,'add_columns',@$cols);
    }
    else {
        if ($self->_is_case_sensitive) {
            for my $col (keys %$col_info) {
                $col_info->{$col}{accessor} = lc $col
                    if $col ne lc($col);
            }
        } else {
            $col_info = { map { lc($_), $col_info->{$_} } keys %$col_info };
        }

        my $fks = $self->_table_fk_info($table);

        for my $fkdef (@$fks) {
            for my $col (@{ $fkdef->{local_columns} }) {
                $col_info->{$col}{is_foreign_key} = 1;
            }
        }
        $self->_dbic_stmt(
            $table_class,
            'add_columns',
            map { $_, ($col_info->{$_}||{}) } @$cols
        );
    }

    my %uniq_tag; # used to eliminate duplicate uniqs

    my $pks = $self->_table_pk_info($table) || [];
    @$pks ? $self->_dbic_stmt($table_class,'set_primary_key',@$pks)
          : carp("$table has no primary key");
    $uniq_tag{ join("\0", @$pks) }++ if @$pks; # pk is a uniq

    my $uniqs = $self->_table_uniq_info($table) || [];
    for (@$uniqs) {
        my ($name, $cols) = @$_;
        next if $uniq_tag{ join("\0", @$cols) }++; # skip duplicates
        $self->_dbic_stmt($table_class,'add_unique_constraint', $name, $cols);
    }

}

=head2 tables

Returns a sorted list of loaded tables, using the original database table
names.

=cut

sub tables {
    my $self = shift;

    return keys %{$self->_tables};
}

# Make a moniker from a table
sub _default_table2moniker {
    my ($self, $table) = @_;

    return join '', map ucfirst, split /[\W_]+/,
        Lingua::EN::Inflect::Number::to_S(lc $table);
}

sub _table2moniker {
    my ( $self, $table ) = @_;

    my $moniker;

    if( ref $self->moniker_map eq 'HASH' ) {
        $moniker = $self->moniker_map->{$table};
    }
    elsif( ref $self->moniker_map eq 'CODE' ) {
        $moniker = $self->moniker_map->($table);
    }

    $moniker ||= $self->_default_table2moniker($table);

    return $moniker;
}

sub _load_relationships {
    my ($self, $table) = @_;

    my $tbl_fk_info = $self->_table_fk_info($table);
    foreach my $fkdef (@$tbl_fk_info) {
        $fkdef->{remote_source} =
            $self->monikers->{delete $fkdef->{remote_table}};
    }
    my $tbl_uniq_info = $self->_table_uniq_info($table);

    my $local_moniker = $self->monikers->{$table};
    my $rel_stmts = $self->{relbuilder}->generate_code($local_moniker, $tbl_fk_info, $tbl_uniq_info);

    foreach my $src_class (sort keys %$rel_stmts) {
        my $src_stmts = $rel_stmts->{$src_class};
        foreach my $stmt (@$src_stmts) {
            $self->_dbic_stmt($src_class,$stmt->{method},@{$stmt->{args}});
        }
    }
}

# Overload these in driver class:

# Returns an arrayref of column names
sub _table_columns { croak "ABSTRACT METHOD" }

# Returns arrayref of pk col names
sub _table_pk_info { croak "ABSTRACT METHOD" }

# Returns an arrayref of uniqs [ [ foo => [ col1, col2 ] ], [ bar => [ ... ] ] ]
sub _table_uniq_info { croak "ABSTRACT METHOD" }

# Returns an arrayref of foreign key constraints, each
#   being a hashref with 3 keys:
#   local_columns (arrayref), remote_columns (arrayref), remote_table
sub _table_fk_info { croak "ABSTRACT METHOD" }

# Returns an array of lower case table names
sub _tables_list { croak "ABSTRACT METHOD" }

# Execute a constructive DBIC class method, with debug/dump_to_dir hooks.
sub _dbic_stmt {
    my $self = shift;
    my $class = shift;
    my $method = shift;

    my $args = dump(@_);
    $args = '(' . $args . ')' if @_ < 2;
    my $stmt = $method . $args . q{;};

    warn qq|$class\->$stmt\n| if $self->debug;
    $self->_raw_stmt($class, '__PACKAGE__->' . $stmt);
}

# Store a raw source line for a class (for dumping purposes)
sub _raw_stmt {
    my ($self, $class, $stmt) = @_;
    push(@{$self->{_dump_storage}->{$class}}, $stmt);
}

# Like above, but separately for the externally loaded stuff
sub _ext_stmt {
    my ($self, $class, $stmt) = @_;
    push(@{$self->{_ext_storage}->{$class}}, $stmt);
}

sub _quote_table_name {
    my ($self, $table) = @_;

    my $qt = $self->schema->storage->sql_maker->quote_char;

    return $table unless $qt;

    if (ref $qt) {
        return $qt->[0] . $table . $qt->[1];
    }

    return $qt . $table . $qt;
}

sub _is_case_sensitive { 0 }

=head2 monikers

Returns a hashref of loaded table to moniker mappings.  There will
be two entries for each table, the original name and the "normalized"
name, in the case that the two are different (such as databases
that like uppercase table names, or preserve your original mixed-case
definitions, or what-have-you).

=head2 classes

Returns a hashref of table to class mappings.  In some cases it will
contain multiple entries per table for the original and normalized table
names, as above in L</monikers>.

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
