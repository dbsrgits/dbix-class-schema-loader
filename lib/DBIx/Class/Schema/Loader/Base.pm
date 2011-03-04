package DBIx::Class::Schema::Loader::Base;

use strict;
use warnings;
use base qw/Class::Accessor::Grouped Class::C3::Componentised/;
use mro 'c3';
use Carp::Clan qw/^DBIx::Class/;
use DBIx::Class::Schema::Loader::RelBuilder;
use Data::Dump qw/ dump /;
use POSIX qw//;
use File::Spec qw//;
use Cwd qw//;
use Digest::MD5 qw//;
use Lingua::EN::Inflect::Number qw//;
use Lingua::EN::Inflect::Phrase qw//;
use File::Temp qw//;
use Class::Unload;
use Class::Inspector ();
use Scalar::Util 'looks_like_number';
use File::Slurp 'slurp';
use DBIx::Class::Schema::Loader::Utils qw/split_name dumper_squashed eval_without_redefine_warnings/;
use DBIx::Class::Schema::Loader::Optional::Dependencies ();
use Try::Tiny;
use DBIx::Class ();
use Class::Load 'load_class';
use namespace::clean;

our $VERSION = '0.07010';

__PACKAGE__->mk_group_ro_accessors('simple', qw/
                                schema
                                schema_class

                                exclude
                                constraint
                                additional_classes
                                additional_base_classes
                                left_base_classes
                                components
                                skip_relationships
                                skip_load_external
                                moniker_map
                                col_accessor_map
                                custom_column_info
                                inflect_singular
                                inflect_plural
                                debug
                                dump_directory
                                dump_overwrite
                                really_erase_my_files
                                resultset_namespace
                                default_resultset_class
                                schema_base_class
                                result_base_class
                                use_moose
                                overwrite_modifications

                                relationship_attrs

                                db_schema
                                _tables
                                classes
                                _upgrading_classes
                                monikers
                                dynamic
                                naming
                                datetime_timezone
                                datetime_locale
                                config_file
                                loader_class
                                qualify_objects
/);


