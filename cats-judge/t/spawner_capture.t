use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More tests => 26;

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
        '{$| = 1; print STDOUT "legitimate\n"; print STDERR "warning\n"; '
        . '$f = shift; unlink $f; symlink shift, $f or die $!;}',
        '{' . File::Spec->catfile($run_dir, $target) . '}', '{' . $canary . '}',
    ]);
    my $report = eval { $spawner->run({ save_output => 1, active_connections => 0 }, $program) };
    if ($@) {
        diag $log->{dump};
        die $@;
    }
    is $report->items->[0]->{terminate_reason}, $TR_SECURITY, "$target attack is a security violation";
    is_deeply $spawner->stdout_lines, [ "legitimate\n" ], "$target retains stdout";
    is $spawner->stderr_lines->[0], "warning\n", "$target retains stderr";
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
        user => { name => 'nobody', password => undef }, active_connections => 0,
    }, $program);
    is $report->items->[0]->{security}->{user_name}, 'nobody', 'spawner reports unprivileged user';
    is_deeply $spawner->stdout_lines_chomp, [ '65534' ], 'process really runs as nobody';
    is((stat $owned)[4], 65534, 'run directory is writable by nobody');
}

SKIP: {
    skip 'seccomp test requires Linux', 6 if $^O eq 'MSWin32';
    my @operations = (
        [ symlink => 'symlink q(/dev/null), q(.tmp);' ],
        [ ptrace => 'syscall(101, 0, 0, 0, 0);' ],
        [ socket => 'use Socket qw(AF_UNIX SOCK_STREAM); socket(my $s, AF_UNIX, SOCK_STREAM, 0);' ],
    );
    for my $operation (@operations) {
        my ($name, $code) = @$operation;
        my ($spawner) = make_spawner;
        my $program = CATS::Spawner::Program->new("{$^X}", [ '-e', '{' . $code . '}' ]);
        my $report = $spawner->run({ active_connections => 0 }, $program);
        is $report->items->[0]->{terminate_reason}, $TR_SECURITY, "seccomp $name is a security violation";
    }
    my ($spawner) = make_spawner;
    my $source = File::Spec->catfile($run_dir, 'rename-source');
    my $dest = File::Spec->catfile($run_dir, 'rename-dest');
    $fu->write_to_file($source, 'ok') or die;
    my $program = CATS::Spawner::Program->new("{$^X}", [
        '-e', '{rename shift, shift or die $!; print "rename=ok\n";}',
        '{' . $source . '}', '{' . $dest . '}',
    ]);
    $spawner->run({ active_connections => 0 }, $program);
    like join('', @{$spawner->stdout_lines}), qr/rename=ok/, 'seccomp permits rename';

    ($spawner) = make_spawner;
    $program = CATS::Spawner::Program->new("{$^X}", [
        '-e', '{lstat shift or die $!; print "lstat=ok\n";}', '{' . $dest . '}',
    ]);
    $spawner->run({ active_connections => 0 }, $program);
    like join('', @{$spawner->stdout_lines}), qr/lstat=ok/, 'seccomp permits lstat';

    ($spawner) = make_spawner;
    $program = CATS::Spawner::Program->new("{$^X}", [
        '-e', '{syscall(237, 0, 0, 0, 0, 0, 0); print "mbind=ok\n";}',
    ]);
    $spawner->run({ active_connections => 0 }, $program);
    like join('', @{$spawner->stdout_lines}), qr/mbind=ok/, 'seccomp permits mbind';
}

SKIP: {
    my $pypy = '/opt/pypy3.11/bin/pypy3.11';
    skip 'PyPy with NumPy is not installed', 2 unless -x $pypy;
    my $source = File::Spec->catfile($run_dir, 'pypy-compile.pypy');
    $fu->write_to_file($source, "print('ok')\n") or die;
    my ($spawner) = make_spawner;
    my $program = CATS::Spawner::Program->new("{$pypy}", [ '-m', 'py_compile', 'pypy-compile.pypy' ]);
    my $report = $spawner->run({ active_connections => 0 }, $program);
    is $report->items->[0]->{terminate_reason}, $TR_OK, 'PyPy compilation is allowed';

    ($spawner) = make_spawner;
    $program = CATS::Spawner::Program->new("{$pypy}", [
        '-c', '{import numpy; a = numpy.arange(100); assert a.sum() == 4950}',
    ]);
    $report = eval { $spawner->run({ active_connections => 0 }, $program) };
    if ($@) {
        diag $@;
        fail 'NumPy import is allowed';
    }
    else {
        is $report->items->[0]->{terminate_reason}, $TR_OK, 'NumPy import is allowed';
    }
}
