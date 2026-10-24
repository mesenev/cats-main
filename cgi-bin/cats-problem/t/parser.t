package main;

use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 24;
use Test::Exception;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib $FindBin::Bin;

use CATS::Problem::Parser;
use ParserMockup;

sub parse { ParserMockup::make(@_)->parse }

sub wrap_xml { qq~<?xml version="1.0" encoding="Utf-8"?><CATS version="1.0">$_[0]</CATS>~ }

sub wrap_problem {
    wrap_xml(qq~
<Problem title="Title" lang="en" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt">
$_[0]
</Problem>
~)
}

# Work around older Test::More.
BEGIN { if (!main->can('subtest')) { *subtest = sub ($&) { $_[1]->(); }; *plan = sub {}; } }

subtest 'trivial errors', sub {
    plan tests => 6;
    throws_ok { parse({ 'text.x' => 'zzz' }); } qr/xml not found/, 'no xml';
    throws_ok { parse({ 'text.xml' => 'zzz' }); } qr/error/, 'bad xml';
    throws_ok { parse({
        'text.xml' => '<?xml version="1.0" encoding="Utf-8"?><ZZZ/>',
    }); } qr/ZZZ/, 'no CATS 1';
    throws_ok { parse({
        'text.xml' => '<?xml version="1.0" encoding="Utf-8"?><Problem/>',
    }); } qr/Problem.+CATS/, 'no CATS 2';
    throws_ok { parse({
        'text.xml' => wrap_problem(qq~
        <ProblemStatement></SomeTag>
        ~)
    }); } qr/mismatched/, 'mismatched tag';
    TODO: {
        local $TODO = 'Should validate on end_CATS, not end_Problem';
        throws_ok { parse({ 'text.xml' => wrap_xml('') }) } qr/error/, 'missing Problem';
    }
};

subtest 'header', sub {
    plan tests => 12;
    my $d = parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" author="A. Uthor" tlimit="5" mlimit="6" wlimit="100B"
    saveOutputPrefix="100B" saveInputPrefix="200B" saveAnswerPrefix="300B" inputFile="input.txt" outputFile="output.txt">
<Checker src="checker.pp"/>
</Problem>~),
    'checker.pp' => 'begin end.',
    })->{description};
    is $d->{title}, 'Title', 'title';
    is $d->{author}, 'A. Uthor', 'author';
    is $d->{lang}, 'en', 'lang';
    is $d->{time_limit}, 5, 'time';
    is $d->{memory_limit}, 6, 'memory';
    is $d->{save_output_prefix}, 100, 'saveOutputPrefix';
    is $d->{save_input_prefix}, 200, 'saveInputPrefix';
    is $d->{save_answer_prefix}, 300, 'saveAnswerPrefix';
    is $d->{write_limit}, 100, 'write';
    is $d->{input_file}, 'input.txt', 'input';
    is $d->{output_file}, 'output.txt', 'output';

    my $d1 = parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" author="A. Uthor" tlimit="0" mlimit="6" wlimit="100B"
    inputFile="input.txt" outputFile="output.txt">
<Checker src="checker.pp"/>
</Problem>~),
    'checker.pp' => 'begin end.',
    })->{description};
    is $d1->{time_limit}, 0, 'time 0';
};

subtest 'missing', sub {
    plan tests => 6;
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="" lang="en" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt"/>~),
    }) } qr/title/, 'empty title';
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt"/>~),
    }) } qr/lang/, 'missing lang';
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" mlimit="6" inputFile="input.txt" outputFile="output.txt"/>~),
    }) } qr/tlimit/, 'missing time limit';
    is parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" tlimit="5" inputFile="input.txt" outputFile="output.txt">
<Checker src="checker.pp"/>
</Problem>~),
        'checker.pp' => 'begin end.',
    })->{description}->{memory_limit}, 200, 'default memory limit';
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" tlimit="5" mlimit="6" inputFile="input.txt"/>~),
    }) } qr/outputFile/, 'missing output file';
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt"/>~),
    }) } qr/checker/, 'missing checker';
};

subtest 'rename', sub {
    plan tests => 2;
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="New Title" lang="en" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt"/>~),
    }, { old_title => 'Old Title' }) } qr/rename/, 'unexpected rename';
    is parse({
        'test.xml' => wrap_xml(q~
<Problem title="Old Title" lang="en" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt">
<Run method="none"/>
</Problem>~),
    }, { old_title => 'Old Title' })->{description}->{title}, 'Old Title', 'expected rename';
};

subtest 'sources', sub {
    plan tests => 8;

    is parse({
        'test.xml' => wrap_problem(q~<Checker src="checker.pp"/>~),
        'checker.pp' => 'checker1',
    })->{checker}->{src}, 'checker1', 'checker';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Checker src="chk.pp"/>~),
    }) } qr/checker.*chk\.pp/, 'no checker';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="chk.pp"/>
<Checker src="chk.pp"/>
~),
        'chk.pp' => 'checker1',
    }) } qr/checker/, 'duplicate checker';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Solution/>~),
    }) } qr/Solution.src/, 'no solution src';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Solution src="zzz"/>~),
    }) } qr/Solution.name/, 'no solution nme';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="chk.pp"/>
<Solution name="sol1" src="sol"/>
~),
        'chk.pp' => 'checker1',
    }) } qr/sol/, 'missing solution';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="chk.pp"/>
<Solution name="sol1" src="chk.pp"/>
<Solution name="sol1" src="chk.pp"/>
~),
        'chk.pp' => 'checker1',
    }) } qr/sol1/, 'duplicate solution';

    my $sols = parse({
        'test.xml' => wrap_problem(q~
<Checker src="chk.pp"/>
<Solution name="sol1" src="chk.pp"/>
<Solution name="sol2" src="chk.pp"/>
~),
        'chk.pp' => 'checker1',
    })->{solutions};
    is_deeply [ map $_->{path}, @$sols ], [ 'chk.pp', 'chk.pp' ], 'two solutions';
};

subtest 'import', sub {
    plan tests => 3;
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Import/>~),
    }) } qr/Import.guid/, 'Import without guid';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Import guid="nonexisting"/>~),
    }) } qr/nonexisting/, 'non-existing guid';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Import guid="empty" type="yyy"/>~),
    }) } qr/type.*'yyy'/, 'incorrect type';
};

subtest 'text', sub {
    plan tests => 13;
    my $p = parse({
        'test.xml' => wrap_problem(q~
<Checker src="checker.pp"/>
<ProblemStatement>problem
statement</ProblemStatement>
<ProblemConstraints>$N = 0$</ProblemConstraints>
<InputFormat>x, y, z</InputFormat>
<OutputFormat>single number</OutputFormat>
<Explanation>easy</Explanation>~),
        'checker.pp' => 'z',
    });
    is $p->{statement}, "problem\nstatement", 'statement';
    is $p->{constraints}, '$N = 0$', 'constraints';
    is $p->{input_format}, 'x, y, z', 'input';
    is $p->{output_format}, 'single number', 'output';
    is $p->{explanation}, 'easy', 'explanation';

    my $p1 = parse({
        'test.xml' => wrap_problem(q~
<Run method="none"/>
<ProblemStatement>outside<b  class="  z  " > inside </b></ProblemStatement>
<ProblemConstraints>before<include src="incl"/>after</ProblemConstraints>~),
        'incl' => 'included'
    });
    is $p1->{statement}, 'outside<b class="  z  "> inside </b>', 'tag reconstruction';
    is $p1->{constraints}, 'beforeincludedafter', 'include';

    my $p2 = parse({
        'test.xml' => wrap_problem(q~
<Run method="none"/>
<ProblemStatement>&amp;&lt;&gt;&quot;</ProblemStatement>~),
    });
    is $p2->{statement}, '&amp;&lt;&gt;&quot;', 'xml characters';

    my $p3 = parse({
        'test.xml' => wrap_problem(q~
<Checker src="checker.pp"/>
<ProblemStatement><a href="&amp;&lt;&gt;&quot;"/></ProblemStatement>~),
        'checker.pp' => 'z',
    });
    is $p3->{statement}, '<a href="&amp;&lt;&gt;&quot;"></a>', 'xml in attribute';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<ZZZ></ZZZ>~),
    }) } qr/ZZZ/, 'unknown tag';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><include/></ProblemStatement>
<Run method="none"/>~),
    }) } qr/include/, 'no incude src';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><include src="qqq"/></ProblemStatement>
<Run method="none"/~),
    }) } qr/qqq/, 'bad incude src';

    throws_ok { parse({
        'text.xml' => wrap_problem(q~
<ProblemStatement><ProblemConstraints></ProblemConstraints></ProblemStatement>~),
    }); } qr/Unexpected.*ProblemConstraints/, 'ProblemConstraints inside ProblemStatement';
};

subtest 'picture-attachment', sub {
    plan tests => 19;
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<ProblemStatement><img/></ProblemStatement>~),
    }) } qr/picture/i, 'img without picture';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<ProblemStatement><img picture="qqq"/></ProblemStatement>~),
    }) } qr/qqq/, 'img with bad picture';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<ProblemStatement><a attachment="zzz"/></ProblemStatement>~),
    }) } qr/zzz/, 'a with bad attachment';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<ProblemStatement><object attachment="zzz"/></ProblemStatement>~),
    }) } qr/zzz/, 'object with bad attachment';

    for my $tag (qw(Picture Attachment)) {
        throws_ok { parse({
            'test.xml' => wrap_problem(qq~<$tag/>~),
        }) } qr/src/, "$tag without src";

        throws_ok { parse({
            'test.xml' => wrap_problem(qq~<$tag src="test"/>~),
        }) } qr/name/, "$tag without name";

        throws_ok { parse({
            'test.xml' => wrap_problem(qq~<$tag src="xxxx" name="yyyy"/>~),
        }) } qr/xxxx/, "$tag with bad src";
    }

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Picture src="p1" name="p1" />~),
        'p1' => 'p1data',
    }) } qr/extension/, 'bad picture extension';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Attachment src="a1.txt" name="a1" />
<ProblemStatement><img picture="a1"/></ProblemStatement>
~),
        'a1.txt' => 'a1data',
    }) } qr/a1/, 'img references attachment';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Picture src="p1.txt" name="p1" />
<ProblemStatement><a attachment="p1"/></ProblemStatement>
~),
        'p1.txt' => 'p1data',
    }) } qr/p1/, 'a references picture';

    my $p = parse({
        'test.xml' => wrap_problem(q~
<Picture src="p1.img" name="p1" />
<Attachment src="a1.txt" name="a1" />
<ProblemStatement>
text <img picture="p1"/> <a attachment="a1"/>
</ProblemStatement>
<Run method="none"/>
~),
        'p1.img' => 'p1data',
        'a1.txt' => 'a1data',
    });

    is scalar @{$p->{pictures}}, 1, 'pictures count';
    is $p->{pictures}->[0]->{name}, 'p1', 'picture 1 name';
    is $p->{pictures}->[0]->{src}, 'p1data', 'picture 1 data';
    is scalar @{$p->{attachments}}, 1, 'attachments count';
    is $p->{attachments}->[0]->{name}, 'a1', 'attachment 1 name';
    is $p->{attachments}->[0]->{src}, 'a1data', 'attachment 1 data';
};

subtest 'tag stack', sub {
    plan tests => 11;
    throws_ok { parse({
        'test.xml' => wrap_xml(q~<ProblemStatement/>~),
    }) } qr/ProblemStatement.+Problem/, 'ProblemStatement outside Problem';
    throws_ok { parse({
        'test.xml' => wrap_xml(q~<Checker/>~),
    }) } qr/Checker.+Problem/, 'Checker outside Problem';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Problem/>~),
    }) } qr/Problem.+CATS/, 'Problem inside Problem';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<In/>~),
    }) } qr/In.+Test/, 'In outside Test';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Out/>~),
    }) } qr/Out.+Test/, 'Out outside Test';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<SampleIn/>~),
    }) } qr/SampleIn.+Sample/, 'SampleIn outside Sample';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<SampleOut/>~),
    }) } qr/SampleOut.+Sample/, 'SampleOut outside SampleTest';
    throws_ok { parse({
        'test.xml' => wrap_problem(qq~
<ProblemStatement><p><ProblemConstraints></ProblemConstraints></p></ProblemStatement>~),
    }) } qr/Unexpected/, 'Top-level tag inside stml';
    throws_ok { parse({
        'text.xml' => wrap_problem(qq~
        <Quiz type="text"></Quiz>
        ~)
    }); } qr/Quiz/, 'mismatched tag';
    throws_ok { parse({
        'test.xml' => wrap_problem('<Attachment src="a1.txt" name="a1" /><a attachment="a1"/>'),
        'a1.txt' => 'a1data',
    }) } qr/Unexpected/, 'tag a';
    throws_ok { parse({
        'text.xml' => wrap_problem(qq~
        <table></table>
        ~)
    }); } qr/Unknown/, 'table';
};

subtest 'apply_test_rank', sub {
    plan tests => 5;
    is CATS::Problem::Parser::apply_test_rank('abc', 9), 'abc', 'No rank';
    is CATS::Problem::Parser::apply_test_rank('a%nc', 9), 'a9c', '1 digit';
    is CATS::Problem::Parser::apply_test_rank('a%0nc', 9), 'a09c', '2 digits';
    is CATS::Problem::Parser::apply_test_rank('a%00nc', 9), 'a009c', '3 digits';
    is CATS::Problem::Parser::apply_test_rank('a%%%nc', 9), 'a%9c', 'Escape';
};

subtest 'sample', sub {
    plan tests => 40;

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample/>~),
    }) } qr/Sample.rank/, 'Sample without rank';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="2"><SampleIn>q</SampleIn><SampleOut>w</SampleOut></Sample>~),
    }) } qr/Missing.*1/, 'missing sample';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"/>~),
    }) } qr/Neither.*SampleIn.*1/, 'missing SampleIn';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn>w</SampleIn></Sample>~),
    }) } qr/Neither.*SampleOut.*1/, 'missing SampleOut';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn src="t01.in"/></Sample>~),
    }) } qr/'t01.in'/, 'Sample with nonexisting input file';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn src="t01.in"/><SampleOut src="t01.out"/></Sample>~),
        't01.in' => 'z',
    }) } qr/'t01.out'/, 'Sample with nonexisting output file';
    throws_ok { parse({
            'test.xml' => wrap_problem(q~
<Sample rank="1"><SampleIn src="s"><tt>zz</tt></SampleIn><SampleOut>ww</SampleOut></Sample>~),
        's' => 'a',
    }) } qr/Redefined source.*SampleIn.*1/, 'Sample with duplicate input';
    throws_ok { parse({
            'test.xml' => wrap_problem(q~
<Sample rank="1"><SampleIn><tt>zz</tt></SampleIn><SampleOut src="s">ww</SampleOut></Sample>~),
        's' => 'a',
    }) } qr/Redefined source.*SampleOut.*1/, 'Sample with duplicate output';
    throws_ok { parse({
            'test.xml' => wrap_problem(q~
<Sample rank="1"><SampleIn html="1">zz</SampleIn><SampleOut>w</SampleOut></Sample>
<Sample rank="1"><SampleIn html="0"/></Sample>~),
    }) } qr/Redefined.*html.*SampleIn.*1/, 'Sample with duplicate html attr';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn src="t01.in"/><SampleIn src="t01.in"/></Sample>~),
        't01.in' => 'z',
    }) } qr/Redefined source.*SampleIn.*1/, 'Sample with duplicate input file';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleOut src="t01.in"/><SampleOut src="t01.in"/></Sample>~),
        't01.in' => 'z',
    }) } qr/Redefined source.*SampleOut.*1/, 'Sample with duplicate output file';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn>ii</SampleIn><SampleIn>jj</SampleIn></Sample>~),
    }) } qr/Redefined source for SampleIn.*1/, 'Sample with duplicate input text';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn>ii</SampleIn><SampleIn/></Sample>~),
    }) } qr/Neither.*SampleOut/, 'SampleIn with empty content';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn>i</SampleIn><SampleOut>a</SampleOut><SampleOut>b</SampleOut></Sample>~),
    }) } qr/Redefined source for SampleOut.*1/, 'Sample with duplicate output text';
    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Sample rank="1"><SampleIn src="s"/><SampleOut src="s"/></Sample>
<Sample rank="2"><SampleIn>aaa</SampleIn><SampleOut>bbb</SampleOut></Sample>
<Sample rank="3"><SampleIn html="1">&amp;<b>&lt;</b></SampleIn><SampleOut>&amp;<b>&lt;</b></SampleOut></Sample>
<Run method="none"/>~),
            's' => 'sss',
        });
        is scalar(keys %{$p->{samples}}), 3, 'Sample count';
        is_deeply [ map $p->{samples}->{$_}->{rank}, 1..3 ], [ 1..3 ], 'Sample ranks';
        my $s1 = $p->{samples}->{1};
        is $s1->{in_file}, 'sss', 'Sample 1 In src';
        is $s1->{out_file}, 'sss', 'Sample 1 Out src';
        my $s2 = $p->{samples}->{2};
        is $s2->{in_file}, 'aaa', 'Sample 2 In';
        is $s2->{out_file}, 'bbb', 'Sample 2 Out';
        my $s3 = $p->{samples}->{3};
        is $s3->{in_file}, '&amp;<b>&lt;</b>', 'Sample 3 In';
        is $s3->{in_html}, 1, 'Sample 3 In Html';
        is $s3->{out_file}, '&<b><</b>', 'Sample 3 Out';
    }
    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Sample rank="1-2"><SampleIn src="s%n"/></Sample>
<Sample rank="2-3"><SampleOut src="out"/></Sample>
<Sample rank="3"><SampleIn>s33</SampleIn></Sample>
<Sample rank="1"><SampleOut>out</SampleOut></Sample>

<Run method="none"/>~),
            's1' => 's11',
            's2' => 's22',
            's3' => 's33',
            'out' => 'out',
        });
        is scalar(keys %{$p->{samples}}), 3, 'Sample range count';
        for (1..3) {
            my $s = $p->{samples}->{$_};
            is $s->{rank}, $_, "Sample range $_ rank";
            is $s->{in_file}, "s$_$_", "Sample range $_ In src";
            is $s->{out_file}, 'out', "Sample range $_ Out src";
        }
    }
    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Sample rank="1-2"><SampleIn><b>cc</b></SampleIn><SampleOut src="s%0n"/></Sample>
<Checker src="checker.pp"/>~),
            'checker.pp' => 'zz',
            's01' => 's11',
            's02' => 's22',
        });
        is scalar(keys %{$p->{samples}}), 2, 'Sample range count';
        for (1..2) {
            my $s = $p->{samples}->{$_};
            is $s->{rank}, $_, "Sample range $_ rank";
            is $s->{in_file}, '<b>cc</b>', "Sample range $_ In";
            is $s->{out_file}, "s$_$_", "Sample range $_ Out src";
        }
    }
};

subtest 'test', sub {
    plan tests => 68;

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test/>~),
    }) } qr/Test.rank/, 'Test without rank';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="999999"/>~),
    }) } qr/Bad rank/, 'Test with bad rank';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="2"/>~),
    }) } qr/Missing test #1/, 'Missing test 1';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"/>~),
    }) } qr/No input source for test 1/, 'Test without In';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In/></Test>~),
    }) } qr/No input source for test 1/, 'Test with empty In';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/></Test>~),
    }) } qr/'t01.in'/, 'Test with nonexinsting input file';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><In src="t01.in"/></Test>~),
        't01.in' => 'z',
    }) } qr/Redefined attribute 'in_file'/, 'Test with duplicate In';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><In>zzz</In></Test>~),
        't01.in' => 'z',
    }) } qr/Redefined attribute 'in_file'/, 'Test with duplicate In text';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/></Test>~),
        't01.in' => 'z',
    }) } qr/No output source for test 1/, 'Test without Out';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><Out/></Test>~),
        't01.in' => 'z',
    }) } qr/No output source for test 1/, 'Test with empty Out';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><Out src="t02.out"/></Test>~),
        't01.in' => 'z',
    }) } qr/'t02.out'/, 'Test with nonexinsting output file 1';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1-2"><In src="t01.in"/><Out src="t%0n.out"/></Test>~),
        't01.in' => 'z',
    }) } qr/'t01.out', 't02.out'/, 'Test with nonexinsting output file 2';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><Out src="t01.out"/><Out src="t01.out"/></Test>~),
        't01.in' => 'z',
        't01.out' => 'q',
    }) } qr/Redefined attribute 'out_file'/, 'Test with duplicate Out';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In>zz</In><Out src="t01.out"/><Out>out</Out></Test>~),
        't01.out' => 'q',
    }) } qr/Redefined attribute 'out_file'/, 'Test with duplicate Out text';
    throws_ok { parse({
        'test.xml' => wrap_problem(
            q~<Generator name="g" src="g.pp"/><Test rank="1"><In use="g">z</In><Out>out</Out></Test>~),
        'g.pp' => 'q',
    }) } qr/Both input file and generator/, 'Test with input file and generator';
    throws_ok { parse({
        'test.xml' => wrap_problem(
            q~<Solution name="s" src="s.pp"/><Test rank="1"><In>z</In><Out use="s">out</Out></Test>~),
        's.pp' => 'q',
    }) } qr/output file.*standard solution/, 'Test with output file and solution';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="2"></Test><Test rank="1"></Test>~),
    }) } qr/No input source for test 1/, 'Test errors in rank order';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1" points="A"><In src="t01.in"/><Out src="t01.out"/></Test>~),
        't01.in' => 'z',
        't01.out' => 'q',
    }) } qr/Bad points/, 'Bad points';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In hash="zzz">1</In><Out>2</Out></Test>~),
    }) } qr/Invalid hash.*zzz.*1/, 'Bad hash';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In hash="$yyy$zz">1</In><Out>2</Out></Test>~),
    }) } qr/Unknown hash algorithm.*yyy.*1/, 'Bad hash algorithm';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In hash="$sha$zz">1</In><In hash="$sha$qq"/><Out>2</Out></Test>~),
    }) } qr/Redefined attribute 'hash'/, 'Redefined hash';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1" descr="a"/><Test rank="1" descr="b"/>~),
    }) } qr/Redefined attribute 'descr'/, 'Redefined descr';

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Test rank="1" descr="check it"><In src="t01.in"/><Out src="t01.out"/></Test>
<Checker src="checker.pp"/>~),
            't01.in' => 'z',
            't01.out' => 'q',
            'checker.pp' => 'z',
        });
        is scalar(keys %{$p->{tests}}), 1, 'Test 1';
        my $t = $p->{tests}->{1};
        is $t->{rank}, 1, 'Test 1 rank';
        is $t->{descr}, 'check it', 'Test 1 descr';
        is $t->{in_file}, 'z', 'Test 1 In src';
        is $t->{in_file_name}, 't01.in', 'Test 1 In src name';
        is $t->{out_file}, 'q', 'Test 1 Out src';
        is $t->{out_file_name}, 't01.out', 'Test 1 Out src name';
    }

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Test rank="1"><In/><In>in1</In><Out/></Test>
<Test rank="1"><Out>out1</Out></Test>
<Test rank="2"><In>in2</In><Out>out2</Out></Test>
<Test rank="3"><In>&amp;<tag/></In><Out>&lt;&gt;</Out></Test>
<Checker src="checker.pp"/>~),
            'checker.pp' => 'z',
        });
        is scalar(keys %{$p->{tests}}), 3, 'Test text';
        for (1..2) {
            my $t = $p->{tests}->{$_};
            is $t->{rank}, $_, 'Test text rank';
            is $t->{in_file}, "in$_", 'Test text In';
            is $t->{out_file}, "out$_", 'Test text Out';
        }
        my $t = $p->{tests}->{3};
        # TODO
        is $t->{in_file}, '&<tag></tag>', 'Test text In literal';
        is $t->{out_file}, '<>', 'Test text Out literal';
    }

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Test rank="1-2" points="5"><In src="t%n.in"/><Out src="t%n.out"/></Test>
<Checker src="checker.pp"/>~),
            't1.in' => 't1in', 't1.out' => 't1out',
            't2.in' => 't2in', 't2.out' => 't2out',
            'checker.pp' => 'z',
        });
        is scalar(keys %{$p->{tests}}), 2, 'Apply %n';
        for (1..2) {
            my $t = $p->{tests}->{$_};
            is $t->{rank}, $_, "Apply $_ rank";
            is $t->{points}, 5, "Apply $_ points";
            is $t->{in_file}, "t${_}in", "Apply $_ In src";
            is $t->{out_file}, "t${_}out", "Apply $_ Out src";
        }
    }

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Generator name="gen" src="gen.pp"/>
<Solution name="sol" src="sol.pp"/>
<Test rank="1-5"><In use="gen" param="!%n"/><Out use="sol"/></Test>
<Checker src="chk.pp"/>~),
            'gen.pp' => 'z',
            'sol.pp' => 'z',
            'chk.pp' => 'z',
        });
        is scalar(keys %{$p->{tests}}), 5, 'Gen %n';
        for (1, 2, 5) {
            my $t = $p->{tests}->{$_};
            is $t->{rank}, $_, "Gen $_ rank";
            is $t->{param}, "!$_", "Gen $_ param";
            is $t->{generator_id}, 'gen.pp', "Gen $_ In";
            is $t->{std_solution_id}, 'sol.pp', "Gen $_ Out";
        }
    }

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Solution name="sol" src="sol.pp"/>
<Solution name="sol1" src="sol1.pp"/>
<Test rank="*"><In>def</In><Out use="sol"/></Test>
<Test rank="1"><In src="01.in"/></Test>
<Test rank="2"><Out use="sol1"/></Test>
<Checker src="chk.pp"/>~),
            'sol.pp' => 'z',
            'sol1.pp' => 'z',
            '01.in' => 'zz',
            'chk.pp' => 'z',
        });
        is scalar(keys %{$p->{tests}}), 2, 'Default test_count';
        {
            my $t = $p->{tests}->{1};
            is $t->{in_file}, 'zz', 'Default 1 in';
            is $t->{std_solution_id}, 'sol.pp', 'Default 1 out';
        }
        {
            my $t = $p->{tests}->{2};
            is $t->{in_file}, 'def', 'Default 2 in';
            is $t->{std_solution_id}, 'sol1.pp', 'Default 2 out';
        }
    }

    {
        my $parser = ParserMockup::make({
            'test.xml' => wrap_problem(q~
<Test rank="1" points="1"><In src="in"/><Out src="out"/></Test>
<Test rank="2"><In src="in"/><Out src="out"/></Test>
<Checker src="checker.pp" style="testlib"/>~),
            'in' => 'in', 'out' => 'out',
            'checker.pp' => 'z',
        });
        my $p = $parser->parse;
        my $w = $parser->logger->{warnings};
        is scalar @$w, 1, 'point/no-point warnings count';
        is $w->[0], 'Points are defined for tests: 1 but not 2', 'point/no-point warning';
        is scalar(keys %{$p->{tests}}), 2, 'point/no-point tests count';
    }

};

subtest 'testest', sub {
    plan tests => 20;

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Testset/>~),
    }) } qr/Testset.name/, 'Testset without name';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Testset name="ts"/>~),
    }) } qr/Testset.tests/, 'Testset without tests';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Testset name="ts" tests="X"/>~),
    }) } qr/Unknown testset 'X'/, 'Testset with bad tests 1';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Testset name="ts" tests="1-"/>~),
    }) } qr/Bad element/, 'Testset with bad tests 2';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Testset name="ts" tests="1"/>
<Testset name="ts" tests="2"/>~),
    }) } qr/Duplicate testset 'ts'/, 'Duplicate testset';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Testset name="ts" tests="1" points="X"/>~),
    }) } qr/Bad points for testset 'ts'/, 'Bad points';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Testset name="ts" tests="1"/>~),
    }) } qr/Undefined test 1 in testset 'ts'/, 'Undefined test';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Test rank="1-10"><In src="t"/><Out src="t"/></Test>
<Testset name="ts1" tests="1" depends_on="ts2"/>
<Testset name="ts2" tests="2" depends_on="ts1"/>
<Checker src="checker.pp"/>~),
            't' => 'q',
            'checker.pp' => 'z',
    }) } qr/Testset 'ts1' both contains and depends on test 1/, 'Recursive dependency via testest';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Test rank="1-10"><In src="t"/><Out src="t"/></Test>
<Testset name="ts1" tests="1" depends_on="ts2"/>
<Testset name="ts2" tests="2" depends_on="1"/>
<Checker src="checker.pp"/>~),
            't' => 'q',
            'checker.pp' => 'z',
    }) } qr/Testset 'ts1' both contains and depends on test 1/, 'Recursive dependency via test';

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Test rank="1-10"><In src="t"/><Out src="t"/></Test>
<Testset name="ts1" tests="2-5,1" comment="blabla"/>
<Testset name="ts2" tests="ts1,7" hideDetails="1"/>
<Testset name="ts3" tests="10" depends_on="ts1,6"/>
<Checker src="checker.pp"/>~),
            't' => 'q',
            'checker.pp' => 'z',
        });
        is scalar(keys %{$p->{testsets}}), 3, 'Testset count';

        my $ts1 = $p->{testsets}->{ts1};
        is $ts1->{name}, 'ts1', 'Testset 1 name';
        is $ts1->{tests}, '2-5,1', 'Testset 1 tests';
        is $ts1->{comment}, 'blabla', 'Testset 1 comment';
        is $ts1->{hideDetails}, 0, 'Testset 1 hideDetails';

        my $ts2 = $p->{testsets}->{ts2};
        is $ts2->{name}, 'ts2', 'Testset 2 name';
        is $ts2->{tests}, 'ts1,7', 'Testset 2 tests';
        is $ts2->{hideDetails}, 1, 'Testset 2 hideDetails';

        my $ts3 = $p->{testsets}->{ts3};
        is $ts3->{name}, 'ts3', 'Testset 3 name';
        is $ts3->{tests}, '10', 'Testset 2 tests';
        is $ts3->{depends_on}, 'ts1,6', 'Testset 3 depends_on';
    }
};

subtest 'validator', sub {
    plan tests => 10;
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Validator/>~),
    }) } qr/Validator.src/, 'Validator without source';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Validator src="t"/>~),
    }) } qr/Validator.name/, 'Validator without name';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="t.pp"/>
<Test rank="1"><In src="t" validateParam="1"/><Out src="t"/></Test>~),
        't.pp' => 'q',
        't' => 'w',
    }) } qr/validateParam.+1/, 'validateParam without validate';
    my $p = parse({
        'test.xml' => wrap_problem(q~
<Validator name="val" src="t.pp" inputFile="*STDIN"/>
<Checker src="t.pp"/>
<Test rank="1"><In src="t" validate="val" validateParam="99"/><Out src="t"/></Test>~),
        't.pp' => 'q',
        't' => 'w',
    });
    is @{$p->{validators}}, 1, 'validator count';
    my $v = $p->{validators}->[0];
    is $v->{name}, 'val', 'validator name';
    is $v->{src}, 'q', 'validator source';
    is $v->{inputFile}, '*STDIN', 'validator inputFile';
    is keys(%{$p->{tests}}), 1, 'validator test count';
    is $p->{tests}->{1}->{input_validator_id}, 't.pp', 'validator test validate';
    is $p->{tests}->{1}->{input_validator_param}, '99', 'validator test validate param';
};

subtest 'interactor', sub {
    plan tests => 6;
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Interactor/>~),
    }) } qr/Interactor.src/, 'Interactor without source';

    my $p = parse({
        'test.xml' => wrap_problem(q~
<Interactor name="val" src="t.pp"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    is $p->{interactor}->{src}, 'q', 'interactor source';

    my $parser = ParserMockup::make({
        'test.xml' => wrap_problem(q~<Interactor src="t.pp"/><Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q'
    });
    $parser->parse;
    is $parser->logger->{warnings}->[0],
        'Interactor defined when run method is not interactive or competitive', 'interactor defined when not interactive or competitive';

    $parser = ParserMockup::make({
        'test.xml' => wrap_problem(q~<Run method="interactive" /><Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q'
    });
    $parser->parse;

    is $parser->logger->{warnings}->[0],
        'Interactor is not defined when run method is interactive or competitive (maybe used legacy interactor definition)',
        'interactor not defined';
    $parser = ParserMockup::make({
        'test.xml' => wrap_problem(q~
<Run method="interactive"/>
<Interactor src="t.pp"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q'});
    $parser->parse;
    is @{$parser->logger->{warnings}}, 0, 'interactor normal tag definiton';

    $parser = ParserMockup::make({
        'test.xml' => wrap_problem(q~
<Interactor src="t.pp"/>
<Run method="interactive"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q'
    });
    $parser->parse;
    is @{$parser->logger->{warnings}}, 0, 'interactor inverse tag definition';
};

subtest 'run method', sub {
    plan tests => 14;

    my $p = parse({
        'test.xml' => wrap_problem(q~
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    is $p->{run_method}, $cats::rm_default, 'default run method';

    $p = parse({
        'test.xml' => wrap_problem(q~
<Run method="default" />
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    is $p->{run_method}, $cats::rm_default, 'run method = default';

    $p = parse({
        'test.xml' => wrap_problem(q~
<Run method="interactive" />
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    is $p->{run_method}, $cats::rm_interactive, 'run method = interactive';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Run method="asd" />
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    }) } qr/Unknown run method: /, 'bad run method';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Run method="competitive" />
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    }) } qr/Player count limit must be defined for competitive run method/, 'competetive without player count';

    my $parser = ParserMockup::make({
        'test.xml' => wrap_problem(q~
<Run method="default" players_count="1"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    $p = $parser->parse;
    my $w = $parser->logger->{warnings};
    is scalar @$w, 1, 'players_count when not competitive warnings count';
    is $w->[0], 'Player count limit defined when run method is not competitive',
        'players_count when not competitive warning';

    $p = parse({
        'test.xml' => wrap_problem(q~
<Run method="competitive" players_count="2,3-5"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    is $p->{run_method}, $cats::rm_competitive, 'run method = competitive';
    is $p->{players_count}->[0], 2, 'run method = competitive, players_count = 2';

    $p = parse({
        'test.xml' => wrap_problem(q~
<Run method="competitive_modules" players_count="2,3-5"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    is $p->{run_method}, $cats::rm_competitive_modules, 'run method = competitive_modules';
    is $p->{players_count}->[1], 3, 'run method = competitive_modules, players_count = 3';

    $p = parse({
        'test.xml' => wrap_problem(q~
<Run method="competitive" players_count="2,4-5"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });

    is_deeply $p->{players_count}, [ 2, 4, 5 ], 'run method = competitive, players_count = 2,4-5';

    $p = parse({
        'test.xml' => wrap_problem(q~
<Run method="none"/>~),
    });
    is $p->{run_method}, $cats::rm_none, 'run method = none';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Run method="none" />
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    }) } qr/Checker.*none/, 'run method = none but has checker';

};

subtest 'memory unit suffix', sub {
    plan tests => 12;

    my $parse = sub {
        parse({
        'test.xml' => wrap_xml(qq~
<Problem title="asd" lang="en" tlimit="5" inputFile="asd" outputFile="asd" $_[0]>
<Run method="none"/>
</Problem>~),
        })->{description}
    };

    throws_ok { $parse->(q/mlimit="asd"/) } qr/Bad value of 'mlimit'/, 'bad mlimit asd';
    throws_ok { $parse->(q/mlimit="K"/) } qr/Bad value of 'mlimit'/, 'bad mlimit K';
    throws_ok { $parse->(q/mlimit="10K"/) } qr/Value of 'mlimit' must be in whole Mbytes/, 'mlimit 10K';
    is $parse->(q/mlimit="1024K"/)->{memory_limit}, 1, 'mlimit 1024K';
    is $parse->(q/mlimit="1M"/)->{memory_limit}, 1, 'mlimit 1M';
    is $parse->(q/mlimit="1"/)->{memory_limit}, 1, 'mlimit 1';

    throws_ok { $parse->(q/wlimit="asd"/) } qr/Bad value of 'wlimit'/, 'bad wlimit asd';
    throws_ok { $parse->(q/wlimit="K"/) } qr/Bad value of 'wlimit'/, 'bad wlimit K';
    is $parse->(q/wlimit="10B"/)->{write_limit}, 10, 'wlimit 10B';
    is $parse->(q/wlimit="2K"/)->{write_limit}, 2048, 'wlimit 2K';
    is $parse->(q/wlimit="1M"/)->{write_limit}, 1048576, 'wlimit 1M';
    is $parse->(q/wlimit="1"/)->{write_limit}, 1048576, 'wlimit 1';
};

subtest 'sources limit params', sub {
    plan tests => 70;

    my $test = sub {
        my ($tag, $getter) = @_;

        my $xml = $tag eq 'Checker' ? q~
        <Checker src="t.pp" style="testlib" %s/>"~ : qq~
        <$tag name="val" src="t.pp" \%s/><Checker src="t.pp" style="testlib"/>~;

        my $parse = sub {
            parse({
                'test.xml' => wrap_problem(sprintf $xml, $_[0]),
                'checker.pp' => 'begin end.', 't.pp' => 'q'
            })
        };

        throws_ok { $parse->(q/memoryLimit="asd"/) } qr/Bad value of 'memoryLimit'/, "bad memoryLimit asd: $tag";
        throws_ok { $parse->(q/memoryLimit="K"/) } qr/Bad value of 'memoryLimit'/, "bad memoryLimit K: $tag";
        throws_ok { $parse->(q/memoryLimit="10K"/) } qr/Value of 'memoryLimit' must be in whole Mbytes/, "memoryLimit 10K: $tag";
        is $getter->($parse->(q/memoryLimit="1024K"/))->{memory_limit}, 1, "memoryLimit 1024K: $tag";
        is $getter->($parse->(q/memoryLimit="1M"/))->{memory_limit}, 1, "memoryLimit 1M: $tag";
        is $getter->($parse->(q/memoryLimit="1"/))->{memory_limit}, 1, "memoryLimit 1: $tag";
        is $getter->($parse->(q/memoryLimit="1G"/))->{memory_limit}, 1024, "memoryLimit 1G: $tag";

        throws_ok { $parse->(q/writeLimit="asd"/) } qr/Bad value of 'writeLimit'/, "bad writeLimit asd: $tag";
        throws_ok { $parse->(q/writeLimit="K"/) } qr/Bad value of 'writeLimit'/, "bad writeLimit K: $tag";
        is $getter->($parse->(q/writeLimit="10B"/))->{write_limit}, 10, "writeLimit 10B: $tag";
        is $getter->($parse->(q/writeLimit="2K"/))->{write_limit}, 2048, "writeLimit 2K: $tag";
        is $getter->($parse->(q/writeLimit="1M"/))->{write_limit}, 1048576, "writeLimit 1M: $tag";
        is $getter->($parse->(q/writeLimit="1"/))->{write_limit}, 1048576, "writeLimit 1: $tag";
        is $getter->($parse->(q/writeLimit="1G"/))->{write_limit}, 1024 * 1048576, "writeLimit 1G: $tag";
    };

    $test->('Generator', sub { $_[0]->{generators}[0] });
    $test->('Solution', sub { $_[0]->{solutions}[0] });
    $test->('Visualizer', sub { $_[0]->{visualizers}[0] });
    $test->('Checker', sub { $_[0]->{checker} });
    $test->('Interactor', sub { $_[0]->{interactor} });
};

subtest 'linter', sub {
    plan tests => 3;

    my $parse = sub {
        my ($stage) = @_;
        parse({
        'test.xml' => wrap_xml(qq~
<Problem title="asd" lang="en" tlimit="5" inputFile="asd" outputFile="asd" $_[0]>
<Checker src="checker.pp"/>
<Linter name="lint" src="checker.pp" $stage/>
</Problem>~),
        'checker.pp' => 'begin end.',
        });
    };

    throws_ok { $parse->('') } qr/Linter\.stage/, 'no stage';
    throws_ok { $parse->('stage="qqq"') } qr/'qqq'/, 'bad stage';
    is $parse->(q/stage="before"/)->{linters}->[0]->{stage}, 'before', 'before';
};

subtest 'quiz', sub {
    plan tests => 23;

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><Quiz type="zzz" rank="2" points="1"></Quiz></ProblemStatement>
<Run method="none"/>~),
    }) } qr/unknown.*type.*zzz/i, 'Quiz bad type';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><Quiz type="text" rank="2" points="1"></Quiz></ProblemStatement>
<Run method="none"/>~),
    }) } qr/missing\stest.*1/i, 'Quiz bad rank';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><Quiz type="text" rank="1" points="1"></Quiz></ProblemStatement>
<Test rank="1" points="2"><Out>2</Out></Test>
<Run method="none"/>~),
    }) } qr/redefined.*points.*1/i, 'Quiz duplicate points';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><Quiz type="text"><Text>text<Text>text</Text></Text></Quiz></ProblemStatement>
<Run method="none"/>~),
    }) } qr/unexpected.*text/i, 'Quiz nested text';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><Quiz type="text"><Quiz></Quiz></Quiz></ProblemStatement>
<Run method="none"/>~),
    }) } qr/unexpected.*quiz/i, 'Quiz nested';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><Quiz type="checkbox"><Answer/></Quiz></ProblemStatement>