__PACKAGE__->mk_group_accessors('simple', qw/
                                version_to_dump
                                schema_version_to_dump
                                _upgrading_from
                                _upgrading_from_load_classes
                                _downgrading_to_load_classes
                                _rewriting_result_namespace
                                use_namespaces
                                result_namespace
                                generate_pod
                                pod_comment_mode
                                pod_comment_spillover_length
                                preserve_case
                                col_collision_map
                                rel_collision_map
                                real_dump_directory
                                result_component_map
                                datetime_undef_if_invalid
                                _result_class_methods
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

=head2 skip_load_external

Skip loading of other classes in @INC. The default is to merge all other classes
with the same name found in @INC into the schema file we are creating.

=head2 naming

Static schemas (ones dumped to disk) will, by default, use the new-style
relationship names and singularized Results, unless you're overwriting an
existing dump made by an older version of L<DBIx::Class::Schema::Loader>, in
which case the backward compatible RelBuilder will be activated, and the
appropriate monikerization used.

Specifying

    naming => 'current'

will disable the backward-compatible RelBuilder and use
the new-style relationship names along with singularized Results, even when
overwriting a dump made with an earlier version.

The option also takes a hashref:

    naming => { relationships => 'v7', monikers => 'v7' }

The keys are:

=over 4

=item relationships

How to name relationship accessors.

=item monikers

How to name Result classes.

=item column_accessors

How to name column accessors in Result classes.

=back

The values can be:

=over 4

=item current

Latest style, whatever that happens to be.

=item v4

Unsingularlized monikers, C<has_many> only relationships with no _id stripping.

=item v5

Monikers singularized as whole words, C<might_have> relationships for FKs on
C<UNIQUE> constraints, C<_id> stripping for belongs_to relationships.

Some of the C<_id> stripping edge cases in C<0.05003> have been reverted for
the v5 RelBuilder.

=item v6

All monikers and relationships are inflected using
L<Lingua::EN::Inflect::Phrase>, and there is more aggressive C<_id> stripping
from relationship names.

In general, there is very little difference between v5 and v6 schemas.

=item v7

This mode is identical to C<v6> mode, except that monikerization of CamelCase
table names is also done correctly.

CamelCase column names in case-preserving mode will also be handled correctly
for relationship name inflection. See L</preserve_case>.

In this mode, CamelCase L</column_accessors> are normalized based on case
transition instead of just being lowercased, so C<FooId> becomes C<foo_id>.

If you don't have any CamelCase table or column names, you can upgrade without
breaking any of your code.

=back

Dynamic schemas will always default to the 0.04XXX relationship names and won't
singularize Results for backward compatibility, to activate the new RelBuilder
and singularization put this in your C<Schema.pm> file:

    __PACKAGE__->naming('current');

Or if you prefer to use 0.07XXX features but insure that nothing breaks in the
next major version upgrade:

    __PACKAGE__->naming('v7');

=head2 generate_pod

By default POD will be generated for columns and relationships, using database
metadata for the text if available and supported.

Reading database metadata (e.g. C<COMMENT ON TABLE some_table ...>) is only
supported for Postgres right now.

Set this to C<0> to turn off all POD generation.

=head2 pod_comment_mode

Controls where table comments appear in the generated POD. Smaller table
comments are appended to the C<NAME> section of the documentation, and larger
ones are inserted into C<DESCRIPTION> instead. You can force a C<DESCRIPTION>
section to be generated with the comment always, only use C<NAME>, or choose
the length threshold at which the comment is forced into the description.

=over 4

=item name

Use C<NAME> section only.

=item description

Force C<DESCRIPTION> always.

=item auto

Use C<DESCRIPTION> if length > L</pod_comment_spillover_length>, this is the
default.

=back

=head2 pod_comment_spillover_length

When pod_comment_mode is set to C<auto>, this is the length of the comment at
which it will be forced into a separate description section.

The default is C<60>

=head2 relationship_attrs

Hashref of attributes to pass to each generated relationship, listed
by type.  Also supports relationship type 'all', containing options to
pass to all generated relationships.  Attributes set for more specific
relationship types override those set in 'all'.

For example:

  relationship_attrs => {
    belongs_to => { is_deferrable => 0 },
  },

use this to turn off DEFERRABLE on your foreign key constraints.

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

The default behavior is to split on case transition and non-alphanumeric
boundaries, singularize the resulting phrase, then join the titlecased words
together. Examples:

    Table Name       | Moniker Name
    ---------------------------------
    luser            | Luser
    luser_group      | LuserGroup
    luser-opts       | LuserOpt
    stations_visited | StationVisited
    routeChange      | RouteChange

=head2 col_accessor_map

Same as moniker_map, but for column accessor names.  If a coderef is
passed, the code is called with arguments of

   the name of the column in the underlying database,
   default accessor name that DBICSL would ordinarily give this column,
   {
      table_class     => name of the DBIC class we are building,
      table_moniker   => calculated moniker for this table (after moniker_map if present),
      table_name      => name of the database table,
      full_table_name => schema-qualified name of the database table (RDBMS specific),
      schema_class    => name of the schema class we are building,
      column_info     => hashref of column info (data_type, is_nullable, etc),
    }

=head2 inflect_plural

Just like L</moniker_map> above (can be hash/code-ref, falls back to default
if hash key does not exist or coderef returns false), but acts as a map
for pluralizing relationship names.  The default behavior is to utilize
L<Lingua::EN::Inflect::Phrase/to_PL>.

=head2 inflect_singular

As L</inflect_plural> above, but for singularizing relationship names.
Default behavior is to utilize L<Lingua::EN::Inflect::Phrase/to_S>.

=head2 schema_base_class

Base class for your schema classes. Defaults to 'DBIx::Class::Schema'.

=head2 result_base_class

Base class for your table classes (aka result classes). Defaults to
'DBIx::Class::Core'.

=head2 additional_base_classes

List of additional base classes all of your table classes will use.

=head2 left_base_classes

List of additional base classes all of your table classes will use
that need to be leftmost.

=head2 additional_classes

List of additional classes which all of your table classes will use.

=head2 components

List of additional components to be loaded into all of your table
classes.  A good example would be
L<InflateColumn::DateTime|DBIx::Class::InflateColumn::DateTime>

=head2 result_component_map

A hashref of moniker keys and component values.  Unlike C<components>, which loads the
given components into every table class, this option allows you to load certain
components for specified tables.  For example:

  result_component_map => {
      StationVisited => '+YourApp::Schema::Component::StationVisited',
      RouteChange    => [
                            '+YourApp::Schema::Component::RouteChange',
                            'InflateColumn::DateTime',
                        ],
  }
  
You may use this in conjunction with C<components>.

=head2 use_namespaces

This is now the default, to go back to L<DBIx::Class::Schema/load_classes> pass
a C<0>.

Generate result class names suitable for
L<DBIx::Class::Schema/load_namespaces> and call that instead of
L<DBIx::Class::Schema/load_classes>. When using this option you can also
specify any of the options for C<load_namespaces> (i.e. C<result_namespace>,
C<resultset_namespace>, C<default_resultset_class>), and they will be added
to the call (and the generated result class names adjusted appropriately).

=head2 dump_directory

The value of this option is a perl libdir pathname.  Within
that directory this module will create a baseline manual
L<DBIx::Class::Schema> module set, based on what it creates at runtime.

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
C<# DO NOT MODIFY THE FIRST PART OF THIS FILE>
leaving any customizations you placed after that as they were.

When C<really_erase_my_files> is not set, if the output file already exists,
but the aforementioned final stanza is not found, or the checksum
contained there does not match the generated contents, Loader will
croak and not touch the file.

You should really be using version control on your schema classes (and all
of the rest of your code for that matter).  Don't blame me if a bug in this
code wipes something out when it shouldn't have, you've been warned.

=head2 overwrite_modifications

Default false.  If false, when updating existing files, Loader will
refuse to modify any Loader-generated code that has been modified
since its last run (as determined by the checksum Loader put in its
comment lines).

If true, Loader will discard any manual modifications that have been
made to Loader-generated code.

Again, you should be using version control on your schema classes.  Be
careful with this option.

=head2 custom_column_info

Hook for adding extra attributes to the
L<column_info|DBIx::Class::ResultSource/column_info> for a column.

Must be a coderef that returns a hashref with the extra attributes.

Receives the table name, column name and column_info.

For example:

  custom_column_info => sub {
      my ($table_name, $column_name, $column_info) = @_;

      if ($column_name eq 'dog' && $column_info->{default_value} eq 'snoopy') {
          return { is_snoopy => 1 };
      }
  },

This attribute can also be used to set C<inflate_datetime> on a non-datetime
column so it also receives the L</datetime_timezone> and/or L</datetime_locale>.

=head2 datetime_timezone

Sets the timezone attribute for L<DBIx::Class::InflateColumn::DateTime> for all
columns with the DATE/DATETIME/TIMESTAMP data_types.

=head2 datetime_locale

Sets the locale attribute for L<DBIx::Class::InflateColumn::DateTime> for all
columns with the DATE/DATETIME/TIMESTAMP data_types.

=head2 datetime_undef_if_invalid

Pass a C<0> for this option when using MySQL if you B<DON'T> want C<<
datetime_undef_if_invalid => 1 >> in your column info for DATE, DATETIME and
TIMESTAMP columns.

The default is recommended to deal with data such as C<00/00/00> which
sometimes ends up in such columns in MySQL.

=head2 config_file

File in Perl format, which should return a HASH reference, from which to read
loader options.

=head2 preserve_case

Usually column names are lowercased, to make them easier to work with in
L<DBIx::Class>. This option lets you turn this behavior off, if the driver
supports it.

Drivers for case sensitive databases like Sybase ASE or MSSQL with a
case-sensitive collation will turn this option on unconditionally.

Currently the drivers for SQLite, mysql, MSSQL and Firebird/InterBase support
setting this option.

=head2 qualify_objects

Set to true to prepend the L</db_schema> to table names for C<<
__PACKAGE__->table >> calls, and to some other things like Oracle sequences.

=head2 use_moose

Creates Schema and Result classes that use L<Moose>, L<MooseX::NonMoose> and
L<namespace::autoclean>. The default content after the md5 sum also makes the
classes immutable.

It is safe to upgrade your existing Schema to this option.

=head2 col_collision_map

This option controls how accessors for column names which collide with perl
methods are named. See L</COLUMN ACCESSOR COLLISIONS> for more information.

This option takes either a single L<sprintf|perlfunc/sprintf> format or a hashref of
strings which are compiled to regular expressions that map to
L<sprintf|perlfunc/sprintf> formats.

Examples:

    col_collision_map => 'column_%s'

    col_collision_map => { '(.*)' => 'column_%s' }

    col_collision_map => { '(foo).*(bar)' => 'column_%s_%s' }

=head2 rel_collision_map

Works just like L</col_collision_map>, but for relationship names/accessors
rather than column names/accessors.

The default is to just append C<_rel> to the relationship name, see
L</RELATIONSHIP NAME COLLISIONS>.

=head1 METHODS

None of these methods are intended for direct invocation by regular
users of L<DBIx::Class::Schema::Loader>. Some are proxied via
L<DBIx::Class::Schema::Loader>.

=cut

my $CURRENT_V = 'v7';

my @CLASS_ARGS = qw(
    schema_base_class result_base_class additional_base_classes
    left_base_classes additional_classes components
);

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

    if (exists $args{column_accessor_map}) {
        $args{col_accessor_map} = delete $args{column_accessor_map};
    }

    my $self = { %args };

    # don't lose undef options
    for (values %$self) {
        $_ = 0 unless defined $_;
    }

    bless $self => $class;

    if (my $config_file = $self->config_file) {
        my $config_opts = do $config_file;

        croak "Error reading config from $config_file: $@" if $@;

        croak "Config file $config_file must be a hashref" unless ref($config_opts) eq 'HASH';

        while (my ($k, $v) = each %$config_opts) {
            $self->{$k} = $v unless exists $self->{$k};
        }
    }

    $self->_ensure_arrayref(qw/additional_classes
                               additional_base_classes
                               left_base_classes
                               components
                              /);

    $self->_validate_class_args;

    if ($self->result_component_map) {
        my %rc_map = %{ $self->result_component_map };
        foreach my $moniker (keys %rc_map) {
            $rc_map{$moniker} = [ $rc_map{$moniker} ] unless ref $rc_map{$moniker};
        }
        $self->result_component_map(\%rc_map);
    }
    else {
        $self->result_component_map({});
    }
    $self->_validate_result_component_map;

    if ($self->use_moose) {
        if (not DBIx::Class::Schema::Loader::Optional::Dependencies->req_ok_for('use_moose')) {
            die sprintf "You must install the following CPAN modules to enable the use_moose option: %s.\n",
                DBIx::Class::Schema::Loader::Optional::Dependencies->req_missing_for('use_moose');
        }
    }

    $self->{monikers} = {};
    $self->{classes} = {};
    $self->{_upgrading_classes} = {};

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

    $self->real_dump_directory($self->{dump_directory});

    $self->version_to_dump($DBIx::Class::Schema::Loader::VERSION);
    $self->schema_version_to_dump($DBIx::Class::Schema::Loader::VERSION);

    if ((not ref $self->naming) && defined $self->naming) {
        my $naming_ver = $self->naming;
        $self->{naming} = {
            relationships => $naming_ver,
            monikers => $naming_ver,
            column_accessors => $naming_ver,
        };
    }

    if ($self->naming) {
        for (values %{ $self->naming }) {
            $_ = $CURRENT_V if $_ eq 'current';
        }
    }
    $self->{naming} ||= {};

    if ($self->custom_column_info && ref $self->custom_column_info ne 'CODE') {
        croak 'custom_column_info must be a CODE ref';
    }

    $self->_check_back_compat;

    $self->use_namespaces(1) unless defined $self->use_namespaces;
    $self->generate_pod(1)   unless defined $self->generate_pod;
    $self->pod_comment_mode('auto')         unless defined $self->pod_comment_mode;
    $self->pod_comment_spillover_length(60) unless defined $self->pod_comment_spillover_length;

    if (my $col_collision_map = $self->col_collision_map) {
        if (my $reftype = ref $col_collision_map) {
            if ($reftype ne 'HASH') {
                croak "Invalid type $reftype for option 'col_collision_map'";
            }
        }
        else {
            $self->col_collision_map({ '(.*)' => $col_collision_map });
        }
    }

    $self;
}

sub _check_back_compat {
    my ($self) = @_;

# dynamic schemas will always be in 0.04006 mode, unless overridden
    if ($self->dynamic) {
# just in case, though no one is likely to dump a dynamic schema
        $self->schema_version_to_dump('0.04006');

        if (not %{ $self->naming }) {
            warn <<EOF unless $ENV{SCHEMA_LOADER_BACKCOMPAT};

Dynamic schema detected, will run in 0.04006 mode.

Set the 'naming' attribute or the SCHEMA_LOADER_BACKCOMPAT environment variable
to disable this warning.

Also consider setting 'use_namespaces => 1' if/when upgrading.

See perldoc DBIx::Class::Schema::Loader::Manual::UpgradingFromV4 for more
details.
EOF
        }
        else {
            $self->_upgrading_from('v4');
        }

        $self->naming->{relationships} ||= 'v4';
        $self->naming->{monikers}      ||= 'v4';

        if ($self->use_namespaces) {
            $self->_upgrading_from_load_classes(1);
        }
        else {
            $self->use_namespaces(0);
        }

        return;
    }

# otherwise check if we need backcompat mode for a static schema
    my $filename = $self->_get_dump_filename($self->schema_class);
    return unless -e $filename;

    my ($old_gen, $old_md5, $old_ver, $old_ts, $old_custom) =
      $self->_parse_generated_file($filename);

    return unless $old_ver;

    # determine if the existing schema was dumped with use_moose => 1
    if (! defined $self->use_moose) {
        $self->{use_moose} = 1 if $old_gen =~ /^ (?!\s*\#) use \s+ Moose/xm;
    }

    my $load_classes = ($old_gen =~ /^__PACKAGE__->load_classes;/m) ? 1 : 0;
    my $result_namespace = do { ($old_gen =~ /result_namespace => '([^']+)'/) ? $1 : '' };

    if ($load_classes && (not defined $self->use_namespaces)) {
        warn <<"EOF"  unless $ENV{SCHEMA_LOADER_BACKCOMPAT};

'load_classes;' static schema detected, turning off 'use_namespaces'.

Set the 'use_namespaces' attribute or the SCHEMA_LOADER_BACKCOMPAT environment
variable to disable this warning.

See perldoc DBIx::Class::Schema::Loader::Manual::UpgradingFromV4 for more
details.
EOF
        $self->use_namespaces(0);
    }
    elsif ($load_classes && $self->use_namespaces) {
        $self->_upgrading_from_load_classes(1);
    }
    elsif ((not $load_classes) && defined $self->use_namespaces && ! $self->use_namespaces) {
        $self->_downgrading_to_load_classes(
            $result_namespace || 'Result'
        );
    }
    elsif ((not defined $self->use_namespaces) || $self->use_namespaces) {
        if (not $self->result_namespace) {
            $self->result_namespace($result_namespace || 'Result');
        }
        elsif ($result_namespace ne $self->result_namespace) {
            $self->_rewriting_result_namespace(
                $result_namespace || 'Result'
            );
        }
    }

    # XXX when we go past .0 this will need fixing
    my ($v) = $old_ver =~ /([1-9])/;
    $v = "v$v";

    return if ($v eq $CURRENT_V || $old_ver =~ /^0\.\d\d999/);

    if (not %{ $self->naming }) {
        warn <<"EOF" unless $ENV{SCHEMA_LOADER_BACKCOMPAT};

Version $old_ver static schema detected, turning on backcompat mode.

Set the 'naming' attribute or the SCHEMA_LOADER_BACKCOMPAT environment variable
to disable this warning.

See: 'naming' in perldoc DBIx::Class::Schema::Loader::Base .

See perldoc DBIx::Class::Schema::Loader::Manual::UpgradingFromV4 if upgrading
from version 0.04006.
EOF

        $self->naming->{relationships}    ||= $v;
        $self->naming->{monikers}         ||= $v;
        $self->naming->{column_accessors} ||= $v;

        $self->schema_version_to_dump($old_ver);
    }
    else {
        $self->_upgrading_from($v);
    }
}

sub _validate_class_args {
    my $self = shift;

    foreach my $k (@CLASS_ARGS) {
        next unless $self->$k;

        my @classes = ref $self->$k eq 'ARRAY' ? @{ $self->$k } : $self->$k;
        $self->_validate_classes($k, \@classes);
    }
}

sub _validate_result_component_map {
    my $self = shift;

    my $map = $self->result_component_map;
    return unless $map && ref $map eq 'HASH';

    foreach my $classes (values %$map) {
        $self->_validate_classes('result_component_map', [@$classes]);
    }
}

sub _validate_classes {
    my $self = shift;
    my $key  = shift;
    my $classes = shift;

    foreach my $c (@$classes) {
        # components default to being under the DBIx::Class namespace unless they
        # are preceeded with a '+'
        if ( $key =~ m/component/ && $c !~ s/^\+// ) {
            $c = 'DBIx::Class::' . $c;
        }

        # 1 == installed, 0 == not installed, undef == invalid classname
        my $installed = Class::Inspector->installed($c);
        if ( defined($installed) ) {
            if ( $installed == 0 ) {
                croak qq/$c, as specified in the loader option "$key", is not installed/;
            }
        } else {
            croak qq/$c, as specified in the loader option "$key", is an invalid class name/;
        }
    }
}


sub _find_file_in_inc {
    my ($self, $file) = @_;

    foreach my $prefix (@INC) {
        my $fullpath = File::Spec->catfile($prefix, $file);
        return $fullpath if -f $fullpath
            # abs_path throws on Windows for nonexistant files
            and (try { Cwd::abs_path($fullpath) }) ne
               ((try { Cwd::abs_path(File::Spec->catfile($self->dump_directory, $file)) }) || '');
    }

    return;
}

sub _class_path {
    my ($self, $class) = @_;

    my $class_path = $class;
    $class_path =~ s{::}{/}g;
    $class_path .= '.pm';

    return $class_path;
}

sub _find_class_in_inc {
    my ($self, $class) = @_;

    return $self->_find_file_in_inc($self->_class_path($class));
}

sub _rewriting {
    my $self = shift;

    return $self->_upgrading_from
        || $self->_upgrading_from_load_classes
        || $self->_downgrading_to_load_classes
        || $self->_rewriting_result_namespace
    ;
}

sub _rewrite_old_classnames {
    my ($self, $code) = @_;

    return $code unless $self->_rewriting;

    my %old_classes = reverse %{ $self->_upgrading_classes };

    my $re = join '|', keys %old_classes;
    $re = qr/\b($re)\b/;

    $code =~ s/$re/$old_classes{$1} || $1/eg;

    return $code;
}

sub _load_external {
    my ($self, $class) = @_;

    return if $self->{skip_load_external};

    # so that we don't load our own classes, under any circumstances
    local *INC = [ grep $_ ne $self->dump_directory, @INC ];

    my $real_inc_path = $self->_find_class_in_inc($class);

    my $old_class = $self->_upgrading_classes->{$class}
        if $self->_rewriting;

    my $old_real_inc_path = $self->_find_class_in_inc($old_class)
        if $old_class && $old_class ne $class;

    return unless $real_inc_path || $old_real_inc_path;

    if ($real_inc_path) {
        # If we make it to here, we loaded an external definition
        warn qq/# Loaded external class definition for '$class'\n/
            if $self->debug;

        my $code = $self->_rewrite_old_classnames(scalar slurp $real_inc_path);

        if ($self->dynamic) { # load the class too
            eval_without_redefine_warnings($code);
        }

        $self->_ext_stmt($class,
          qq|# These lines were loaded from '$real_inc_path' found in \@INC.\n|
         .qq|# They are now part of the custom portion of this file\n|
         .qq|# for you to hand-edit.  If you do not either delete\n|
         .qq|# this section or remove that file from \@INC, this section\n|
         .qq|# will be repeated redundantly when you re-create this\n|
         .qq|# file again via Loader!  See skip_load_external to disable\n|
         .qq|# this feature.\n|
        );
        chomp $code;
        $self->_ext_stmt($class, $code);
        $self->_ext_stmt($class,
            qq|# End of lines loaded from '$real_inc_path' |
        );
    }

    if ($old_real_inc_path) {
        my $code = slurp $old_real_inc_path;

        $self->_ext_stmt($class, <<"EOF");

# These lines were loaded from '$old_real_inc_path',
# based on the Result class name that would have been created by an older
# version of the Loader. For a static schema, this happens only once during
# upgrade. See skip_load_external to disable this feature.
EOF

        $code = $self->_rewrite_old_classnames($code);

        if ($self->dynamic) {
            warn <<"EOF";

Detected external content in '$old_real_inc_path', a class name that would have
been used by an older version of the Loader.

* PLEASE RENAME THIS CLASS: from '$old_class' to '$class', as that is the
new name of the Result.
EOF
            eval_without_redefine_warnings($code);
        }

        chomp $code;
        $self->_ext_stmt($class, $code);
        $self->_ext_stmt($class,
            qq|# End of lines loaded from '$old_real_inc_path' |
        );
    }
}

=head2 load

Does the actual schema-construction work.

=cut

sub load {
    my $self = shift;

    $self->_load_tables(
        $self->_tables_list({ constraint => $self->constraint, exclude => $self->exclude })
    );
}

=head2 rescan

Arguments: schema

Rescan the database for changes. Returns a list of the newly added table
monikers.

The schema argument should be the schema class or object to be affected.  It
should probably be derived from the original schema_class used during L</load>.

=cut

sub rescan {
    my ($self, $schema) = @_;

    $self->{schema} = $schema;
    $self->_relbuilder->{schema} = $schema;

    my @created;
    my @current = $self->_tables_list({ constraint => $self->constraint, exclude => $self->exclude });

    foreach my $table (@current) {
        if(!exists $self->{_tables}->{$table}) {
            push(@created, $table);
        }
    }

    my %current;
    @current{@current} = ();
    foreach my $table (keys %{ $self->{_tables} }) {
        if (not exists $current{$table}) {
            $self->_unregister_source_for_table($table);
        }
    }

    delete $self->{_dump_storage};
    delete $self->{_relations_started};

    my $loaded = $self->_load_tables(@current);

    return map { $self->monikers->{$_} } @created;
}

sub _relbuilder {
    my ($self) = @_;

    return if $self->{skip_relationships};

    return $self->{relbuilder} ||= do {

        no warnings 'uninitialized';
        my $relbuilder_suff =
            {qw{
                v4  ::Compat::v0_040
                v5  ::Compat::v0_05
                v6  ::Compat::v0_06
            }}
            ->{ $self->naming->{relationships}};

        my $relbuilder_class = 'DBIx::Class::Schema::Loader::RelBuilder'.$relbuilder_suff;
        load_class $relbuilder_class;
        $relbuilder_class->new( $self );

    };
}

sub _load_tables {
    my ($self, @tables) = @_;

    # Save the new tables to the tables list
    foreach (@tables) {
        $self->{_tables}->{$_} = 1;
    }

    $self->_make_src_class($_) for @tables;

    # sanity-check for moniker clashes
    my $inverse_moniker_idx;
    for (keys %{$self->monikers}) {
      push @{$inverse_moniker_idx->{$self->monikers->{$_}}}, $_;
    }

    my @clashes;
    for (keys %$inverse_moniker_idx) {
      my $tables = $inverse_moniker_idx->{$_};
      if (@$tables > 1) {
        push @clashes, sprintf ("tables %s reduced to the same source moniker '%s'",
          join (', ', map { "'$_'" } @$tables),
          $_,
        );
      }
    }

    if (@clashes) {
      die   'Unable to load schema - chosen moniker/class naming style results in moniker clashes. '
          . 'Either change the naming style, or supply an explicit moniker_map: '
          . join ('; ', @clashes)
          . "\n"
      ;
    }


    $self->_setup_src_meta($_) for @tables;

    if(!$self->skip_relationships) {
        # The relationship loader needs a working schema
        $self->{quiet} = 1;
        local $self->{dump_directory} = $self->{temp_directory};
        $self->_reload_classes(\@tables);
        $self->_load_relationships($_) for @tables;
        $self->_relbuilder->cleanup;
        $self->{quiet} = 0;

        # Remove that temp dir from INC so it doesn't get reloaded
        @INC = grep $_ ne $self->dump_directory, @INC;
    }

    $self->_load_external($_)
        for map { $self->classes->{$_} } @tables;

    # Reload without unloading first to preserve any symbols from external
    # packages.
    $self->_reload_classes(\@tables, { unload => 0 });

    # Drop temporary cache
    delete $self->{_cache};

    return \@tables;
}

sub _reload_classes {
    my ($self, $tables, $opts) = @_;

    my @tables = @$tables;

    my $unload = $opts->{unload};
    $unload = 1 unless defined $unload;

    # so that we don't repeat custom sections
    @INC = grep $_ ne $self->dump_directory, @INC;

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
            local *Class::C3::reinitialize = sub {};  # to speed things up, reinitialized below
            use warnings;

            if (my $mc = $self->_moose_metaclass($class)) {
                $mc->make_mutable;
            }
            Class::Unload->unload($class) if $unload;
            my ($source, $resultset_class);
            if (
                ($source = $have_source{$moniker})
                && ($resultset_class = $source->resultset_class)
                && ($resultset_class ne 'DBIx::Class::ResultSet')
            ) {
                my $has_file = Class::Inspector->loaded_filename($resultset_class);
                if (my $mc = $self->_moose_metaclass($resultset_class)) {
                    $mc->make_mutable;
                }
                Class::Unload->unload($resultset_class) if $unload;
                $self->_reload_class($resultset_class) if $has_file;
            }
            $self->_reload_class($class);
        }
        push @to_register, [$moniker, $class];
    }

    Class::C3->reinitialize;
    for (@to_register) {
        $self->schema->register_class(@$_);
    }
}

