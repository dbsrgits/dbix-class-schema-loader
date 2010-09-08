package dbixcsl_test_dir;

use warnings;
use strict;

our $tdir = 't/var';

use base qw/Exporter/;
our @EXPORT_OK = '$tdir';

die "/t does not exist, this can't be right...\n"
  unless -d 't';

unless (-d $tdir) {
  mkdir $tdir or die "Unable to create $tdir: $!\n";
}

1;
