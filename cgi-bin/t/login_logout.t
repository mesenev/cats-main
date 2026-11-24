use strict;
use warnings;

use Digest::SHA;
use File::Spec;
use FindBin;
use Test::More tests => 12;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

BEGIN {
    $INC{'CATS/Config.pm'} = 1;
    package CATS::Config;
    our $db = { driver => 'Pg', name => 'test', host => 'localhost' };
}

use CATS::UI::LoginLogout;
use CATS::User;

{
    package CATS::Test::LoginDBH;

    sub new {
        my ($class, %args) = @_;
        bless {
            history => {}, commits => 0, updates => 0, insert_queries => [],
            update_results => $args{update_results} || [],
        }, $class;
    }

    sub do {
        my ($self, $query, $attrs, @params) = @_;
        if ($query =~ /UPDATE accounts/) {
            ++$self->{updates};
            return shift @{$self->{update_results}} // 1;
        }
        if ($query =~ /INSERT INTO account_sid_history/) {
            push @{$self->{insert_queries}}, $query;
            my ($sid_hash, $account_id, $ip) = @params;
            $self->{history}{$sid_hash} ||= { account_id => $account_id, ip => $ip };
            return 1;
        }
        die "Unexpected query: $query";
    }

    sub selectrow_array {
        my ($self, $query, $attrs, $sid_hash) = @_;
        $self->{history}{$sid_hash}{account_id};
    }

    sub commit { ++$_[0]->{commits}; 1 }
}

sub ensure_sid {
    my ($db, $sid, $account_id) = @_;
    local $CATS::UI::LoginLogout::dbh = $db;
    local $CATS::User::dbh = $db;
    local $CATS::User::db = CATS::DB::Postgres->new;
    local $CATS::DB::db = CATS::DB::Postgres->new;
    local $CATS::UI::LoginLogout::sid = $sid;
    CATS::UI::LoginLogout::_ensure_good_sid('192.0.2.10', $account_id);
}

my $db = CATS::Test::LoginDBH->new;
ensure_sid($db, 'first-sid', 42);
ensure_sid($db, 'first-sid', 42);
my $first_hash = Digest::SHA::sha256_hex('first-sid');
is scalar keys %{$db->{history}}, 1, 'reused SID is recorded once';
is_deeply $db->{history}{$first_hash},
    { account_id => 42, ip => '192.0.2.10' }, 'SID resolves to account and IP';
is $db->{commits}, 2, 'both login transactions commit';
like $db->{insert_queries}[0], qr/WHERE NOT EXISTS/, 'recording is idempotent';

ensure_sid($db, 'second-sid', 42);
is scalar keys %{$db->{history}}, 2, 'replacement SID adds history';
is $db->{history}{$first_hash}{account_id}, 42, 'old SID keeps its account mapping';
ok !exists $db->{history}{'first-sid'}, 'plaintext SID is not stored';

my $collision = CATS::Test::LoginDBH->new(update_results => [ 0, 1 ]);
{
    no warnings 'redefine';
    local *CATS::User::make_sid = sub { 'replacement-sid' };
    ensure_sid($collision, 'taken-sid', 42);
}
is $collision->{updates}, 2, 'SID collision retries account update';
is $collision->{history}{Digest::SHA::sha256_hex('replacement-sid')}{account_id}, 42,
    'final replacement SID is recorded';
ok !exists $collision->{history}{Digest::SHA::sha256_hex('taken-sid')},
    'rejected SID is not recorded';

my $ownership = CATS::Test::LoginDBH->new;
{
    local $CATS::User::dbh = $ownership;
    local $CATS::User::db = CATS::DB::Postgres->new;
    CATS::User::record_sid('owned-sid', 1, '192.0.2.1');
    ok !eval { CATS::User::record_sid('owned-sid', 2, '192.0.2.2'); 1 },
        'SID owned by another account is rejected';
}
is $ownership->{history}{Digest::SHA::sha256_hex('owned-sid')}{account_id}, 1,
    'ownership conflict preserves the original mapping';

1;