sub _moose_metaclass {
  return undef unless $INC{'Class/MOP.pm'};   # if CMOP is not loaded the class could not have loaded in the 1st place

  my $class = $_[1];

  my $mc = try { Class::MOP::class_of($class) }
    or return undef;

  return $mc->isa('Moose::Meta::Class') ? $mc : undef;
}

# We use this instead of ensure_class_loaded when there are package symbols we
# want to preserve.
sub _reload_class {
    my ($self, $class) = @_;

    my $class_path = $self->_class_path($class);
    delete $INC{ $class_path };

# kill redefined warnings
    try {
        eval_without_redefine_warnings ("require $class");
    }
    catch {
        my $source = slurp $self->_get_dump_filename($class);
        die "Failed to reload class $class: $_.\n\nCLASS SOURCE:\n\n$source";
    };
}

sub _get_dump_filename {
    my ($self, $class) = (@_);

    $class =~ s{::}{/}g;
    return $self->dump_directory . q{/} . $class . q{.pm};
}

=head2 get_dump_filename

Arguments: class

Returns the full path to the file for a class that the class has been or will
be dumped to. This is a file in a temp dir for a dynamic schema.

=cut

sub get_dump_filename {
    my ($self, $class) = (@_);

    local $self->{dump_directory} = $self->real_dump_directory;

    return $self->_get_dump_filename($class);
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
        . qq|# DO NOT MODIFY THE FIRST PART OF THIS FILE\n\n|;

    if ($self->use_moose) {
        $schema_text.= qq|use Moose;\nuse namespace::autoclean;\nextends '$schema_base_class';\n\n|;
    }
    else {
        $schema_text .= qq|use strict;\nuse warnings;\n\nuse base '$schema_base_class';\n\n|;
    }

    if ($self->use_namespaces) {
        $schema_text .= qq|__PACKAGE__->load_namespaces|;
        my $namespace_options;

        my @attr = qw/resultset_namespace default_resultset_class/;

        unshift @attr, 'result_namespace' unless (not $self->result_namespace) || $self->result_namespace eq 'Result';

        for my $attr (@attr) {
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

    {
        local $self->{version_to_dump} = $self->schema_version_to_dump;
        $self->_write_classfile($schema_class, $schema_text, 1);
    }

    my $result_base_class = $self->result_base_class || 'DBIx::Class::Core';

    foreach my $src_class (@classes) {
        my $src_text = 
              qq|package $src_class;\n\n|
            . qq|# Created by DBIx::Class::Schema::Loader\n|
            . qq|# DO NOT MODIFY THE FIRST PART OF THIS FILE\n\n|
            . qq|use strict;\nuse warnings;\n\n|;
        if ($self->use_moose) {
            $src_text.= qq|use Moose;\nuse MooseX::NonMoose;\nuse namespace::autoclean;|;

            # these options 'use base' which is compile time
            if (@{ $self->left_base_classes } || @{ $self->additional_base_classes }) {
                $src_text .= qq|\nBEGIN { extends '$result_base_class' }\n\n|;
            }
            else {
                $src_text .= qq|\nextends '$result_base_class';\n\n|;
            }
        }
        else {
             $src_text .= qq|use base '$result_base_class';\n\n|;
        }
        $self->_write_classfile($src_class, $src_text);
    }

    # remove Result dir if downgrading from use_namespaces, and there are no
    # files left.
    if (my $result_ns = $self->_downgrading_to_load_classes
                        || $self->_rewriting_result_namespace) {
        my $result_namespace = $self->_result_namespace(
            $schema_class,
            $result_ns,
        );

        (my $result_dir = $result_namespace) =~ s{::}{/}g;
        $result_dir = $self->dump_directory . '/' . $result_dir;

        unless (my @files = glob "$result_dir/*") {
            rmdir $result_dir;
        }
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
    my ($self, $class, $text, $is_schema) = @_;

    my $filename = $self->_get_dump_filename($class);
    $self->_ensure_dump_subdirs($class);

    if (-f $filename && $self->really_erase_my_files) {
        warn "Deleting existing file '$filename' due to "
            . "'really_erase_my_files' setting\n" unless $self->{quiet};
        unlink($filename);
    }

    my ($old_gen, $old_md5, $old_ver, $old_ts, $old_custom)
        = $self->_parse_generated_file($filename);

    if (! $old_gen && -f $filename) {
        croak "Cannot overwrite '$filename' without 'really_erase_my_files',"
            . " it does not appear to have been generated by Loader"
    }

    my $custom_content = $old_custom || '';

    # prepend extra custom content from a *renamed* class (singularization effect)
    if (my $renamed_class = $self->_upgrading_classes->{$class}) {
        my $old_filename = $self->_get_dump_filename($renamed_class);

        if (-f $old_filename) {
            my $extra_custom = ($self->_parse_generated_file ($old_filename))[4];

            $extra_custom =~ s/\n\n# You can replace.*\n1;\n//;

            $custom_content = join ("\n", '', $extra_custom, $custom_content)
                if $extra_custom;

            unlink $old_filename;
        }
    }

    $custom_content ||= $self->_default_custom_content($is_schema);

    # If upgrading to use_moose=1 replace default custom content with default Moose custom content.
    # If there is already custom content, which does not have the Moose content, add it.
    if ($self->use_moose) {

        my $non_moose_custom_content = do {
            local $self->{use_moose} = 0;
            $self->_default_custom_content;
        };

        if ($custom_content eq $non_moose_custom_content) {
            $custom_content = $self->_default_custom_content($is_schema);
        }
        elsif ($custom_content !~ /\Q@{[$self->_default_moose_custom_content($is_schema)]}\E/) {
            $custom_content .= $self->_default_custom_content($is_schema);
        }
    }
    elsif (defined $self->use_moose && $old_gen) {
        croak 'It is not possible to "downgrade" a schema that was loaded with use_moose => 1 to use_moose => 0, due to differing custom content'
            if $old_gen =~ /use \s+ MooseX?\b/x;
    }

    $custom_content = $self->_rewrite_old_classnames($custom_content);

    $text .= qq|$_\n|
        for @{$self->{_dump_storage}->{$class} || []};

    # Check and see if the dump is infact differnt

    my $compare_to;
    if ($old_md5) {
      $compare_to = $text . $self->_sig_comment($old_ver, $old_ts);
      if (Digest::MD5::md5_base64($compare_to) eq $old_md5) {
        return unless $self->_upgrading_from && $is_schema;
      }
    }

    $text .= $self->_sig_comment(
      $self->version_to_dump,
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

sub _default_moose_custom_content {
    my ($self, $is_schema) = @_;

    if (not $is_schema) {
        return qq|\n__PACKAGE__->meta->make_immutable;|;
    }
    
    return qq|\n__PACKAGE__->meta->make_immutable(inline_constructor => 0);|;
}

sub _default_custom_content {
    my ($self, $is_schema) = @_;
    my $default = qq|\n\n# You can replace this text with custom|
         . qq| code or comments, and it will be preserved on regeneration|;
    if ($self->use_moose) {
        $default .= $self->_default_moose_custom_content($is_schema);
    }
    $default .= qq|\n1;\n|;
    return $default;
}

sub _parse_generated_file {
    my ($self, $fn) = @_;

    return unless -f $fn;

    open(my $fh, '<', $fn)
        or croak "Cannot open '$fn' for reading: $!";

    my $mark_re =
        qr{^(# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:)([A-Za-z0-9/+]{22})\n};

    my ($md5, $ts, $ver, $gen);
    while(<$fh>) {
        if(/$mark_re/) {
            my $pre_md5 = $1;
            $md5 = $2;

            # Pull out the version and timestamp from the line above
            ($ver, $ts) = $gen =~ m/^# Created by DBIx::Class::Schema::Loader v(.*?) @ (.*?)\Z/m;

            $gen .= $pre_md5;
            croak "Checksum mismatch in '$fn', the auto-generated part of the file has been modified outside of this loader.  Aborting.\nIf you want to overwrite these modifications, set the 'overwrite_modifications' loader option.\n"
                if !$self->overwrite_modifications && Digest::MD5::md5_base64($gen) ne $md5;

            last;
        }
        else {
            $gen .= $_;
        }
    }

    my $custom = do { local $/; <$fh> }
        if $md5;

    close ($fh);

    return ($gen, $md5, $ver, $ts, $custom);
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

    my $blist = join(q{ }, @_);

    return unless $blist;

    warn "$target: use base qw/$blist/;" if $self->debug;
    $self->_raw_stmt($target, "use base qw/$blist/;");
}

sub _result_namespace {
    my ($self, $schema_class, $ns) = @_;
    my @result_namespace;

    if ($ns =~ /^\+(.*)/) {
        # Fully qualified namespace
        @result_namespace = ($1)
    }
    else {
        # Relative namespace
        @result_namespace = ($schema_class, $ns);
    }

    return wantarray ? @result_namespace : join '::', @result_namespace;
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
        @result_namespace = $self->_result_namespace(
            $schema_class,
            $result_namespace,
        );
    }
    my $table_class = join(q{::}, @result_namespace, $table_moniker);

    if ((my $upgrading_v = $self->_upgrading_from)
            || $self->_rewriting) {
        local $self->naming->{monikers} = $upgrading_v
            if $upgrading_v;

        my @result_namespace = @result_namespace;
        if ($self->_upgrading_from_load_classes) {
            @result_namespace = ($schema_class);
        }
        elsif (my $ns = $self->_downgrading_to_load_classes) {
            @result_namespace = $self->_result_namespace(
                $schema_class,
                $ns,
            );
        }
        elsif ($ns = $self->_rewriting_result_namespace) {
            @result_namespace = $self->_result_namespace(
                $schema_class,
                $ns,
            );
        }

        my $old_class = join(q{::}, @result_namespace,
            $self->_table2moniker($table));

        $self->_upgrading_classes->{$table_class} = $old_class
            unless $table_class eq $old_class;
    }

# this was a bad idea, should be ok now without it
#    my $table_normalized = lc $table;
#    $self->classes->{$table_normalized} = $table_class;
#    $self->monikers->{$table_normalized} = $table_moniker;

    $self->classes->{$table} = $table_class;
    $self->monikers->{$table} = $table_moniker;

    $self->_use   ($table_class, @{$self->additional_classes});
    $self->_inject($table_class, @{$self->left_base_classes});

    my @components = @{ $self->components || [] };

    push @components, @{ $self->result_component_map->{$table_moniker} }
        if exists $self->result_component_map->{$table_moniker};

    $self->_dbic_stmt($table_class, 'load_components', @components) if @components;

    $self->_inject($table_class, @{$self->additional_base_classes});
}

sub _is_result_class_method {
    my ($self, $name, $table_name) = @_;

    my $table_moniker = $table_name ? $self->_table2moniker($table_name) : '';

    if (not $self->_result_class_methods) {
        my (@methods, %methods);
        my $base       = $self->result_base_class || 'DBIx::Class::Core';

        my @components = @{ $self->components || [] };

        push @components, @{ $self->result_component_map->{$table_moniker} }
            if exists $self->result_component_map->{$table_moniker};

        for my $c (@components) {
            $c = $c =~ /^\+/ ? substr($c,1) : "DBIx::Class::$c";
        }

        for my $class ($base, @components, $self->use_moose ? 'Moose::Object' : ()) {
            load_class $class;

            push @methods, @{ Class::Inspector->methods($class) || [] };
        }

        push @methods, @{ Class::Inspector->methods('UNIVERSAL') };

        @methods{@methods} = ();

        # futureproof meta
        $methods{meta} = undef;

        $self->_result_class_methods(\%methods);
    }
    my $result_methods = $self->_result_class_methods;

    return exists $result_methods->{$name};
}

sub _resolve_col_accessor_collisions {
    my ($self, $table, $col_info) = @_;

    my $table_name = ref $table ? $$table : $table;

    while (my ($col, $info) = each %$col_info) {
        my $accessor = $info->{accessor} || $col;

        next if $accessor eq 'id'; # special case (very common column)

        if ($self->_is_result_class_method($accessor, $table_name)) {
            my $mapped = 0;

            if (my $map = $self->col_collision_map) {
                for my $re (keys %$map) {
                    if (my @matches = $col =~ /$re/) {
                        $info->{accessor} = sprintf $map->{$re}, @matches;
                        $mapped = 1;
                    }
                }
            }

            if (not $mapped) {
                warn <<"EOF";
Column '$col' in table '$table_name' collides with an inherited method.
See "COLUMN ACCESSOR COLLISIONS" in perldoc DBIx::Class::Schema::Loader::Base .
EOF
                $info->{accessor} = undef;
            }
        }
    }
}

# use the same logic to run moniker_map, col_accessor_map, and
# relationship_name_map
sub _run_user_map {
    my ( $self, $map, $default_code, $ident, @extra ) = @_;

    my $default_ident = $default_code->( $ident, @extra );
    my $new_ident;
    if( $map && ref $map eq 'HASH' ) {
        $new_ident = $map->{ $ident };
    }
    elsif( $map && ref $map eq 'CODE' ) {
        $new_ident = $map->( $ident, $default_ident, @extra );
    }

    $new_ident ||= $default_ident;

    return $new_ident;
}

sub _default_column_accessor_name {
    my ( $self, $column_name ) = @_;

    my $accessor_name = $column_name;
    $accessor_name =~ s/\W+/_/g;

    if ((($self->naming->{column_accessors}||'') =~ /(\d+)/ && $1 < 7) || (not $self->preserve_case)) {
        # older naming just lc'd the col accessor and that's all.
        return lc $accessor_name;
    }

    return join '_', map lc, split_name $column_name;

}

sub _make_column_accessor_name {
    my ($self, $column_name, $column_context_info ) = @_;

    my $accessor = $self->_run_user_map(
        $self->col_accessor_map,
        sub { $self->_default_column_accessor_name( shift ) },
        $column_name,
        $column_context_info,
       );

    return $accessor;
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

    my $full_table_name = ($self->qualify_objects ? ($self->db_schema . '.') : '') . (ref $table_name ? $$table_name : $table_name);

    # be careful to not create refs Data::Dump can "optimize"
    $full_table_name    = \do {"".$full_table_name} if ref $table_name;

    $self->_dbic_stmt($table_class, 'table', $full_table_name);

    my $cols     = $self->_table_columns($table);
    my $col_info = $self->__columns_info_for($table);

    ### generate all the column accessor names
    while (my ($col, $info) = each %$col_info) {
        # hashref of other info that could be used by
        # user-defined accessor map functions
        my $context = {
            table_class     => $table_class,
            table_moniker   => $table_moniker,
            table_name      => $table_name,
            full_table_name => $full_table_name,
            schema_class    => $schema_class,
            column_info     => $info,
        };

        $info->{accessor} = $self->_make_column_accessor_name( $col, $context );
    }

    $self->_resolve_col_accessor_collisions($full_table_name, $col_info);

    # prune any redundant accessor names
    while (my ($col, $info) = each %$col_info) {
        no warnings 'uninitialized';
        delete $info->{accessor} if $info->{accessor} eq $col;
    }

    my $fks = $self->_table_fk_info($table);

    foreach my $fkdef (@$fks) {
        for my $col (@{ $fkdef->{local_columns} }) {
            $col_info->{$col}{is_foreign_key} = 1;
        }
    }

    my $pks = $self->_table_pk_info($table) || [];

    foreach my $pkcol (@$pks) {
        $col_info->{$pkcol}{is_nullable} = 0;
    }

    $self->_dbic_stmt(
        $table_class,
        'add_columns',
        map { $_, ($col_info->{$_}||{}) } @$cols
    );

    my %uniq_tag; # used to eliminate duplicate uniqs

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

sub __columns_info_for {
    my ($self, $table) = @_;

    my $result = $self->_columns_info_for($table);

    while (my ($col, $info) = each %$result) {
        $info = { %$info, %{ $self->_custom_column_info  ($table, $col, $info) } };
        $info = { %$info, %{ $self->_datetime_column_info($table, $col, $info) } };

        $result->{$col} = $info;
    }

    return $result;
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
    no warnings 'uninitialized';
    my ($self, $table) = @_;

    if ($self->naming->{monikers} eq 'v4') {
        return join '', map ucfirst, split /[\W_]+/, lc $table;
    }
    elsif ($self->naming->{monikers} eq 'v5') {
        return join '', map ucfirst, split /[\W_]+/,
            Lingua::EN::Inflect::Number::to_S(lc $table);
    }
    elsif ($self->naming->{monikers} eq 'v6') {
        (my $as_phrase = lc $table) =~ s/_+/ /g;
        my $inflected = Lingua::EN::Inflect::Phrase::to_S($as_phrase);

        return join '', map ucfirst, split /\W+/, $inflected;
    }

    my @words = map lc, split_name $table;
    my $as_phrase = join ' ', @words;

    my $inflected = Lingua::EN::Inflect::Phrase::to_S($as_phrase);

    return join '', map ucfirst, split /\W+/, $inflected;
}

sub _table2moniker {
    my ( $self, $table ) = @_;

    $self->_run_user_map(
        $self->moniker_map,
        sub { $self->_default_table2moniker( shift ) },
        $table
       );
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
    my $rel_stmts = $self->_relbuilder->generate_code($local_moniker, $tbl_fk_info, $tbl_uniq_info);

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
    my $self   = shift;
    my $class  = shift;
    my $method = shift;

    # generate the pod for this statement, storing it with $self->_pod
    $self->_make_pod( $class, $method, @_ ) if $self->generate_pod;

    my $args = dump(@_);
    $args = '(' . $args . ')' if @_ < 2;
    my $stmt = $method . $args . q{;};

    warn qq|$class\->$stmt\n| if $self->debug;
    $self->_raw_stmt($class, '__PACKAGE__->' . $stmt);
    return;
}

# generates the accompanying pod for a DBIC class method statement,
# storing it with $self->_pod
sub _make_pod {
    my $self   = shift;
    my $class  = shift;
    my $method = shift;

    if ( $method eq 'table' ) {
        my ($table) = @_;
        my $pcm = $self->pod_comment_mode;
        my ($comment, $comment_overflows, $comment_in_name, $comment_in_desc);
        $comment = $self->__table_comment($table);
        $comment_overflows = ($comment and length $comment > $self->pod_comment_spillover_length);
        $comment_in_name   = ($pcm eq 'name' or ($pcm eq 'auto' and !$comment_overflows));
        $comment_in_desc   = ($pcm eq 'description' or ($pcm eq 'auto' and $comment_overflows));
        $self->_pod( $class, "=head1 NAME" );
        my $table_descr = $class;
        $table_descr .= " - " . $comment if $comment and $comment_in_name;
        $self->{_class2table}{ $class } = $table;
        $self->_pod( $class, $table_descr );
        if ($comment and $comment_in_desc) {
            $self->_pod( $class, "=head1 DESCRIPTION" );
            $self->_pod( $class, $comment );
        }
        $self->_pod_cut( $class );
    } elsif ( $method eq 'add_columns' ) {
        $self->_pod( $class, "=head1 ACCESSORS" );
        my $col_counter = 0;
        my @cols = @_;
        while( my ($name,$attrs) = splice @cols,0,2 ) {
            $col_counter++;
            $self->_pod( $class, '=head2 ' . $name  );
            $self->_pod( $class,
                join "\n", map {
                    my $s = $attrs->{$_};
                    $s = !defined $s          ? 'undef'             :
                        length($s) == 0       ? '(empty string)'    :
                        ref($s) eq 'SCALAR'   ? $$s                 :
                        ref($s)               ? dumper_squashed $s  :
                        looks_like_number($s) ? $s                  : qq{'$s'};

                    "  $_: $s"
                 } sort keys %$attrs,
            );
            if (my $comment = $self->__column_comment($self->{_class2table}{$class}, $col_counter, $name)) {
                $self->_pod( $class, $comment );
            }
        }
        $self->_pod_cut( $class );
    } elsif ( $method =~ /^(belongs_to|has_many|might_have)$/ ) {
        $self->_pod( $class, "=head1 RELATIONS" ) unless $self->{_relations_started} { $class } ;
        my ( $accessor, $rel_class ) = @_;
        $self->_pod( $class, "=head2 $accessor" );
        $self->_pod( $class, 'Type: ' . $method );
        $self->_pod( $class, "Related object: L<$rel_class>" );
        $self->_pod_cut( $class );
        $self->{_relations_started} { $class } = 1;
    }
}

sub _filter_comment {
    my ($self, $txt) = @_;

    $txt = '' if not defined $txt;

    $txt =~ s/(?:\015?\012|\015\012?)/\n/g;

    return $txt;
}

sub __table_comment {
    my $self = shift;

    if (my $code = $self->can('_table_comment')) {
        return $self->_filter_comment($self->$code(@_));
    }
    
    return '';
}

sub __column_comment {
    my $self = shift;

    if (my $code = $self->can('_column_comment')) {
        return $self->_filter_comment($self->$code(@_));
    }

    return '';
}

# Stores a POD documentation
sub _pod {
    my ($self, $class, $stmt) = @_;
    $self->_raw_stmt( $class, "\n" . $stmt  );
}

sub _pod_cut {
    my ($self, $class ) = @_;
    $self->_raw_stmt( $class, "\n=cut\n" );
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

sub _custom_column_info {
    my ( $self, $table_name, $column_name, $column_info ) = @_;

    if (my $code = $self->custom_column_info) {
        return $code->($table_name, $column_name, $column_info) || {};
    }
    return {};
}

sub _datetime_column_info {
    my ( $self, $table_name, $column_name, $column_info ) = @_;
    my $result = {};
    my $type = $column_info->{data_type} || '';
    if ((grep $_, @{ $column_info }{map "inflate_$_", qw/date datetime timestamp/})
            or ($type =~ /date|timestamp/i)) {
        $result->{timezone} = $self->datetime_timezone if $self->datetime_timezone;
        $result->{locale}   = $self->datetime_locale   if $self->datetime_locale;
    }
    return $result;
}

sub _lc {
    my ($self, $name) = @_;

    return $self->preserve_case ? $name : lc($name);
}

sub _uc {
    my ($self, $name) = @_;

    return $self->preserve_case ? $name : uc($name);
}

sub _unregister_source_for_table {
    my ($self, $table) = @_;

    try {
        local $@;
        my $schema = $self->schema;
        # in older DBIC it's a private method
        my $unregister = $schema->can('unregister_source') || $schema->can('_unregister_source');
        $schema->$unregister($self->_table2moniker($table));
        delete $self->monikers->{$table};
        delete $self->classes->{$table};
        delete $self->_upgrading_classes->{$table};
        delete $self->{_tables}{$table};
    };
}

# remove the dump dir from @INC on destruction
sub DESTROY {
    my $self = shift;

    @INC = grep $_ ne $self->dump_directory, @INC;
}

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

=head1 COLUMN ACCESSOR COLLISIONS

Occasionally you may have a column name that collides with a perl method, such
as C<can>. In such cases, the default action is to set the C<accessor> of the
column spec to C<undef>.

You can then name the accessor yourself by placing code such as the following
below the md5:

    __PACKAGE__->add_column('+can' => { accessor => 'my_can' });

Another option is to use the L</col_collision_map> option.

=head1 RELATIONSHIP NAME COLLISIONS

In very rare cases, you may get a collision between a generated relationship
name and a method in your Result class, for example if you have a foreign key
called C<belongs_to>.

This is a problem because relationship names are also relationship accessor
methods in L<DBIx::Class>.

The default behavior is to append C<_rel> to the relationship name and print
out a warning that refers to this text.

You can also control the renaming with the L</rel_collision_map> option.

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=head1 AUTHOR

See L<DBIx::Class::Schema::Loader/AUTHOR> and L<DBIx::Class::Schema::Loader/CONTRIBUTORS>.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
# vim:et sts=4 sw=4 tw=0:
