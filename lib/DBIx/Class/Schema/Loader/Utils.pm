package # hide from PAUSE
    DBIx::Class::Schema::Loader::Utils;

use strict;
use warnings;
use Data::Dumper ();
use Test::More;
use namespace::clean;
use Exporter 'import';

our @EXPORT_OK = qw/split_name dumper dumper_squashed eval_without_redefine_warnings warnings_exist warnings_exist_silent/;

use constant BY_CASE_TRANSITION =>
    qr/(?<=[[:lower:]\d])[\W_]*(?=[[:upper:]])|[\W_]+/;

use constant BY_NON_ALPHANUM =>
    qr/[\W_]+/;

sub split_name($) {
    my $name = shift;

    split $name =~ /[[:upper:]]/ && $name =~ /[[:lower:]]/ ? BY_CASE_TRANSITION : BY_NON_ALPHANUM, $name;
}

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

sub eval_without_redefine_warnings {
    my $code = shift;

    my $warn_handler = $SIG{__WARN__} || sub { warn @_ };
    local $SIG{__WARN__} = sub {
        $warn_handler->(@_)
            unless $_[0] =~ /^Subroutine \S+ redefined/;
    };
    eval $code;
    die $@ if $@;
}

sub warnings_exist(&$$) {
    my ($code, $re, $test_name) = @_;

    my $matched = 0;

    my $warn_handler = $SIG{__WARN__} || sub { warn @_ };
    local $SIG{__WARN__} = sub {
        if ($_[0] =~ $re) {
            $matched = 1;
        }
        else {
            $warn_handler->(@_)
        }
    };

    $code->();

    ok $matched, $test_name;
}

sub warnings_exist_silent(&$$) {
    my ($code, $re, $test_name) = @_;

    my $matched = 0;

    local $SIG{__WARN__} = sub { $matched = 1 if $_[0] =~ $re; };

    $code->();

    ok $matched, $test_name;
}


1;
# vim:et sts=4 sw=4 tw=0:
