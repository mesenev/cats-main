use strict;
use warnings;

use Cwd qw(abs_path);
use File::Spec;
use FindBin;
use Test::More tests => 3;

use lib File::Spec->catdir($FindBin::Bin, '..');

use CATS::Version qw(current_commit);

my $repo = abs_path(File::Spec->catdir($FindBin::Bin, '..', '..'));
my $expected = `git -C "$repo" rev-parse HEAD`;
chomp $expected;

like current_commit($repo), qr/\A[0-9a-f]{40}\z/, 'read commit hash';
is current_commit(File::Spec->catdir($repo, 'cgi-bin', '..')), $expected, 'cache current commit';
is current_commit(File::Spec->catdir($repo, 'cgi-bin')), '', 'non-git directory has no commit';
