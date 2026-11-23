use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More tests => 18;

use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');
use lib File::Spec->catdir($FindBin::Bin, '..', 'lib', 'cats-problem');

use CATS::FileUtil;
use CATS::Spawner::Const ':all';
use CATS::Spawner::Default;
use CATS::Spawner::Program;

{
    package TestLogger;

    sub new { bless { dump => '' }, $_[0] }
    sub msg { my $self = shift; $self->{dump} .= join '', @_; $self->{dump} }
    sub dump_write { $_[0]->{dump} .= $_[1] }
}

my $dir = tempdir(CLEANUP => 1);
my $run_dir = File::Spec->catdir($dir, 'run');
mkdir $run_dir or die $!;
my $canary = File::Spec->catfile($dir, 'canary.txt');
my $fu = CATS::FileUtil->new({ logger => TestLogger->new });
$fu->write_to_file($canary, 'do not disclose') or die;
my $sp = File::Spec->catfile($FindBin::Bin, '..', 'cmd', 'sp-sandbox');

sub make_spawner {
    my $log = TestLogger->new;
    my $stdout = File::Spec->catfile($run_dir, 'stdout.txt');
    my $stderr = File::Spec->catfile($run_dir, 'stderr.txt');
    unlink $_ for map File::Spec->catfile($run_dir, $_), qw(stdout.txt stderr.txt report.txt);
    my $spawner = CATS::Spawner::Default->new({
        logger => $log,
        path => $sp,
        run_dir => $run_dir,
        stdout_file => $stdout,
        stderr_file => $stderr,
        save_stdout => $stdout,
        save_stderr => $stderr,
        save_report => File::Spec->catfile($run_dir, 'report.txt'),
        json => 1,
    });
    $spawner, $log;
}

for my $target (qw(stdout.txt stderr.txt report.txt)) {
    my ($spawner) = make_spawner;
    my $log = $spawner->opts->{logger};
    my $program = CATS::Spawner::Program->new("{$^X}", [
        '-e',
        '{print STDOUT "legitimate\n"; print STDERR "warning\n"; '
        . '$f = shift; unlink $f; symlink shift, $f or die $!;}',
        '{' . File::Spec->catfile($run_dir, $target) . '}', '{' . $canary . '}',
    ]);
    my $report = eval { $spawner->run({ save_output => 1 }, $program) };
    if ($@) {
        diag $log->{dump};
        die $@;
    }
    is $report->items->[0]->{terminate_reason}, $TR_OK, "$target attack completes";
    is_deeply $spawner->stdout_lines, [ "legitimate\n" ], "$target retains stdout";
    is_deeply $spawner->stderr_lines, [ "warning\n" ], "$target retains stderr";
    unlike $log->{dump}, qr/do not disclose/, "$target does not disclose canary";
    is_deeply $fu->read_lines($canary), [ 'do not disclose' ], "$target canary is unchanged";
}

SKIP: {
    skip 'unprivileged-user test requires root on Linux', 3 if $^O eq 'MSWin32' || $> != 0;
    chmod 0755, $dir or die $!;
    chmod 01777, $run_dir or die $!;
    my ($spawner) = make_spawner;
    my $owned = File::Spec->catfile($run_dir, 'nobody-file.txt');
    my $program = CATS::Spawner::Program->new("{$^X}", [
        '-e', '{print "65534\n"; open my $f, q(>), shift or die $!; print $f q(ok);}',
        '{' . $owned . '}',
    ]);
    my $report = $spawner->run({
        user => { name => 'nobody', password => undef },
    }, $program);
    is $report->items->[0]->{security}->{user_name}, 'nobody', 'spawner reports unprivileged user';
    is_deeply $spawner->stdout_lines_chomp, [ '65534' ], 'process really runs as nobody';
    is((stat $owned)[4], 65534, 'run directory is writable by nobody');
}
