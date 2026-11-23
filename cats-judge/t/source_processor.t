use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 6;

use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');
use lib File::Spec->catdir($FindBin::Bin, '..', 'lib', 'cats-problem');

use CATS::Loggers;
use CATS::Spawner;
use CATS::Spawner::Const ':all';
use CATS::Judge::SourceProcessor;

{
    package TestConfig;

    sub DEs { $_[0]->{DEs} }
    sub compile { $_[0]->{compile} }
    sub sp_user { 'nobody' }
    sub sp_password { undef }
}

{
    package TestSpawner;

    use CATS::Spawner::Const ':all';

    sub new { bless { calls => [] }, $_[0] }
    sub calls { $_[0]->{calls} }
    sub run_single {
        my ($self, $globals, @program) = @_;
        push @{$self->{calls}}, { globals => $globals, program => \@program };
        CATS::Spawner::ReportItem->new({
            errors => [], terminate_reason => $TR_OK, exit_code => 0,
        });
    }
}

my $cfg = bless {
    DEs => {
        503 => {
            id => 503,
            compile_precompile => 'precompile %full_name',
            compile => 'compile_one %full_name|compile_two %full_name',
        },
    },
    compile => { time_limit => 60 },
}, 'TestConfig';
my $sp = TestSpawner->new;
my $processor = CATS::Judge::SourceProcessor->new(
    cfg => $cfg, fu => 1, log => CATS::Logger::Count->new, sp => $sp,
);

is $processor->compile({
    de_id => 503, name_parts => { full_name => 'solution.hs' },
}, {}), $cats::st_testing, 'compilation succeeds';

my $calls = $sp->calls;
is scalar @$calls, 3, 'precompile and both compile stages run';
is_deeply [ map $_->{program}->[0], @$calls ], [
    'precompile solution.hs', 'compile_one solution.hs', 'compile_two solution.hs',
], 'compilation commands';
is_deeply [ map $_->{globals}->{active_connections}, @$calls ], [ 0, 0, 0 ],
    'network is disabled for every compilation stage';
is_deeply [ map $_->{globals}->{deadline}, @$calls ], [ 60, 60, 60 ],
    'compilation limits are preserved';
is_deeply [ map $_->{globals}->{user}->{name}, @$calls ], [ 'nobody', 'nobody', 'nobody' ],
    'every compilation stage uses the unprivileged user';
