use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 8;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

BEGIN {
    $INC{'CATS/Config.pm'} = 1;
    package CATS::Config;
    our $db = { driver => 'Pg', name => 'test', host => 'localhost' };
}

use CATS::DB;

{
    package CATS::Test::DBH;

    sub ping { $_[0]->{alive} }
    sub disconnect {
        ++$_[0]->{disconnected};
        die "already disconnected\n" if $_[0]->{disconnect_fails};
        1;
    }
}

my $connect_count = 0;

{
    no warnings 'redefine';
    local *DBI::connect = sub {
        ++$connect_count;
        return bless { alive => 1, disconnected => 0 }, 'CATS::Test::DBH';
    };
    local $CATS::DB::dbh;
    local $CATS::DB::db;
    local $CATS::DB::sql;

    CATS::DB::sql_connect({});
    my $first = $CATS::DB::dbh;
    is $connect_count, 1, 'connect initially';
    is $first->{disconnected}, 0, 'initial handle remains open';

    CATS::DB::sql_connect({});
    is $CATS::DB::dbh, $first, 'reuse healthy handle';
    is $connect_count, 1, 'do not reconnect healthy handle';

    $first->{alive} = 0;
    $first->{disconnect_fails} = 1;
    CATS::DB::sql_connect({});
    is $first->{disconnected}, 1, 'disconnect stale handle';
    isnt $CATS::DB::dbh, $first, 'replace stale handle';
    is $connect_count, 2, 'reconnect stale handle';
    ok $CATS::DB::dbh->ping, 'replacement handle is healthy';
}
