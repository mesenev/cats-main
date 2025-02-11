package CATS::UI::RunDetails;

use strict;
use warnings;

use Encode;
use List::Util qw(max min);
use JSON::XS;

use CATS::BinaryFile;
use CATS::Constants;
use CATS::DB;
use CATS::DetectImage;
use CATS::Globals qw($cid $contest $is_jury $is_root $t $uid $user);
use CATS::IP;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template downloads_path downloads_url search url_f url_f_cid);
use CATS::Problem::Utils;
use CATS::ReqDetails qw(
    get_compilation_error
    get_contest_info
    get_contest_tests
    get_log_dump
    get_req_details
    get_sources_info
    get_test_data
    sources_info_param
    source_links);
use CATS::Request;
use CATS::Score;
use CATS::Settings qw($settings);
use CATS::Testset;
use CATS::Utils;
use CATS::Verdicts;

sub _decode_quietly {
    my ($p, $s) = @_;
    $s //= '';
    return CATS::Utils::hex_dump($s) if $p->{comment_enc} eq 'HEX';
    # Comment or output may be non-well-formed utf8.
    my $result = eval { Encode::decode($p->{comment_enc}, $s, Encode::FB_QUIET); } // '';
    # Encode::decode modifies $s to contain non-well-formed part.
    $result . ($s eq '' ? '' : "\x{fffd}$s");
}

sub _get_run_info {
    my ($p, $contest, $req) = @_;
    my $points = $contest->{points};

    my $last_test = 0;
    my $total_points = 0;
    my $all_testsets = CATS::Testset::get_all_testsets($dbh, $req->{problem_id});
    my %testset = CATS::Testset::get_testset($dbh, 'reqs', $req->{req_id});
    $contest->{show_points} ||= 0 < grep $_, values %testset;
    my (%run_details, %used_testsets, %accepted_tests, %accepted_deps);

    my @resources = qw(time_used memory_used disk_used);
    my $rd_fields = join ', ', (
         qw(test_rank result points),
         ($contest->{show_test_resources} ? @resources : ()),
         ($contest->{show_checker_comment} ? qw(checker_comment) : ()),
    );

    for my $row (get_req_details($contest, $req, $rd_fields, \%accepted_tests)) {
        $_ and $_ = sprintf('%.3g', $_) for $row->{time_used};
        if ($contest->{show_checker_comment}) {
            $row->{checker_comment} = _decode_quietly($p, $row->{checker_comment});
        }

        $last_test = $row->{test_rank};
        my $test_points = $points->[$row->{test_rank} - 1] // 0;
        my $p =
            !$row->{is_accepted} ? 0 :
            !defined $row->{points} ? $test_points :
            min(max($row->{points}, 0), $test_points);
        if (my $ts = $row->{ts} = $testset{$last_test}) {
            $used_testsets{$ts->{name}} = $ts;
            $ts->{accepted_count} //= 0;
            push @{$ts->{list} ||= []}, $last_test;
            if (CATS::Score::dependencies_accepted($all_testsets, $ts, \%accepted_tests, \%accepted_deps)) {
                $ts->{accepted_count} += $row->{is_accepted};
                if (!$row->{is_accepted} && ($ts->{failed_test} // 1e12) > $last_test) {
                    $ts->{failed_test} = $last_test;
                    $ts->{verdict} = $CATS::Verdicts::state_to_name->{$row->{result}};
                }
                if (defined $ts->{points}) {
                    $total_points += $ts->{earned_points} = $ts->{points}
                        if $ts->{accepted_count} == $ts->{test_count};
                }
                else {
                    $total_points += $p;
                    $ts->{earned_points} += $p;
                }
            }
            else {
                $p = 'X';
            }
            if ($ts->{hide_details} && $contest->{hide_testset_details}) {
                $row->{is_hidden} = 1;
            }
            if (defined $ts->{points} || $ts->{hide_details} && $contest->{hide_testset_details}) {
                $p = '';
            }
            $p .= " => $ts->{name}";
        }
        else {
            $total_points += $p;
        }
        $run_details{$last_test} = {
            %$row, points => $p,
            short_state => $row->{is_hidden} ? '' : $CATS::Verdicts::state_to_name->{$row->{result}},
        };
    }

    # Output 'not processed' for tests we do not plan to run, but must still display.
    if ($contest->{show_all_tests} && !$contest->{run_all_tests}) {
        $last_test = @$points;
    }
    if ($contest->{hide_testset_details}) {
        for (values %used_testsets) {
            $_->{accepted_count} = '?'
                if $_->{hide_details} && $_->{accepted_count} != $_->{test_count};
        }
    }

    my $run_row = sub {
        my ($rank) = @_;
        return $run_details{$rank} if exists $run_details{$rank};
        return () unless $contest->{show_all_tests};
        my %r = (test_rank => $rank, ts => $testset{$rank});
        $r{short_state} = exists $testset{$rank} ? 'NP' : 'NT';
        return \%r;
    };

    # INNER JOIN must come first to avoid confusing Firebird optimizer.
    my $visualizers = $dbh->selectall_arrayref(q~
        SELECT PS.id, COALESCE(PSL.name, PSLE.name) AS name
        FROM problem_sources PS
        INNER JOIN reqs R ON R.problem_id = PS.problem_id
        LEFT JOIN problem_sources_local PSL ON PSL.id = PS.id
        LEFT JOIN problem_sources_imported PSI ON PSI.id = PS.id
        LEFT JOIN problem_sources_local PSLE ON PSLE.guid = PSI.guid
        WHERE R.id = ? AND COALESCE(PSL.stype, PSLE.stype) = ?~, { Slice => {} },
        $req->{req_id}, $cats::visualizer);

    my %outputs = map { $_->{test_rank} => $_->{output} } @{$dbh->selectall_arrayref(qq~
        SELECT SO.test_rank,
            SUBSTRING(SO.output FROM 1 FOR $cats::test_file_cut + 1) AS output
        FROM solution_output SO WHERE SO.req_id = ? AND SO.test_rank <= ?~, { Slice => {} },
        $req->{req_id}, $last_test)};

    my $snippet_answers = $contest->{show_test_data} ? $dbh->selectall_hashref(q~
        SELECT T.rank, S.text
        FROM tests T INNER JOIN snippets S
            ON T.snippet_name = S.name AND
            S.contest_id = ? AND S.problem_id = T.problem_id AND S.account_id = ?
        WHERE T.problem_id = ?~, 'rank', { Slice => {} },
        $contest->{id}, $req->{account_id}, $req->{problem_id}) : {};

    my $maximums = { map { $_ => 0 } @resources };
    my $add_testdata = sub {
        my ($row) = @_ or return ();
        $contest->{show_test_data} or return $row;
        my $t = $contest->{tests}->[$row->{test_rank} - 1] or return $row;
        $row->{descr} = $t->{descr};
        $t->{param} //= '';
        $row->{input_gen_params} = CATS::Problem::Utils::gen_group_text($t);
        $row->{input_data_cut} = length($t->{input} // '') > $cats::test_file_cut;
        $row->{input_data} =
            _decode_quietly($p, defined $t->{input} ? $t->{input} : $row->{input_gen_params});
        $row->{snippet_name} = $t->{snippet_name};
        my $answer = $snippet_answers->{$row->{test_rank}}->{text} // $t->{answer};
        $row->{answer_data_cut} = length($answer // '') > $cats::test_file_cut;
        $row->{answer_data} = _decode_quietly($p, $answer);
        $row->{visualize_test_hrefs} =
            defined $t->{input} ? [ map +{
                href => url_f('visualize_test',
                    rid => $req->{req_id}, test_rank => $row->{test_rank}, vid => $_->{id}),
                name => $_->{name}
            }, @$visualizers ] : [];
        $maximums->{$_} = max($maximums->{$_}, $row->{$_} // 0) for @resources;
        my $output_data = $outputs{$row->{test_rank}} // '';
        $row->{output_data_cut} = length($output_data) > $cats::test_file_cut;
        $row->{output_data} = _decode_quietly($p, $output_data);
        # Visible end-of-line.
        $row->{$_} =~ s/[\r\n]+/\x{23CE}/mg for qw(input_data output_data answer_data);
        $row->{href_view_test_details} =
            url_f('view_test_details', rid => $req->{req_id}, test_rank => $row->{test_rank});
        $row;
    };
    if (
        $contest->{show_points} && $contest->{points} &&
        # Do not cache incomplete points to avoid messing up RankTable cache.
        $req->{state} > $cats::request_processed &&
        $req->{state} != $cats::st_security_violation &&
        $req->{state} != $cats::st_manually_rejected &&
        (!defined $req->{points} || $req->{points} != $total_points)
    ) {
        $req->{points} //= $total_points;
        eval {
            $req->{needs_commit} = $dbh->do(q~
                UPDATE reqs SET points = ? WHERE id = ? AND points IS NULL~, undef,
                $req->{points}, $req->{req_id});
            1;
        } or $CATS::DB::db->catch_deadlock_error("get_run_info $req->{req_id}");
    }

    return {
        %$contest,
        id => $req->{req_id},
        total_points => $total_points,
        scaled_points => CATS::Score::scale_points($total_points, $req),
        run_details => [ map $add_testdata->($run_row->($_)), 1..$last_test ],
        maximums => $maximums,
        testsets => [ sort { $a->{list}[0] <=> $b->{list}[0] } values %used_testsets ],
        accepted_deps => \%accepted_deps,
        has_depends_on => 0 < grep($_->{depends_on}, values %used_testsets),
        has_visualizer => @$visualizers > 0,
        has_output => $req->{save_output_prefix},
    };
}

sub _set_points {
    my ($p) = @_;
    $is_jury && $p->{set_points} && $p->{set_points_req_id} or return;
    my ($req_id, $pid) = $dbh->selectrow_array(q~
        SELECT id, problem_id FROM reqs WHERE contest_id = ? AND id = ?~, undef,
        $cid, $p->{set_points_req_id}) or return;
    my @points = @{$p->{points}};
    my @ranks = @{$p->{rank}};
    @points && @points == @ranks or return;
    my $test_ranks = $dbh->selectcol_arrayref(q~
        SELECT rank FROM tests WHERE problem_id = ?~, undef,
        $pid);
    my %existing_tests;
    $existing_tests{$_} = 1 for @$test_ranks;
    my $update_sth = $dbh->prepare(q~
        UPDATE req_details SET result = ?, points = ?
        WHERE req_id = ? AND test_rank = ?~);
    my $insert_sth = $dbh->prepare(q~
        INSERT INTO req_details (req_id, test_rank, result, points)
        VALUES (?, ?, ?, ?)~);
    my $delete_sth = $dbh->prepare(q~
        DELETE FROM req_details WHERE req_id = ? AND test_rank = ?~);
    my $count = 0;
    for (my $i = 0; $i < @points; ++$i) {
        my $rank = $ranks[$i];
        $existing_tests{$rank} or next;
        my $pts = $points[$i];

        if ($pts eq '') {
            $count += $delete_sth->execute($req_id, $rank);
        }
        elsif ($update_sth->execute($cats::st_accepted, $pts, $req_id, $rank) > 0) {
            $count += 1;
        }
        else {
            $count += $insert_sth->execute($req_id, $rank, $cats::st_accepted, $pts);
        }
    }
    $count or return;
    $dbh->do(q~
        UPDATE reqs SET points = NULL WHERE id = ? AND points IS NOT NULL~, undef,
        $req_id);
    $dbh->commit;
}

sub _get_display_settings {
    my ($settings) = @_;
    return (
        display_input => $settings->{display_input},
        display_answer => $settings->{display_input},
        display_output => $settings->{display_input}, #TODO: Add this params to settings
    );
}

sub run_details_frame {
    my ($p) = @_;
    init_template($p, 'run_details');

    _set_points($p);
    my $sources_info = get_sources_info($p, request_id => $p->{rid}) or return;
    my @runs;
    my $contest_cache = {};

    my $needs_commit;
    for (@$sources_info) {
        source_links($p, $_);
        my $st = $_->{state};
        if ($st == $cats::st_compilation_error || $st == $cats::st_lint_error) {
            my $logs = get_log_dump({ req_id => $_->{req_id} });
            push @runs, { compiler_output => get_compilation_error($logs, $st) };
            next;
        }
        my $c = get_contest_tests(get_contest_info($p, $_, $contest_cache), $_->{problem_id});
        push @runs, _get_run_info($p, $c, $_);
        $needs_commit ||= $_->{needs_commit};
    }
    $dbh->commit if $needs_commit;
    sources_info_param($sources_info);
    $t->param(runs => \@runs, _get_display_settings($settings));
}

sub save_visualizer {
    my ($data, $lfname, $pid, $hash) = @_;

    CATS::Problem::Utils::ensure_problem_hash($pid, \$hash, 1);

    my $fname = "vis/${hash}_$lfname";
    my $fpath = downloads_path . $fname;
    -f $fpath or CATS::BinaryFile::save($fpath, $data);
    return downloads_url . $fname;
}

sub visualize_test_frame {
    my ($p) = @_;
    init_template($p, 'visualize_test.html.tt');

    $uid or return;
    my $rid = $p->{rid} or return;
    my $vid = $p->{vid} or return;
    my $test_rank = $p->{test_rank} or return;

    my $sources_info = get_sources_info($p,
        request_id => $rid, extra_params => [ test_rank => $test_rank, vid => $p->{vid} ]);
    source_links($p, $sources_info);
    sources_info_param([ $sources_info ]);

    my $ci = get_contest_info($p, $sources_info, {});
    $ci->{show_test_data} or return;

    my @tests = get_req_details($ci, $sources_info, 'test_rank, result', {});
    grep $_->{test_rank} == $test_rank, @tests or return;

    my $visualizer = $dbh->selectrow_hashref(q~
        SELECT
            COALESCE(PSL.name, PSLE.name) AS name,
            COALESCE(PSL.src, PSLE.src) AS src,
            COALESCE(PSL.fname, PSLE.fname) AS fname,
        P.id AS problem_id, P.hash
        FROM problem_sources PS
        INNER JOIN problems P ON PS.problem_id = P.id
        INNER JOIN reqs R ON R.problem_id = P.id
        LEFT JOIN problem_sources_local PSL ON PSL.id = PS.id
        LEFT JOIN problem_sources_imported PSI ON PSI.id = PS.id
        LEFT JOIN problem_sources_local PSLE ON PSLE.guid = PSI.guid
        WHERE R.id = ? AND PS.id = ? AND COALESCE(PSL.stype, PSLE.stype) = ?~, { Slice => {} },
        $rid, $vid, $cats::visualizer) or return;

    my @imports_js = (@{$dbh->selectall_arrayref(q~
        SELECT
            COALESCE(PSL.name, PSLE.name) AS name,
            COALESCE(PSL.src, PSLE.src) AS src,
        PS.problem_id, P.hash
        FROM problem_sources PS
        INNER JOIN problems P ON P.id = PS.problem_id
        LEFT JOIN problem_sources_local PSL ON PSL.id = PS.id
        LEFT JOIN problem_sources_imported PSI ON PSI.id = PS.id
        LEFT JOIN problem_sources_local PSLE ON PSLE.guid = PSI.guid
        WHERE PS.problem_id = ? AND COALESCE(PSL.stype, PSLE.stype) = ?~, { Slice => {} },
        $visualizer->{problem_id}, $cats::visualizer_module)}, $visualizer);

    my $test_data = get_test_data($p) or return;

    @{$test_data}{qw(output output_size)} = $dbh->selectrow_array(q~
        SELECT SO.output, SO.output_size
        FROM solution_output SO
        WHERE SO.req_id = ? AND SO.test_rank = ?~, undef,
        $rid, $test_rank);

    my $vhref = sub { url_f('visualize_test', rid => $rid, test_rank => $_[0], vid => $vid) };

    $t->param(
        vis_scripts => [
            map save_visualizer($_->{src}, $_->{fname}, $_->{problem_id}, $_->{hash}), @imports_js
        ],
        test_data_json => JSON::XS->new->utf8->indent(2)->canonical->encode($test_data),
        visualizer => $visualizer,
        href_prev_pages => $test_rank > $tests[0]->{test_rank} ? $vhref->($test_rank - 1) : undef,
        href_next_pages => $test_rank < $tests[-1]->{test_rank} ? $vhref->($test_rank + 1) : undef,
        test_ranks => [
            map +{
                page_number => $_->{test_rank},
                href_page => $vhref->($_->{test_rank}),
                current_page => $_->{test_rank} == $test_rank,
                short_verdict => $CATS::Verdicts::state_to_name->{$_->{result}},
            }, @tests
        ],
    );
}

sub view_test_details_frame {
    my ($p) = @_;
    init_template($p, 'view_test_details');

    $p->{rid} or return;
    $p->{test_rank} //= 1;

    my $sources_info = get_sources_info($p,
        request_id => $p->{rid}, extra_params => [ test_rank => $p->{test_rank} ]) or return;

    my $ci = get_contest_info($p, $sources_info, {});
    $ci->{show_test_data} or return;

    my $output_data;
    if ($is_jury && $p->{delete_request_outputs}) {
        $dbh->do(q~
            DELETE FROM solution_output SO WHERE SO.req_id = ?~, undef,
            $p->{rid});
        $dbh->commit;
    } elsif($is_jury && $p->{delete_test_output}) {
        $dbh->do(q~
            DELETE FROM solution_output SO WHERE SO.req_id = ? AND SO.test_rank = ?~, undef,
            $p->{rid}, $p->{test_rank});
        $dbh->commit;
    } else {
        $output_data = $dbh->selectrow_hashref(q~
            SELECT SO.output, SO.output_size FROM solution_output SO
            WHERE SO.req_id = ? AND SO.test_rank = ?~, { Slice => {} },
            $p->{rid}, $p->{test_rank});
        !$p->{noimage} && CATS::DetectImage::add_image_data($output_data, 'output') or
            $output_data->{decoded} = _decode_quietly($p, $output_data->{output});
    }

    my $save_prefix_lengths = $dbh->selectrow_hashref(q~
        SELECT
            P.save_input_prefix AS input_prefix,
            P.save_answer_prefix AS answer_prefix,
            P.save_output_prefix AS output_prefix
        FROM problems P
        INNER JOIN reqs R ON R.problem_id = P.id
        WHERE R.id = ?~, { Slice => {} },
        $p->{rid});

    my $test_data = get_test_data($p) or return;
    for (qw(input answer)) {
        !$p->{noimage} && CATS::DetectImage::add_image_data($test_data, $_) or
            $test_data->{"decoded_$_"} = _decode_quietly($p, $test_data->{$_});
    }

    my $tdhref = sub { url_f('view_test_details', rid => $p->{rid}, test_rank => $_[0]) };

    my @tests = get_req_details($ci, $sources_info, 'test_rank, result', {});
    $is_root || grep $_->{test_rank} == $p->{test_rank}, @tests or return;

    source_links($p, $sources_info);
    sources_info_param([ $sources_info ]);
    $t->param(
        output_data => $output_data,
        test_data => $test_data,
        save_prefix_lengths => $save_prefix_lengths,
        href_prev_pages =>
            @tests && $p->{test_rank} > $tests[0]->{test_rank} && $tdhref->($p->{test_rank} - 1),
        href_next_pages =>
            @tests && $p->{test_rank} < $tests[-1]->{test_rank} && $tdhref->($p->{test_rank} + 1),
        test_ranks => [
            map +{
                page_number => $_->{test_rank},
                href_page => $tdhref->($_->{test_rank}),
                current_page => $_->{test_rank} == $p->{test_rank},
                short_verdict => $CATS::Verdicts::state_to_name->{$_->{result}},
            }, @tests
        ],
        _get_display_settings($settings),
    );
}

sub run_log_frame {
    my ($p) = @_;
    init_template($p, 'run_log.html.tt');
    my $rid = $p->{rid} or return;

    my $si = get_sources_info($p, request_id => $rid)
        or return;
    $si->{is_jury} or return;

    source_links($p, $si);
    sources_info_param([ $si ]);

    CATS::Request::delete_logs({ req_id => $rid }) if $p->{delete_log};
    CATS::Request::delete_jobs({ req_id => $rid }) if $p->{delete_jobs};

    $t->param(
        href_jobs => url_f('jobs', search(req_id => $rid)),
        href_snippet_jobs => $si->{problem_snippets} && url_f('jobs', search(
            problem_id => $si->{problem_id},
            account_id => $si->{account_id},
            contest_id => $si->{contest_id},
            type => $cats::job_type_generate_snippets,
        )),
        logs => get_log_dump({ req_id => $rid, parent_id => undef }),
        job_enums => $CATS::Globals::jobs,
    );
}

sub get_last_verdicts_api {
    my ($p) = @_;
    $uid && @{$p->{problem_ids}} or return $p->print_json({});
    my $cp_sth //= $dbh->prepare(q~
        SELECT CP.problem_id, CP.contest_id, CP.status, CA.is_jury FROM contest_problems CP
        LEFT JOIN contest_accounts CA ON CP.contest_id = CA.contest_id
        WHERE CP.id = ? AND CA.account_id = ?~);
    my $state_sth = $dbh->prepare(qq~
        SELECT R.state, R.failed_test, R.id FROM reqs R
        WHERE R.contest_id = ? AND R.account_id = ? AND R.problem_id = ?
        ORDER BY R.submit_time DESC $CATS::DB::db->{LIMIT} 1~);
    my $result = { can_submit => CATS::Problem::Submit::can_submit };
    for (@{$p->{problem_ids}}) {
        $cp_sth->execute($_, $uid);
        my ($problem_id, $contest_id, $problem_status, $is_jury_in_contest) = $cp_sth->fetchrow_array or next;
        $cp_sth->finish;
        $state_sth->execute($contest_id, $uid, $problem_id);
        my ($state, $failed_test, $rid) = $state_sth->fetchrow_array;
        $state_sth->finish;
        $result->{$_} = {
            verdict => defined $state && CATS::Verdicts::hide_verdict_self(
                $is_jury_in_contest, $CATS::Verdicts::state_to_name->{$state}),
            failed_test => $failed_test,
            href_run_details => $rid && url_f('run_details', rid => $rid),
            href_problem_details => ($is_jury_in_contest ?
                url_f_cid('problem_details', cid => $contest_id, pid => $problem_id) : ''),
            allowed => $is_jury ||
                $problem_status < $cats::problem_st_disabled && ($state // 0) != $cats::st_banned,
        };
    }
    $p->print_json($result);
}

sub get_sources_info_api {
    my ($p) = @_;
    $uid or return;
    my $rid = $is_jury && $p->{rid} ? $p->{rid} :
        $dbh->selectrow_array(qq~
            SELECT id FROM reqs
            WHERE problem_id = ? AND account_id = ? AND contest_id = ?
            ORDER BY submit_time DESC~, { Slice => {} },
            $p->{problem_id}, $is_jury && $p->{uid} ? $p->{uid} : $uid, $cid);
    $rid or return;
    my $sources_info = get_sources_info($p, request_id => $rid, get_source => 1, encode_source => 1);
    $p->print_json(CATS::ReqDetails::prepare_sources($p, $sources_info));
}

sub _get_request_state {
    my ($p) = @_;
    $uid && @{$p->{req_ids}} or return ();
    my $result = $dbh->selectall_arrayref(_u $sql->select(
        'reqs', 'id, state, failed_test, account_id, contest_id',
        { id => $p->{req_ids} }));
    my %contest_ids;
    for (@$result) {
        $_->{is_jury} = $is_root || $_->{contest_id} == $cid && $is_jury;
        if ($_->{account_id} == $uid || $_->{is_jury}) {
            $_->{ok} = 1;
        }
        else {
            $contest_ids{$_->{id}} = 1;
        }
    }
    my ($stmt, @bind) = $sql->select(
        'contest_accounts', 'contest_id, is_jury',
        { contest_id => [ keys %contest_ids ], account_id => $uid });
    my $jury_in_contest = $dbh->selectall_hashref($stmt, 'contest_id', undef, @bind);
    for (@$result) {
        $_->{is_jury} ||= $jury_in_contest->{$_->{contest_id}}->{is_jury};
        $_->{verdict} = CATS::Verdicts::hide_verdict_self(
            $_->{is_jury}, $CATS::Verdicts::state_to_name->{$_->{state}});
    }
    grep $_->{ok} || $_->{is_jury}, @$result;
}

sub get_request_state_api {
    my ($p) = @_;
    $p->print_json([ map {
        id => $_->{id},
        verdict => $_->{verdict},
        failed_test => $_->{failed_test},
        np => $_->{state} < $cats::request_processed,
    }, _get_request_state($p) ]);
}

1;
