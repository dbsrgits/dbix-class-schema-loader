package # hide from PAUSE
    DBIx::Class::Schema::Loader::Constants;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw/BY_CASE_TRANSITION/;

use constant BY_CASE_TRANSITION =>
    qr/(?<=[[:lower:]\d])[\W_]*(?=[[:upper:]])|[\W_]+/;

1;
