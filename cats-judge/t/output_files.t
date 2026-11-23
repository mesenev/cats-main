use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::Exception;
use Test::More tests => 14;

use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');
use lib File::Spec->catdir($FindBin::Bin, '..', 'lib', 'cats-problem');

use CATS::BinaryFile;
use CATS::FileUtil;
use CATS::Loggers;

my $dir = tempdir(CLEANUP => 1);
my $canary = File::Spec->catfile($dir, 'canary.txt');
my $link = File::Spec->catfile($dir, 'link.txt');
my $regular = File::Spec->catfile($dir, 'regular.txt');
my $output = File::Spec->catfile($dir, 'output.txt');
my $fu = CATS::FileUtil->new({ logger => CATS::Logger::Count->new });
$fu->write_to_file($canary, "do not disclose\n") or die;
$fu->write_to_file($regular, "ordinary output\n") or die;
symlink 'canary.txt', $link or die $!;

my $data;
throws_ok { CATS::BinaryFile::load($link, \$data) } qr/not found/, 'BinaryFile::load rejects symlink';
is $data, undef, 'BinaryFile::load does not disclose canary';
throws_ok { CATS::BinaryFile::save($link, 'overwrite') } qr/Can not write/, 'BinaryFile::save rejects symlink';
is_deeply $fu->read_lines($canary), [ "do not disclose\n" ], 'BinaryFile::save preserves canary';
ok CATS::BinaryFile::save($output, 'binary data'), 'BinaryFile::save accepts regular file';
my $loaded;
ok CATS::BinaryFile::load($output, \$loaded) && $loaded eq 'binary data',
    'BinaryFile::load reads regular file';

my $copy_cat = File::Spec->catfile($FindBin::Bin, '..', 'copy_cat.pl');
my $r = $fu->run([ $^X, $copy_cat, '-i', $link, '-m', '*STDOUT' ]);
ok !$r->ok, 'copy_cat rejects symlink input';
unlike join('', @{$r->stdout}), qr/do not disclose/, 'copy_cat does not print canary';
$r = $fu->run([ $^X, $copy_cat, '-i', $link, '-o', $output, '-l', '1' ]);
ok !$r->ok, 'copy_cat line mode rejects symlink input';
unlike join('', @{$r->stdout}), qr/do not disclose/, 'copy_cat line mode does not print canary';
$r = $fu->run([ $^X, $copy_cat, '-i', $regular, '-o', $link, '-l', '1' ]);
ok !$r->ok, 'copy_cat rejects symlink output';
is_deeply $fu->read_lines($canary), [ "do not disclose\n" ], 'copy_cat preserves canary';
$r = $fu->run([ $^X, $copy_cat, '-i', $regular, '-m', '*STDOUT' ]);
ok $r->ok, 'copy_cat accepts regular input';
is_deeply $r->stdout, [ "ordinary output\n" ], 'copy_cat preserves ordinary output';
