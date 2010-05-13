package # hide from PAUSE
    DBIx::Class::Schema::Loader::Utils;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw/split_name/;

use constant BY_CASE_TRANSITION =>
    qr/(?<=[[:lower:]\d])[\W_]*(?=[[:upper:]])|[\W_]+/;

use constant BY_NON_ALPHANUM =>
    qr/[\W_]+/;

sub split_name($) {
    my $name = shift;

    split $name =~ /[[:upper:]]/ && $name =~ /[[:lower:]]/ ? BY_CASE_TRANSITION : BY_NON_ALPHANUM, $name;
}

1;
# vim:et sts=4 sw=4 tw=0:
