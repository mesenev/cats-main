package CATS::Problem::Parser;

use strict;
use warnings;

use Encode;
use JSON::XS;
use List::Util qw(sum);
use XML::Parser::Expat;

use CATS::Constants;
use CATS::Problem;
use CATS::Utils qw(escape_xml);

my $has_formal_input;
BEGIN { $has_formal_input = eval { require FormalInput; 1; } }

use CATS::Problem::TestsParser;

sub new {
    my ($class, %opts) = @_;
    $opts{source} or die "Unknown source for parser";
    $opts{problem} = CATS::Problem->new(%{$opts{problem_desc}});
    $opts{import_source} or die 'Unknown import source';
    $opts{id_gen} or die 'Unknown id generator';
    delete $opts{problem_desc};
    return bless \%opts => $class;
}

sub logger { $_[0]->{source}->{logger} }

sub error {
    my CATS::Problem::Parser $self = shift;
    $self->{source}->error(@_);
}

sub error_stack {
    (my CATS::Problem::Parser $self, my $msg) = @_;
    $self->error("$msg in " . join '/', map $_->{el}, @{$self->{tag_stack}});
}

sub note {
    my CATS::Problem::Parser $self = shift;
    $self->{source}->note(@_);
}

sub warning {
    my CATS::Problem::Parser $self = shift;
    $self->{source}->warning(@_);
}

sub get_zip {
    $_[0]->{source}->get_zip;
}

sub build_tag {
    (my CATS::Problem::Parser $self, my $el, my $atts) = @_;
    "<$el" . join ('', map sprintf(' %s="%s"', $_, escape_xml($atts->{$_})), sort keys %$atts) . '>';
}

sub tag_handlers() {{
    CATS => { s => sub {}, r => ['version'], in => [] },
    ProblemStatement => { stml_src_handlers('statement') },
    ProblemConstraints => { stml_handlers('constraints') },
    InputFormat => { stml_handlers('input_format') },
    OutputFormat => { stml_handlers('output_format') },
    FormalInput => { s => start_stml('formal_input'), e => \&end_tag_FormalInput },
    JsonData => { s => start_stml('json_data'), e => \&end_tag_JsonData },
    Explanation => { stml_src_handlers('explanation') },
    Problem => {
        s => \&start_tag_Problem, e => \&end_tag_Problem,
        r => ['title', 'lang', 'tlimit', 'inputFile', 'outputFile'], in => ['CATS']},

    Attachment => { s => \&start_tag_Attachment, r => ['src', 'name'] },
    Picture => { s => \&start_tag_Picture, r => ['src', 'name'] },
    Snippet => { s => \&start_tag_Snippet, r => ['name'] },
    Resource => { s => \&start_tag_Resource, r => ['url', 'name'] },

    Solution => { s => \&start_tag_Solution, r => ['src', 'name'] },
    Checker => { s => \&start_tag_Checker, r => ['src'] },
    Interactor => { s => \&start_tag_Interactor, r => ['src'] },
    Generator => { s => \&start_tag_Generator, r => ['src', 'name'] },
    Validator => { s => \&start_tag_Validator, r => ['src', 'name'] },
    Visualizer => { s => \&start_tag_Visualizer, r => ['src', 'name'] },
    Linter => { s => \&start_tag_Linter, r => ['src', 'name', 'stage'] },
    GeneratorRange => {
        s => \&start_tag_GeneratorRange, r => ['src', 'name', 'from', 'to'] },
    Module => { s => \&start_tag_Module, e => \&end_stml, r => ['de_code', 'type'] },
    Import => { s => \&start_tag_Import, r => ['guid'] },
    Test => { s => \&start_tag_Test, e => \&end_tag_Test, r => ['rank'] },
    TestRange => {
        s => \&start_tag_TestRange, e => \&end_tag_Test, r => ['from', 'to'] },
    In => { s => \&start_tag_In, e => \&end_tag_In, in => ['Test', 'TestRange'] },
    Out => { s => \&start_tag_Out, e => \&end_tag_Out, in => ['Test', 'TestRange'] },
    Sample => { s => \&start_tag_Sample, e => \&end_tag_Sample, r => ['rank'] },
    SampleIn => { start_end_tag_SampleInOut('in_file', 'in_html'), in => ['Sample'] },
    SampleOut => { start_end_tag_SampleInOut('out_file', 'out_html'), in => ['Sample'] },
    Keyword => { s => \&start_tag_Keyword, r => ['code'] },
    AllowDEs => { s => sub { $_[0]->current_tag->{stml} = \(my $text = '') }, e => \&end_tag_AllowDEs, in => ['Problem'] },
    Testset => { s => \&start_tag_Testset, r => ['name', 'tests'] },
    Run => { s => \&start_tag_Run, r => ['method'] },
    Quiz => {
        s => \&start_tag_Quiz, e => \&end_tag_Quiz,
        r => ['type'], in => ['ProblemStatement'], in_stml => 1 },
    Text => { s => \&start_tag_Text, e => \&end_tag_Text, in => ['Quiz'] },
    Choice => { s => \&start_tag_Choice, e => \&end_tag_Choice, in => ['Quiz'] },
    Answer => { s => \&start_tag_Answer, e => \&end_tag_Answer, in => ['Quiz'] },

    include => {
        s => \&start_tag_include, e => \&end_tag_include, r => ['src'], in_stml => 1 },
    img => {
        s => \&start_tag_img_a_object, e => \&end_nested_in_stml_tag, r => ['picture'], in_stml => 1 },
    a => {
        s => \&start_tag_img_a_object, e => \&end_nested_in_stml_tag, in_stml => 1 },
    object => {
        s => \&start_tag_img_a_object, e => \&end_nested_in_stml_tag, r => ['attachment'], in_stml => 1 },
}}

