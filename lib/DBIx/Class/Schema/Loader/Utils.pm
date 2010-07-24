package # hide from PAUSE
    DBIx::Class::Schema::Loader::Utils;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw/split_name dumper dumper_squashed/;

use constant BY_CASE_TRANSITION =>
    qr/(?<=[[:lower:]\d])[\W_]*(?=[[:upper:]])|[\W_]+/;

use constant BY_NON_ALPHANUM =>
    qr/[\W_]+/;

sub split_name($) {
    my $name = shift;

    split $name =~ /[[:upper:]]/ && $name =~ /[[:lower:]]/ ? BY_CASE_TRANSITION : BY_NON_ALPHANUM, $name;
}

# Stolen from Data::Dumper::Concise

sub dumper($) {
    my $val = shift;

    my $dd = Data::Dumper->new([]);
    $dd->Terse(1)->Indent(1)->Useqq(1)->Deparse(1)->Quotekeys(0)->Sortkeys(1);
    return $dd->Values([ $val ])->Dump;
}

sub dumper_squashed($) {
    my $val = shift;

    my $dd = Data::Dumper->new([]);
    $dd->Terse(1)->Indent(1)->Useqq(1)->Deparse(1)->Quotekeys(0)->Sortkeys(1)->Indent(0);
    return $dd->Values([ $val ])->Dump;
}

1;
# vim:et sts=4 sw=4 tw=0:
