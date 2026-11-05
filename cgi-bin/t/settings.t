use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::Exception;
use Test::More tests => 17;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Settings;
use CATS::User;

*get = *CATS::Settings::get_item;
*update = *CATS::Settings::update_item;
*remove = *CATS::Settings::remove_item;

{

    my $s = { key1 => 'abc' };
    is get($s, { name => 'key1' }), 'abc', 'get';
    is get($s, { name => 'key2' }), undef, 'get none';

    update($s, { name => 'key1' }, 'def');
    is get($s, { name => 'key1' }), 'def', 'get 2';
    update($s, { name => 'key1', default => 'def' }, 'def');
    is get($s, { name => 'key1' }), undef, 'get default';

    update($s, { name => 'a.b.c.d' }, 'x');
    is_deeply get($s, { name => 'a.b' }), { c => { d => 'x' } }, 'nested';

    remove($s, { name => 'a.b.c.d' });
    is_deeply $s, {}, 'remove nested';

    update($s, { name => 'a.b.c.d' }, 'x');
    update($s, { name => 'a.b.c.e' }, 'y');
    remove($s, { name => 'a.b.c.d' });
    is_deeply $s, { a => { b => { c => { e => 'y' } } } }, 'remove nested 2';
    remove($s, { name => 'a.q' });
    is_deeply $s, { a => { b => { c => { e => 'y' } } } }, 'remove nonexistent';
}

{
    package CATS::Test::SettingsDBH;

    sub selectrow_array {
        my ($self) = @_;
        map { $_ eq 'settings' ? $self->{settings} : '' } CATS::User::param_names(), 'settings';
    }
    sub do { $_[0]->{new_settings} = $_[3]; 1 }
    sub commit { 1 }
}

{
    my $expected = { display => { input => 1 }, source_width => 120 };
    my $json = JSON::XS::encode_json($expected);
    my $legacy = Storable::nfreeze($expected);

    is_deeply CATS::Settings::decode_settings(undef), {}, 'decode empty';
    is_deeply CATS::Settings::decode_settings($json), $expected, 'decode JSON';
    is_deeply CATS::Settings::decode_settings($legacy), $expected, 'decode legacy Storable';
    ok !defined CATS::Settings::decode_settings('invalid'), 'reject invalid settings';

    local $CATS::Settings::uid = 123;
    CATS::Settings::init($json);
    is_deeply $CATS::Settings::settings, $expected, 'init JSON';
    CATS::Settings::init($legacy);
    is_deeply $CATS::Settings::settings, $expected, 'init legacy Storable';

    my $test_dbh = bless { settings => $json }, 'CATS::Test::SettingsDBH';
    $CATS::DB::dbh = $test_dbh;
    CATS::Settings::save;
    is_deeply JSON::XS::decode_json($test_dbh->{new_settings}), $expected, 'migrate legacy settings to JSON';

    my $u = CATS::User->new->load(123, [ 'settings' ]);
    is_deeply $u->{settings}, $expected, 'load user JSON settings';
    is $u->{frozen_settings}, $json, 'preserve raw settings for edit comparison';
}

1;
