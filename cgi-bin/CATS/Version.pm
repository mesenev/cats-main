package CATS::Version;

use strict;
use warnings;

use Cwd qw(abs_path);
use Exporter qw(import);
use File::Spec;

our @EXPORT_OK = qw(current_commit);

my ($cached_repo, $cached_commit);

sub _read_line {
    my ($file_name) = @_;
    open my $f, '<', $file_name or return '';
    my $line = <$f> // '';
    chomp $line;
    $line;
}

sub current_commit {
    my ($repo) = @_;
    $repo = abs_path($repo) or return '';
    return $cached_commit if defined $cached_repo && $repo eq $cached_repo;

    $cached_repo = $repo;
    $cached_commit = '';

    my $git_dir = "$repo/.git";
    if (-f $git_dir) {
        my ($path) = _read_line($git_dir) =~ /^gitdir:\s+(.+)$/;
        $path or return $cached_commit;
        $git_dir = File::Spec->rel2abs($path, $repo);
    }

    my $head = _read_line("$git_dir/HEAD");
    return $cached_commit = $head if $head =~ /\A[0-9a-f]{40}\z/;

    my ($ref) = $head =~ /^ref:\s+(.+)$/;
    $ref or return $cached_commit;
    my $hash = _read_line("$git_dir/$ref");

    if ($hash !~ /\A[0-9a-f]{40}\z/ && open my $packed, '<', "$git_dir/packed-refs") {
        while (<$packed>) {
            my ($candidate, $name) = split;
            next unless ($name // '') eq $ref;
            $hash = $candidate;
            last;
        }
    }
    $cached_commit = $hash if $hash =~ /\A[0-9a-f]{40}\z/;
    $cached_commit;
}

1;