sub current_tag { $_[0]->{tag_stack}->[-1] }
sub parent_tag { $_[0]->{tag_stack}->[-2] }

sub required_attributes {
    my CATS::Problem::Parser $self = shift;
    my ($el, $attrs, $names) = @_;
    for (@$names) {
        ($attrs->{$_} // '') ne '' or $self->error("$el.$_ not specified");
    }
}

sub set_named_object {
    my CATS::Problem::Parser $self = shift;
    my ($name, $object) = @_;
    $name or return;
    $self->error("Duplicate object reference: '$name'")
        if defined $self->{objects}->{$name};
    $self->{objects}->{$name} = $object;
}

sub get_named_object {
    (my CATS::Problem::Parser $self, my $name, my $kind) = @_;

    defined $name or return undef;
    defined(my $result = $self->{objects}->{$name})
        or $self->error_stack("Undefined object reference: '$name'");
    defined $kind && $result->{kind} ne $kind
        and $self->error_stack("Object '$name' is '$result->{kind}' instead of '$kind'");
    $result;
}

sub get_imported_id {
    (my CATS::Problem::Parser $self, my $name) = @_;

    for (@{$self->{problem}{imports}}) {
        return $_->{id} if $name eq ($_->{name} || '');
    }
    undef;
}

sub read_member_named {
    (my CATS::Problem::Parser $self, my %p) = @_;

    return (
        src => $self->{source}->read_member($p{name}, "Invalid $p{kind} reference: '$p{name}'"),
        path => $p{name},
        kind => $p{kind},
    );
}

sub check_top_tag {
    (my CATS::Problem::Parser $self, my $allowed_tags) = @_;
    my $top_tag = @{$self->{tag_stack}} ? @{$self->{tag_stack}}[-1]->{el} : '';
    return grep $top_tag eq $_, @$allowed_tags;
}

sub checker_added {
    my CATS::Problem::Parser $self = shift;
    $self->{problem}->{has_checker} and $self->error('Found several checkers');
    $self->{problem}->{has_checker} = 1;
}

sub create_generator {
    (my CATS::Problem::Parser $self, my $p) = @_;

    return $self->set_named_object($p->{name}, {
        $self->problem_source_common_params($p, 'generator'),
        outputFile => $p->{outputFile},
    });
}

sub create_validator {
    (my CATS::Problem::Parser $self, my $p) = @_;

    return $self->set_named_object($p->{name}, {
        $self->problem_source_common_params($p, 'validator'),
        inputFile => $p->{inputFile},
    });
}

sub create_visualizer {
    (my CATS::Problem::Parser $self, my $p) = @_;

    return $self->set_named_object($p->{name}, {
        $self->problem_source_common_params($p, 'visualizer')
    });
}

sub validate {
    my CATS::Problem::Parser $self = shift;

    my $check_order = sub {
        my ($objects, $name) = @_;
        my @sorted;
        for (1 .. keys %$objects) {
            exists $objects->{$_} or $self->error("Missing $name #$_");
            push @sorted, $objects->{$_};
        }
        @sorted;
    };

    my $problem = $self->{problem};
    $self->apply_test_defaults;
    my @t = $check_order->($problem->{tests}, 'test');
    for (@t) {
        my $error = validate_test($_) or next;
        $self->error("$error for test $_->{rank}");
    }
    my @no_points = ([], []);
    push @{$no_points[defined $_->{points} ? 0 : 1]}, $_->{rank} for @t;
    $self->warning(sprintf 'Points are defined for tests: %s but not %s',
        map CATS::Testset::pack_rank_spec(@$_), @no_points) if @{$no_points[0]} && @{$no_points[1]};
    $self->validate_testsets;

    for ($check_order->($problem->{samples}, 'sample')) {
        my $error = validate_sample($_);
        $self->error("$error for sample $_->{rank}") if $error;
        $_->{in_file} //= $_->{in_text};
        $_->{out_file} //= $_->{out_text};
    }

    $problem->{run_method} //= $cats::rm_default;

    $problem->{$_} && $problem->{description}->{"${_}_url"}
        and $self->warning("Both stml and url for $_") for qw(statement explanation);
    if ($problem->{run_method} != $cats::rm_none) {
        $problem->{has_checker} or $self->error('No checker specified');
    }
    else {
        !$problem->{has_checker} or $self->error('Checker specified for run method "none"');
    }

    my $need_interactor =
        0 < grep $_ == $problem->{run_method},
        $cats::rm_interactive, $cats::rm_competitive, $cats::rm_competitive_modules;
    $problem->{interactor} && !$need_interactor
        and $self->warning('Interactor defined when run method is not interactive or competitive');

    !$problem->{interactor} && $need_interactor
        and $self->warning(
            'Interactor is not defined when run method is interactive or competitive ' .
            '(maybe used legacy interactor definition)');
}

sub inc_object_ref_count {
    (my CATS::Problem::Parser $self, my $name, my $kind) = @_;
    defined $name and $self->get_named_object($name, $kind)->{refcount}++;
}

sub on_start_tag {
    my CATS::Problem::Parser $self = shift;
    my ($p, $el, %atts) = @_;
    my $h = tag_handlers()->{$el};
    my $top_tag = $self->current_tag;
    my $stml = $top_tag && $top_tag->{stml};
    $stml && $h && !$h->{in_stml} and
        $self->error("Unexpected top-level tag '$el' inside stml of " . $top_tag->{el});
    $stml && !$h && return $$stml .= $self->build_tag($el, \%atts);
    $h or $self->error("Unknown tag $el");
    my $in = $h->{in} // ['Problem'];
    !@$in || $h->{in_stml} || $self->check_top_tag($in)
        or $self->error_stack("Tag '$el' must be inside of " . join(' or ', @$in));
    !$stml && $h->{in_stml} and $self->error("Unexpected stml tag '$el' at top-level");
    $self->required_attributes($el, \%atts, $h->{r}) if $h->{r};
    push @{$self->{tag_stack}}, { el => $el, stml => undef };
    $h->{s}->($self, \%atts, $el);
}

sub on_end_tag {
    my CATS::Problem::Parser $self = shift;
    my ($p, $el, %atts) = @_;

    my $h = tag_handlers()->{$el};
    $h->{e}->($self, \%atts, $el) if $h && $h->{e};
    if (my $stml = $self->current_tag->{stml}) {
        $$stml .= "</$el>";
        return;
    }
    $h or $self->error("Unknown tag $el");
    my $top_tag = pop @{$self->{tag_stack}};
    $el eq $top_tag->{el} or $self->error("Mismatched closing tag $el");
}

sub start_stml {
    my ($v) = @_;
    sub { $_[0]->current_tag->{stml} = \$_[0]->{problem}->{$v} };
}

sub end_stml { undef $_[0]->current_tag->{stml} }

sub stml_handlers { return (s => start_stml(@_), e => \&end_stml); }

sub stml_src_handlers {
    my $start = start_stml(@_);
    my ($field) = @_;
    (
        s => sub {
            (my CATS::Problem::Parser $self, my $atts) = @_;
            $start->(@_);
            my $problem = $self->{problem}->{description};
            for my $src (qw(attachment url)) {
                my $n = $atts->{$src} or next;
                my $url_field = "${field}_url";
                $problem->{$url_field} and $self->error("Several $url_field resources");
                $problem->{$url_field} = $n;
                if ($src eq 'attachment') {
                    $problem->{$url_field} = "file://$n";
                    $self->inc_object_ref_count($n, 'attachment');
                }
                $self->note("$url_field set to $src '$n'");
            }
        },
        e => \&end_stml
    );
}

sub end_tag_FormalInput {
    (my CATS::Problem::Parser $self, my $atts) = @_;
    if (!$has_formal_input) {
      $self->end_stml;
      return $self->warning('Parsing FormalInput tag requires FormalInput module');
    }
    my $parser_err = FormalInput::parserValidate(${$self->current_tag->{stml}});
    if ($parser_err) {
        my $s = FormalInput::errorMessageByCode(FormalInput::getErrCode($parser_err));
        my $l = FormalInput::getErrLine($parser_err);
        my $p = FormalInput::getErrPos($parser_err);
        $self->error("FormalInput: $s. Line: $l. Pos: $p.");
    }
    else {
        $self->note('FormalInput OK.');
    }
    $self->end_stml;
}

sub end_tag_JsonData {
    (my CATS::Problem::Parser $self, my $atts) = @_;
    ${$self->current_tag->{stml}} = Encode::encode_utf8(${$self->current_tag->{stml}});
    eval { decode_json(${$self->current_tag->{stml}}) };
    if ($@) {
        $self->error("JsonData: $@");
    }
    else {
        $self->note('JsonData OK.');
    }
    $self->end_stml;
}

# DE codes the problem allows by default, e.g. "520,502". A contest can still
# set its own list for the problem, which then takes precedence.
sub end_tag_AllowDEs {
    (my CATS::Problem::Parser $self, my $atts) = @_;
    my $text = ${$self->current_tag->{stml}} // '';
    $self->end_stml;
    my @codes = grep length, split /[\s,;]+/, $text;
    @codes or return $self->error('AllowDEs: no DE codes given');
    /^\d+$/ or return $self->error("AllowDEs: '$_' is not a DE code") for @codes;
    my %seen;
    $self->{problem}->{description}->{allow_des} = [ grep !$seen{$_}++, @codes ];
    $self->note('Allowed DEs: ' . join ', ', @{$self->{problem}->{description}->{allow_des}});
}

sub parse_memory_unit {
    my ($atts, $attrib_name, $convert_to, $on_error) = @_;

    $atts->{$attrib_name} or return undef;
    $atts->{$attrib_name} =~ m/^(\d+)([BKMG])?$/ or $on_error->("Bad value of '$attrib_name'");

    my %m = (
        B => 1,
        K => 1 << 10,
        M => 1 << 20,
        G => 1 << 30,
    );

    my $bytes = $1 * $m{$2 || 'M'};

    $bytes % $m{$convert_to} ?
        $on_error->("Value of '$attrib_name' must be in whole ${convert_to}bytes") :
        $bytes / $m{$convert_to};
};

sub start_tag_Problem {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    my $problem = $self->{problem};
    $problem->{description} = {
        title => $atts->{title},
        lang => $atts->{lang},
        time_limit => $atts->{tlimit},
        memory_limit => parse_memory_unit($atts, 'mlimit', 'M', sub { $self->error(@_) }),
        write_limit => parse_memory_unit($atts, 'wlimit', 'B', sub { $self->error(@_) }),
        save_output_prefix => parse_memory_unit($atts, 'saveOutputPrefix', 'B', sub { $self->error(@_) }),
        save_input_prefix => parse_memory_unit($atts, 'saveInputPrefix', 'B', sub { $self->error(@_) }),
        save_answer_prefix => parse_memory_unit($atts, 'saveAnswerPrefix', 'B', sub { $self->error(@_) }),
        difficulty => $atts->{difficulty},
        author => $atts->{author},
        input_file => $atts->{inputFile},
        output_file => $atts->{outputFile},
        std_checker => $atts->{stdChecker},
        max_points => $atts->{maxPoints},
    };
    for ($problem->{description}{memory_limit}) {
        last if defined $_;
        $_ = 200;
        $self->warning("Problem.mlimit not specified. default: $_");
    }

    if ($problem->{description}{std_checker}) {
        $self->warning("Deprecated attribute 'stdChecker', use Import instead");
        $self->checker_added;
    }

    my $ot = $problem->{old_title};
    $self->error(sprintf
        "Unexpected problem rename from: $ot to: $problem->{description}{title}",
    ) if $ot && $problem->{description}{title} ne $ot;
}

sub end_tag_Problem {
    $_[0]->validate;
}

sub start_tag_Attachment {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    push @{$self->{problem}{attachments}},
        $self->set_named_object($atts->{name}, {
            id => $self->{id_gen}->($self, $atts->{src}),
            $self->read_member_named(name => $atts->{src}, kind => 'attachment'),
            name => $atts->{name}, file_name => $atts->{src}, refcount => 0
        });
}

sub start_tag_Picture {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    $atts->{src} =~ /\.([^\.]+)$/ and my $ext = $1
        or $self->error("Invalid image extension for '$atts->{src}'");

    push @{$self->{problem}{pictures}},
        $self->set_named_object($atts->{name}, {
            id => $self->{id_gen}->($self, $atts->{src}),
            $self->read_member_named(name => $atts->{src}, kind => 'picture'),
            name => $atts->{name}, ext => $ext, refcount => 0
        });
}

sub process_Snippet {
    (my CATS::Problem::Parser $self, my $name, my $generator) = @_;

    $name =~ /^[a-zA-Z][a-zA-Z0-9_]*$/
        or $self->error("Invalid snippet name '$name'");

    my $snippet = { name => $name, kind => 'snippet' };
    if (my $gen_id = $generator) {
        $snippet->{generator_id} =
            $self->get_imported_id($gen_id) || $self->get_named_object($gen_id)->{id};
    }
    push @{$self->{problem}->{snippets}}, $self->set_named_object($name, $snippet);
}

sub start_tag_Snippet {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    if ($atts->{rank}) {
        for ($self->parse_test_rank($atts->{rank})) {
            $self->process_Snippet(
                apply_test_rank($atts->{name}, $_),
                apply_test_rank($atts->{generator}, $_),
            );
        }
    }
    else {
        $self->process_Snippet($atts->{name}, $atts->{generator});
    }
}

sub start_tag_Resource {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    my $res_type = $cats::res_types->{$atts->{type}}
        or $self->error("Invalid resource type '$atts->{type}' must be one of: " .
            join ', ', sort keys %$cats::res_types);
    $atts->{name} =~ /^[a-zA-Z][a-zA-Z0-9_]*$/
        or $self->error("Invalid resource name '$atts->{name}'");
    for (@{$self->{problem}->{resources}}) {
        $_->{url} ne $atts->{url}
            or $self->error("Duplicate resource urls for '$atts->{name}' and $_->{name}");
    }

    my $resource = {
        id => $self->{id_gen}->($self, $atts->{name}), kind => 'resource',
        %$atts{qw(name url)}, res_type => $res_type };
    push @{$self->{problem}->{resources}}, $self->set_named_object($atts->{name}, $resource);
}

sub parse_resources_list {
    (my CATS::Problem::Parser $self, my $atts) = @_;
    my $r = $atts->{resources} or return [];
    my %h;
    my $parse_single = sub {
        my ($res_ref) = @_;
        my ($name, $stages) = $res_ref =~ m/^([a-zA-Z0-9_]+)(?::(c|r|cr|rc))?$/ or $self->error(
            sprintf q~Incorrect resource reference '%s' for source '%s'~, $_, $atts->{name} // '?');
        $h{$name}++ and $self->error(
            sprintf q~Duplicate resource '%s' for source '%s'~, $name, $atts->{name} // '?');
        [ $self->get_named_object($name, 'resource')->{id}, $stages ];
    };
    [ map $parse_single->($_), split ',', $r ];
}

sub problem_source_common_params {
    (my CATS::Problem::Parser $self, my $atts, my $kind) = @_;
    return (
        id => $self->{id_gen}->($self, $atts->{src}),
        $self->read_member_named(name => $atts->{src}, kind => $kind),
        de_code => $atts->{de_code},
        guid => $atts->{export},
        time_limit => $atts->{timeLimit},
        memory_limit => parse_memory_unit($atts ,'memoryLimit', 'M', sub { $self->error(@_) }),
        write_limit => parse_memory_unit($atts, 'writeLimit', 'B', sub { $self->error(@_) }),
        name => $atts->{name},
        resources => $self->parse_resources_list($atts),
    );
}

sub start_tag_Solution {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    my $sol = $self->set_named_object($atts->{name}, {
        $self->problem_source_common_params($atts, 'solution'),
        checkup => $atts->{checkup},
    });
    push @{$self->{problem}{solutions}}, $sol;
}

sub start_tag_Checker {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    my $style = $atts->{style} || 'legacy';
    CATS::Problem::checker_type_names->{$style}
        or $self->error(q~Unknown checker style (must be 'legacy', 'testlib', 'partial' or 'multiple')~);
    $style ne 'legacy'
        or $self->warning('Legacy checker found!');
    $self->checker_added;
    $self->{problem}{checker} = {
        $self->problem_source_common_params($atts, 'checker'), style => $style
    };
}

sub start_tag_Interactor {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    $self->error('Found several interactors') if exists $self->{problem}{interactor};

    $self->{problem}{interactor} = {
        $self->problem_source_common_params($atts, 'interactor')
    };
}

sub start_tag_Generator {
    (my CATS::Problem::Parser $self, my $atts) = @_;
    push @{$self->{problem}{generators}}, $self->create_generator($atts);
}

sub start_tag_Validator {
    (my CATS::Problem::Parser $self, my $atts) = @_;
    push @{$self->{problem}{validators}}, $self->create_validator($atts);
}

sub start_tag_Visualizer {
    (my CATS::Problem::Parser $self, my $atts) = @_;
    push @{$self->{problem}{visualizers}}, $self->create_visualizer($atts);
}

sub start_tag_Linter {
    (my CATS::Problem::Parser $self, my $atts) = @_;
    my $stage = $atts->{stage};
    $stage =~ /^before|after$/ or $self->error("Bad stage '$stage': must be 'before' or 'after'");
    push @{$self->{problem}{linters}}, $self->set_named_object($atts->{name}, {
        $self->problem_source_common_params($atts, 'linter'), stage => $stage,
    });
;
}

sub start_tag_GeneratorRange {
    (my CATS::Problem::Parser $self, my $atts) = @_;
    for ($atts->{from} .. $atts->{to}) {
        push @{$self->{problem}{generators}}, $self->create_generator({
            name => apply_test_rank($atts->{name}, $_),
            src => apply_test_rank($atts->{src}, $_),
            export => apply_test_rank($atts->{export}, $_),
            de_code => $atts->{de_code},
            outputFile => $atts->{outputFile},
        });
    }
}

sub start_tag_Module {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    exists CATS::Problem::module_types()->{$atts->{type}}
        or $self->error("Unknown module type: '$atts->{type}'");
    $atts->{src} || $atts->{fileName}
        or $self->error('No source defined for module');
    $atts->{src} && $atts->{fileName}
        and $self->error('Multiple sources defined for module');
    push @{$self->{problem}{modules}}, my $m = {
        id => $self->{id_gen}->($self, $atts->{src} || $atts->{fileName}),
        ($atts->{src} ?
            $self->read_member_named(name => $atts->{src}, kind => 'module') :
            (path => $atts->{fileName}, kind => 'module')),
        de_code => $atts->{de_code},
        guid => $atts->{export}, type => $atts->{type},
        type_code => CATS::Problem::module_types()->{$atts->{type}},
        main => $atts->{main},
    };
    if ($atts->{fileName}) {
        $self->current_tag->{is_literal} = 1;
        $self->current_tag->{stml} = \($m->{src} = '');
    }
}

sub import_one_source {
    my CATS::Problem::Parser $self = shift;
    my ($guid, $name, $type_name) = @_;
    push @{$self->{problem}{imports}}, my $import = { guid => $guid, name => $name };
    my ($src_id, $stype) = $self->{import_source}->get_source($guid);

    my $type;
    !$type_name || ($type = $import->{type} = CATS::Problem::module_types()->{$type_name})
        or $self->error("Unknown import source type: '$type_name'");

    if ($src_id) {
        !$type || $stype == $type || $cats::source_modules{$stype} == $type
            or $self->error(sprintf q~Import type check failed for guid='%s' expected: '%s' got: '%s'~,
                $guid, map $cats::source_module_names{$_}, $type, $stype);
        $self->checker_added
            if defined $cats::source_modules{$stype} && $cats::source_modules{$stype} == $cats::checker_module;
        $import->{src_id} = $src_id;
        $import->{id} = $self->{id_gen}->($self, $name);
        $self->note("Imported source from guid='$guid'");
    }
    else {
        $self->warning("Import source not found for guid='$guid'");
    }

}

sub start_tag_Import {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    my ($guid, @nt) = @$atts{qw(guid name type)};
    if ($guid =~ /\*/) {
        $self->import_one_source($_, @nt) for $self->{import_source}->get_guids($guid);
    }
    else {
        $self->import_one_source($guid, @nt);
    }
}

sub validate_sample {
    my ($sample) = @_;
    !defined $sample->{in_file} ? 'Neither src nor inline data specified for SampleIn' :
    !defined $sample->{out_file} ? 'Neither src nor inline data specified for SampleOut' :
    undef;
}

sub start_tag_Sample {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    $self->{current_samples} =
        CATS::Testset::parse_simple_rank($atts->{rank}, sub { $self->error(@_) });
    my $ps = $self->{problem}->{samples} //= {};
    $ps->{$_} //= { sample_id => $self->{id_gen}->($self, "Sample_$_"), rank => $_ }
        for @{$self->{current_samples}};
}

sub end_tag_Sample {
    my CATS::Problem::Parser $self = shift;
    delete $self->{current_sample_data};
    delete $self->{current_samples};
}

sub sample_inout_file {
    (my CATS::Problem::Parser $self, my $rank, my $in_out) = @_;
    my $f = \$self->{problem}->{samples}->{$rank}->{$in_out};
    defined $$f and $self->error(sprintf "Redefined source for %s %d", $self->current_tag->{el}, $rank);
    $f;
}

sub start_sample_in_out {
    my CATS::Problem::Parser $self = shift;
    my ($atts, $in_out, $html) = @_;
    if ($atts->{src}) {
        for (@{$self->{current_samples}}) {
            my $f = $self->sample_inout_file($_, $in_out);
            my $src = apply_test_rank($atts->{src}, $_);
            $$f = $self->{source}->read_member($src, "Invalid sample $in_out reference: '$src'");
        }
    }
    if (exists $atts->{html}) {
        for (@{$self->{current_samples}}) {
            my $h = \$self->{problem}->{samples}->{$_}->{$html};
            defined $$h and $self->error(
                sprintf "Redefined html attribute for %s %d", $self->current_tag->{el}, $_);
            $$h = $atts->{html};
        }
    }
    $self->current_tag->{is_literal} = !$atts->{html};
    $self->current_tag->{stml} = \($self->{current_sample_data}->{$in_out} = '');
}

sub end_sample_in_out {
    (my CATS::Problem::Parser $self, my $in_out) = @_;
    $self->end_stml;
    my $t = $self->{current_sample_data}->{$in_out};
    return if $t eq '';
    my $html = $self->{current_sample_data}->{html}->{$in_out};
    for (@{$self->{current_samples}}) {
        ${$self->sample_inout_file($_, $in_out)}= $t;
    }
}

sub start_end_tag_SampleInOut {
    my ($in_out, $html) = @_;
    (
        s => sub { $_[0]->start_sample_in_out($_[1], $in_out, $html) },
        e => sub { $_[0]->end_sample_in_out($in_out) },
    );
}

sub start_tag_Keyword {
    (my CATS::Problem::Parser $self, my $atts) = @_;

    my $c = $atts->{code};
    !defined $self->{problem}{keywords}->{$c}
        or $self->warning("Duplicate keyword '$c'");
    $self->{problem}{keywords}->{$c} = 1;
}

sub start_tag_Run {
    (my CATS::Problem::Parser $self, my $atts) = @_;
    my $m = $atts->{method};
    $self->error("Duplicate run method '$m'") if defined $self->{problem}{run_method};
    my %methods = (
        default => $cats::rm_default,
        interactive => $cats::rm_interactive,
        competitive => $cats::rm_competitive,
        competitive_modules => $cats::rm_competitive_modules,
        none => $cats::rm_none,
    );
    defined($self->{problem}{run_method} = $methods{$m})
        or $self->error("Unknown run method: '$m', must be one of: " . join ', ', sort keys %methods);

    my $is_competitive =
        0 < grep $self->{problem}{run_method} == $_,
        $cats::rm_competitive, $cats::rm_competitive_modules;
    if ($is_competitive) {
        $atts->{players_count}
            or $self->error("Player count limit must be defined for competitive run method");
        $self->{problem}{players_count} =
            CATS::Testset::parse_simple_rank($atts->{players_count}, sub { $self->error(@_) });
    }
    else {
        defined $atts->{players_count}
            and $self->warning("Player count limit defined when run method is not competitive");
    }

    $self->note("Run method set to '$m'");
}

sub end_nested_in_stml_tag {
    (my CATS::Problem::Parser $self, my $atts, my $el) = @_;
    ${$self->parent_tag->{stml}} .= ${$self->current_tag->{stml}} . "</$el>";
    undef $self->current_tag->{stml};
}

sub start_tag_include {
    (my CATS::Problem::Parser $self, my $atts) = @_;
    my $name = $atts->{src};
    ${$self->current_tag->{stml}} .= Encode::decode(
        $self->{problem}{encoding},
        $self->{source}->read_member($name, "Invalid 'include' reference: '$name'")
    );
}

sub end_tag_include {
    (my CATS::Problem::Parser $self, my $atts, my $el) = @_;
    ${$self->parent_tag->{stml}} .= ${$self->current_tag->{stml}};
    undef $self->current_tag->{stml};
}

sub start_tag_img_a_object {
    (my CATS::Problem::Parser $self, my $atts, my $el) = @_;
    ${$self->current_tag->{stml}} .= $self->build_tag($el, $atts);
    my $attr = { img => 'picture', a => 'attachment', object => 'attachment' }->{$el};
    $self->inc_object_ref_count($atts->{$attr}, $attr) if $attr;
}

sub parse_xml {
    (my CATS::Problem::Parser $self, my $xml_file) = @_;
    $self->{tag_stack} = [];

    my $parse_Char = sub {
        my $c = $self->current_tag;
        for ($c->{stml}) {
            $_ or return;
            $$_ .= $c->{is_literal} ? $_[1] : escape_xml($_[1]);
        }
    };

    my $xml_parser = XML::Parser::Expat->new;
    $xml_parser->setHandlers(
        Start => sub { $self->on_start_tag(@_) },
        End => sub { $self->on_end_tag(@_) },
        Char => $parse_Char,
        XMLDecl => sub { $self->{problem}->{encoding} = $_[2] },
    );
    $xml_parser->parse($self->{source}->read_member($xml_file));
}

sub parse {
    my $self = shift;
    $self->{source}->init;

    my @xml_members = $self->{source}->find_members('\.xml$');
    $self->error('*.xml not found') if !@xml_members;
    $self->error('found several *.xml in archive') if @xml_members > 1;

    $self->parse_xml($xml_members[0]);
    return $self->{problem};
}

1;