<Run method="none"/>~),
    }) } qr/answer.*checkbox.*text/i, 'Answer not in type text';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><Quiz type="text"><Answer>1</Answer><Answer>2</Answer></Quiz></ProblemStatement>
<Run method="none"/>~),
    }) } qr/redefined.*out_file.*1/i, 'Duplicate Answer';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><Quiz type="text"><Choice/></Quiz></ProblemStatement>
<Run method="none"/>~),
    }) } qr/choice.*text/i, 'Choice inside Quiz.text';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><Quiz type="radiogroup"><Choice correct="1"/><Choice correct="1"/></Quiz></ProblemStatement>
<Run method="none"/>~),
    }) } qr/multiple.*correct/i, 'Multiple correct choices for Quiz.radiogroup';

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<ProblemStatement>
<Quiz type="text" points="3"><Text>123</Text></Quiz>
<Quiz type="text" points="1" descr="q2"></Quiz>
</ProblemStatement>
<Run method="none"/>
<Test rank="1-2"><Out>2</Out></Test>~),
        });
        is $p->{statement}, '
<Quiz points="3" type="text"><Text>123</Text></Quiz>
<Quiz descr="q2" points="1" type="text"></Quiz>
', 'Quiz statement';
        is scalar(keys %{$p->{tests}}), 2, 'Quiz tests num';
        is $p->{tests}->{1}->{points}, 3, 'Quiz points 1';
        is $p->{tests}->{2}->{points}, 1, 'Quiz points 2';
        is $p->{tests}->{2}->{descr}, 'q2', 'Quiz descr';
    }
    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<ProblemStatement><Quiz type="text"><Answer>rr</Answer></Quiz></ProblemStatement>
<Run method="none"/>~),
        });
        is $p->{statement}, '<Quiz type="text"></Quiz>', 'Quiz text answer statement';
        is $p->{tests}->{1}->{in_file}, '1', 'Quiz text in_file';
        is $p->{tests}->{1}->{out_file}, 'rr', 'Quiz text out_file';
    }
    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<ProblemStatement>
<Quiz type="checkbox"><Choice correct="1">one</Choice><Choice>two</Choice><Choice correct="1">three</Choice></Quiz>
<Quiz type="radiogroup"><Choice>one</Choice><Choice correct="1">two</Choice><Choice>three</Choice></Quiz>
</ProblemStatement>
<Run method="none"/>~),
        });
        is $p->{statement}, '
<Quiz type="checkbox"><Choice>one</Choice><Choice>two</Choice><Choice>three</Choice></Quiz>
<Quiz type="radiogroup"><Choice>one</Choice><Choice>two</Choice><Choice>three</Choice></Quiz>
', 'Quiz choices statement';
        is $p->{tests}->{1}->{in_file}, '1', 'Quiz choices in_file 1';
        is $p->{tests}->{1}->{out_file}, '1 3', 'Quiz choices out_file 1';
        is $p->{tests}->{2}->{in_file}, '2', 'Quiz choices in_file 2';
        is $p->{tests}->{2}->{out_file}, '2', 'Quiz choices out_file 2';
    }
    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<ProblemStatement>
<Quiz type="text"><Text>123</Text></Quiz>
<Quiz type="checkbox"><Choice/><Choice/></Quiz>
</ProblemStatement>
<Run method="none"/>~),
        });
        is scalar(keys %{$p->{tests}}), 0, 'Quiz no tests';
    }

};

subtest 'snippets', sub {
    plan tests => 11;

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Snippet name="s-1"/>~),
    }) } qr/invalid.*name.*s\-1/i, 'bad name';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Run method="none"/>
<Snippet name="s1"/><Snippet name="s1"/>~),
    }) } qr/duplicate.*s1/i, 'duplicate name';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Run method="none"/>
<Snippet name="s1"/>
<Test rank="1"><In>1</In><Out snippet="s1">2</Out></Test>~),
    }) } qr/output file.*snippet/i, 'both output and snippet';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Run method="none"/>
