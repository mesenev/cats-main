package CATS::BinaryFile;

use strict;
use warnings;

use Carp;
use CATS::FileUtil;

sub load {
    my ($fname, $result, %p) = @_;
    ref $result eq 'SCALAR' or die;

    my $fh = CATS::FileUtil->new({})->open_regular($fname) or die "$fname not found";
    binmode($fh, ':raw');

    $$result = '';
    while (sysread($fh, my $buffer, 8192)) {
        $$result .= $buffer;
    }
    close $fh;
    1;
}

sub save {
    my ($fname, $data) = @_;
    $data or croak 'No data';
    my $fh = CATS::FileUtil->new({})->open_regular($fname, 1) or die "Can not write to $fname";
    binmode($fh);
    syswrite($fh, $data, length($data));
    close $fh;
}

1;
