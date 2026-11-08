use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 2;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::UI::RankTable;

my @args;
my $p = { json => 1 };

{
    no warnings 'redefine';
    local *CATS::UI::RankTable::rank_table = sub { @args = @_; 'rendered' };
    is CATS::UI::RankTable::rank_table_frame($p), 'rendered',
        'JSON request uses the content renderer';
}

is_deeply \@args, [ $p, 'rank_table' ], 'content renderer receives the request and outer template';