<Test rank="1"><In>1</In><Out snippet="s1"/></Test>~),
    }) } qr/undefined.*s1/i, 'bad snippet';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Run method="none"/>
<Snippet name="s1" generator="nogen"/>~),
    }) } qr/undefined.*nogen/i, 'bad generator';

    my $p = parse({
        'test.xml' => wrap_problem(q~
<Run method="none"/>
<Generator name="gen" src="gen.pp"/>
<Snippet name="snipa"/>
<Snippet name="snip1"/>
<Snippet name="snip2" generator="gen"/>
<Test rank="1-2"><In>1</In><Out snippet="snip%n"/></Test>
<Test rank="3"><In>1</In><Out snippet="snipa"/></Test>
~),
        'gen.pp' => 'begin end.',
    });

    is @{$p->{snippets}}, 3, 'snippet count';
    is_deeply [ map $_->{name}, @{$p->{snippets}} ], [ qw(snipa snip1 snip2) ], 'snippet names';
    is $p->{snippets}->[2]->{generator_id}, 'gen.pp', 'snippet 2 gen';
    is_deeply [ map $p->{tests}->{$_}->{snippet_name}, 1..3 ], [ qw(snip1 snip2 snipa) ], 'test snippets';

    my $p1 = parse({
        'test.xml' => wrap_problem(q~
<Run method="none"/>
<Snippet rank="1-4" name="sn%n"/>
<Test rank="1-4"><In>1</In><Out snippet="sn%n"/></Test>~),
    });
    is @{$p1->{snippets}}, 4, 'snippet count 2';
    is_deeply [ map $p1->{tests}->{$_}->{snippet_name}, 1..4 ], [ map "sn$_", 1..4 ], 'test snippets 2';
};

subtest 'modules', sub {
    plan tests => 13;

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Module de_code="1"/>~),
    }) } qr/module.*type/i, 'no type';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Module type="bad" de_code="1"/>~),
    }) } qr/unknown.*type.*bad/i, 'bad type';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Module type="checker" de_code="1"/>~),
    }) } qr/no.*source/i, 'no src';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Module type="checker" de_code="1" src="bad"/>~),
    }) } qr/invalid.*reference.*bad/i, 'bad src';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Module type="checker" de_code="1" src="t.pp" fileName="q.pp"/>~),
        't.pp' => 'q',
    }) } qr/multiple.*sources/i, 'multiple src';
    my $p = parse({
        'test.xml' => wrap_problem(q~
<Checker src="t.pp"/>
<Module type="checker" de_code="1" src="q.pp"/>
<Module type="checker" de_code="1" fileName="m.pp">content</Module>
<Module type="checker" de_code="1" fileName="c.pp">&amp;<![CDATA[
<>&&
]]></Module>~),
        't.pp' => 'q',
        'q.pp' => 'z',
    });
    is @{$p->{modules}}, 3, 'module count';
    is_deeply [ map $_->{kind}, @{$p->{modules}} ], [ ('module') x 3 ], 'module kinds';
    is $p->{modules}->[0]->{path}, 'q.pp', 'module 0 path';
    is $p->{modules}->[0]->{src}, 'z', 'module 0 src';
    is $p->{modules}->[1]->{path}, 'm.pp', 'module 1 path';
    is $p->{modules}->[1]->{src}, 'content', 'module 1 src';
    is $p->{modules}->[2]->{path}, 'c.pp', 'module 2 path';
    is $p->{modules}->[2]->{src}, "&\n<>&&\n", 'module 2 src';
};

subtest 'resources', sub {
    plan tests => 10;

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="t.pp"/>
<Resource name="r-1" url="http://example.com" type="git"/>~),
        't.pp' => 'q',
    }) } qr/invalid.*name.*r\-1/i, 'bad name';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="t.pp"/>
<Resource name="r1" url="http://example.com" type="fgf"/>~),
        't.pp' => 'q',
    }) } qr/invalid.*type.*fgf/i, 'bad type';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="t.pp"/>
<Resource name="r1" type="git"/>~),
        't.pp' => 'q',
    }) } qr/Resource.url/i, 'missing url';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="t.pp"/>
<Resource name="r1" url="http://example1.com" type="git"/>
<Resource name="r2" url="http://example1.com" type="git"/>~),
        't.pp' => 'q',
    }) } qr/duplicate.*url.*r2.*r1/i, 'duplicate url';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="t.pp" resources="r2"/>
<Resource name="r1" url="http://example.com" type="git"/>~),
        't.pp' => 'q',
    }) } qr/undefined.*r2/i, 'bad resource';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Resource name="r1" url="http://example.com" type="git"/>
<Checker src="t.pp" resources="r1,r1"/>~),
        't.pp' => 'q',
    }) } qr/duplicate.*r1/i, 'duplicate resource';

    my $p = parse({
        'test.xml' => wrap_problem(q~
<Resource name="r1" url="http://example1.com" type="git"/>
<Resource name="r2" url="http://example2.com" type="file"/>
<Checker src="t.pp" resources="r2:c,r1"/>~),
        't.pp' => 'q',
    });
    is @{$p->{resources}}, 2, 'resource count';
    is_deeply { %{$p->{resources}->[0]}{qw(name url res_type)} },
        { name => 'r1', url => 'http://example1.com', res_type => 1 }, 'resource 1';
    is_deeply { %{$p->{resources}->[1]}{qw(name url res_type)} },
        { name => 'r2', url => 'http://example2.com', res_type => 2 }, 'resource 2';
    is_deeply $p->{checker}->{resources}, [ [ 'r2', 'c' ], [ 'r1', undef ] ], 'resource refs';
};

subtest 'allow_des', sub {
    plan tests => 6;

    my $parse = sub {
        parse({
            'test.xml' => wrap_problem(qq~<Checker src="t.pp"/>$_[0]~),
            't.pp' => 'q',
        });
    };
    is $parse->('')->{description}->{allow_des}, undef, 'none: everything allowed';
    is_deeply $parse->('<AllowDEs>520,502</AllowDEs>')->{description}->{allow_des}, [ 520, 502 ], 'comma list';
    is_deeply $parse->("<AllowDEs> 102 105\n102 </AllowDEs>")->{description}->{allow_des}, [ 102, 105 ],
        'spaces, newlines, duplicates';
    throws_ok { $parse->('<AllowDEs>502,python</AllowDEs>') } qr/'python' is not a DE code/, 'not a code';
    throws_ok { $parse->('<AllowDEs> </AllowDEs>') } qr/no DE codes/, 'empty';
    throws_ok { parse({ 'test.xml' => wrap_xml('<AllowDEs>1</AllowDEs>') }) } qr/AllowDEs/, 'outside Problem';
};
