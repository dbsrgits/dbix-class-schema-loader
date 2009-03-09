use Test::More;

eval { require Test::Kwalitee; die "Not maintainer" unless -f 'MANIFEST.SKIP' };
if($@) {
    $@ =~ s/ \(\@INC contains.*//; # reduce the noise
    plan( skip_all => $@ );
}
Test::Kwalitee->import(); 
