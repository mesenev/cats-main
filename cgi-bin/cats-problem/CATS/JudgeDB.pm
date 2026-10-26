package CATS::JudgeDB;

use strict;
use warnings;

use Data::Dumper;
use DBD::Pg qw(:pg_types);

use CATS::DeBitmaps;
use CATS::Config;
use CATS::Constants;
use CATS::DB qw(:DEFAULT $db);
use CATS::DevEnv;
use CATS::Job;

sub get_judge_id {
    my ($sid) = @_;
    $dbh->selectrow_array(q~
        SELECT J.id FROM judges J LEFT JOIN accounts A
        ON A.id = J.account_id WHERE A.sid = ?~, undef,
        $sid // '');
}

# { id, active_only, fields }
sub get_DEs {
    my ($p) = @_;
    my $condition = join ' AND ', ($p->{active_only} ? ('in_contests = 1') : ()), ($p->{id} ? ('id = ?') : ());
    my $extra_fields = !$p->{fields} ? '' : join '', map ", $_", ref $p->{fields} ? @{$p->{fields}} : $p->{fields};
    $condition = 'WHERE ' . $condition if $condition;
    {
        des => $dbh->selectall_arrayref(qq~
            SELECT id, code, description, file_ext, default_file_ext, memory_handicap$extra_fields
            FROM default_de
            $condition ORDER BY code~, { Slice => {} },
            $p->{id} ? ($p->{id}) : ()),
        version => current_de_version()
    }
}

sub get_problem {
    my ($pid) = @_;

    my $limits_str = join ', ', @cats::limits_fields;

    my $problem = $dbh->selectrow_hashref(qq~
        SELECT
            id, title, upload_date, $limits_str,
            input_file, output_file, std_checker, contest_id, formal_input,
            run_method, players_count, save_output_prefix, save_input_prefix, save_answer_prefix
        FROM problems WHERE id = ?~, { Slice => {}, ib_timestampformat => '%d-%m-%Y %H:%M:%S' }, $pid);
    $problem->{run_method} //= $cats::rm_default;
    $problem;
}

sub get_problem_sources {
    my ($pid) = @_;

    my $fields = join ', ', map "PSL.$_", qw(
        stype
        de_id
        src
        fname
        name
        input_file
        output_file
        guid
        time_limit
        memory_limit
        write_limit
        main
    );
    my $problem_sources = $dbh->selectall_arrayref(qq~
        SELECT PS.id, $fields, D.code FROM problem_sources PS
            INNER JOIN problem_sources_local PSL ON PSL.id = PS.id
            INNER JOIN default_de D ON D.id = PSL.de_id
        WHERE PS.problem_id = ? ORDER BY PS.id~, { Slice => {} },
        $pid);

    my $imported = $dbh->selectall_arrayref(qq~
        SELECT PS.id, $fields, D.code FROM problem_sources PS
            INNER JOIN problem_sources_imported PSI ON PSI.id = PS.id
            LEFT JOIN problem_sources_local PSL ON PSL.guid = PSI.guid
            LEFT JOIN default_de D ON D.id = PSL.de_id
        WHERE PS.problem_id = ? ORDER BY PS.id~, { Slice => {} },
        $pid);

    $_->{is_imported} = 1 for @$imported;

    [ @$problem_sources, @$imported ];
}

sub get_problem_snippets {
    my ($pid) = @_;

    $dbh->selectall_arrayref(q~
        SELECT generator_id, snippet_name AS name
        FROM problem_snippets WHERE problem_id = ?~, { Slice => {} },
        $pid);
}

sub get_problem_tags {
    my ($problem_id, $contest_id, $account_id) = @_;

    join ',', grep defined $_, @{$dbh->selectcol_arrayref(q~
        SELECT tags FROM contest_problems CP WHERE CP.problem_id = ? AND CP.contest_id = ?
        UNION
        SELECT CS.problem_tag
        FROM contest_accounts CA
        INNER JOIN contest_sites CS ON CA.contest_id = CS.contest_id AND CS.site_id = CA.site_id
        WHERE CA.account_id = ? AND CA.contest_id = ?
        ~, undef,
        $problem_id, $contest_id,
        $account_id, $contest_id)};
}

sub get_snippet_text {
    my ($problem_id, $contest_id, $account_id, $names) = @_;

    my $sth = $dbh->prepare(q~
        SELECT text FROM snippets
        WHERE problem_id = ? AND contest_id = ? AND account_id = ? AND name = ?~);
    [ map {
        $sth->execute($problem_id, $contest_id, $account_id, $_);
        my $t = $sth->fetchrow_array;
        $sth->finish;
        $t;
    } @$names ];
}

sub get_problem_tests {
    my ($pid) = @_;

    $dbh->selectall_arrayref(q~
        SELECT
            generator_id, input_validator_id, input_validator_param,
            rank, param, std_solution_id, in_file_hash,
            CASE WHEN in_file_size  IS NULL THEN in_file  ELSE NULL END AS in_file,
            CASE WHEN out_file_size IS NULL THEN out_file ELSE NULL END AS out_file,
            in_file_size,
            out_file_size,
            gen_group,
            snippet_name
        FROM tests WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
        $pid);
}

sub is_problem_uptodate {
    my ($pid, $date) = @_;

    scalar $dbh->selectrow_array(q~
        SELECT 1 FROM problems
        WHERE id = ? AND upload_date - 1.0000000000 / 24 / 60 / 60 <= ?~, undef,
        $pid, $date);
}

sub save_logs {
    my ($job_id, $dump) = @_;

    my $sth = $dbh->prepare(q~
        INSERT INTO logs (id, dump, job_id) VALUES (?, ?, ?)~);
    $sth->bind_param(1, new_id);
    $sth->bind_param(2, $dump, { pg_type => DBD::Pg::PG_BYTEA });
    $sth->bind_param(3, $job_id);
    $sth->execute;

    $dbh->commit;
}

sub copy_req_tree_info {
    my ($req_tree, @reqs) = @_;
    for my $req (@reqs) {
        $req_tree->{$req->{id}}->{$_} = $req->{$_} for keys %$req;
    }
}

sub add_info_to_req_tree {
    my ($needed_info, $req_ids, $req_tree) = @_;

    $needed_info //= {};
    $req_tree //= {};

    my $needed_fields = join ', ', qw(R.id R.elements_count), @{$needed_info->{fields} // []};
    my $needed_tables = join ' ', @{$needed_info->{tables} // []};
    my $req_ids_list = join ', ', $req_ids ? @$req_ids : keys %$req_tree or return {};

    #warn "add_info_to_req_tree. $req_ids_list";

    my $reqs = $dbh->selectall_arrayref(qq~
        SELECT $needed_fields
        FROM reqs R
            $needed_tables
        WHERE R.id IN ($req_ids_list)~, { Slice => {} });

    copy_req_tree_info($req_tree, @$reqs);

    $req_tree;
}

sub get_req_tree {
    my ($req_ids, $p, $req_tree) = @_;

    $req_ids && @$req_ids or return {};
    $req_tree //= {};

    #warn 'get_req_tree. given ids: ', join ', ', @$req_ids;

    add_info_to_req_tree($p, $req_ids, $req_tree);

    my @reqs_to_next_level = grep {
        $_->{elements_count} &&
        (!$p->{on_level_filter} || $p->{on_level_filter}->($_))
    } map $req_tree->{$_}, @$req_ids;

    #warn 'get_req_tree. filtered to next level: ', join ', ', map $_->{id}, @reqs_to_next_level;

    @reqs_to_next_level or return $req_tree;

    my $req_ids_to_next_level_list = join ', ', map $_->{id}, @reqs_to_next_level;
    my $req_elements = $dbh->selectall_arrayref(qq~
        SELECT RG.group_id, RG.element_id
        FROM req_groups RG
        WHERE RG.group_id IN ($req_ids_to_next_level_list)~, { Slice => {} });

    for my $req_element (@$req_elements) {
        #warn "get_req_tree. link: $req_element->{group_id}->$req_element->{element_id}";
        $req_tree->{$req_element->{element_id}} //= {};
        #push @{$req_tree->{$req_element->{element_id}}->{parents} //= []}, $req_tree->{$req_element->{group_id}};
        push @{$req_tree->{$req_element->{group_id}}->{elements} //= []}, $req_tree->{$req_element->{element_id}};
    }

    for my $req (@reqs_to_next_level) {
        if (@{$req_tree->{$req->{id}}->{elements} //= []} != $req->{elements_count}) {
            die "elements_count mismatch on request: $req->{id}";
        }
    }

    my @unvisited_ids = grep !defined $req_tree->{$_}->{id}, map $_->{element_id}, @$req_elements;
    return @unvisited_ids ? get_req_tree(\@unvisited_ids, $p, $req_tree) : $req_tree;
}

sub ensure_request_de_bitmap_cache {
    my ($req_ids, $dev_env, $select_all) = @_;

    $req_ids or return {};

    if (!ref($req_ids)) {
        $req_ids = [ $req_ids ];
    } elsif (ref($req_ids) ne 'ARRAY') {
        die 'req_ids is not neither reference to ARRAY or scalar';
    }

    #warn "ensure_request_de_bitmap_cache. enter with req_ids: ", join ', ', @$req_ids;

    @$req_ids or return {};

    $dev_env //= CATS::DevEnv->new(get_DEs);

    my $req_tree = get_req_tree($req_ids, {
        fields => [
            'S.de_id',
            'RDEBC.version AS de_version',
            CATS::DeBitmaps::de_bitmap_str('RDEBC'),
        ],
        tables => [
            'LEFT JOIN req_de_bitmap_cache RDEBC ON RDEBC.req_id = R.id',
            'LEFT JOIN sources S ON S.req_id = R.id',
        ],
        on_level_filter => $select_all ? undef : sub {
            !$dev_env->is_good_version($_[0]->{de_version});
        },
    });

    my @needed_update_reqs;
    my $collect_needed_update_req_ids;
    $collect_needed_update_req_ids = sub {
        my $req = shift;

        my @bitmap;

        if (!$dev_env->is_good_version($req->{de_version})) {
            if ($req->{elements_count} > 0) {
                #warn "ensure_request_de_bitmap_cache. req $req->{id} needs update recursively";
                @bitmap = (0) x $cats::de_req_bitfields_count;
                for my $req_element (@{$req->{elements}}) {
                    my @element_bitmap = $collect_needed_update_req_ids->($req_element);
                    CATS::DevEnv::merge_bitmaps(\@bitmap, \@element_bitmap);
                }
            }
            else {
                #warn "ensure_request_de_bitmap_cache. req $req->{id} needs update";
                @bitmap = $dev_env->bitmap_by_ids($req->{de_id});
            }
            my %de_bitfields_hash = CATS::DeBitmaps::get_de_bitfields_hash(@bitmap);
            $req->{$_} = $de_bitfields_hash{$_} for keys %de_bitfields_hash;
            push @needed_update_reqs, $req;
        }
        else {
            #warn "ensure_request_de_bitmap_cache. req $req->{id} is up to date";
            @bitmap = CATS::DeBitmaps::extract_de_bitmap($req);
        }

        $req->{bitmap} = [ @bitmap ];
        $req->{de_version} = $dev_env->version;
        my %bitfields_hash = CATS::DeBitmaps::get_de_bitfields_hash(@bitmap);
        $req->{$_} = $bitfields_hash{$_} for keys %bitfields_hash;
        @bitmap;
    };

    $collect_needed_update_req_ids->($_) for values %$req_tree;

    @needed_update_reqs or return $req_tree;

    my $update_req_ids_list = join ', ', map $_->{id}, @needed_update_reqs;
    $dbh->do(qq~
        DELETE FROM req_de_bitmap_cache RDEBC
        WHERE RDEBC.req_id IN ($update_req_ids_list)~);

    my $set_bitmap_cache_str = join ', ', map "de_bits$_", 1..$cats::de_req_bitfields_count;
    my $q_str = join ', ', map '?', 1..$cats::de_req_bitfields_count;
    my $c = $dbh->prepare(qq~
        INSERT INTO req_de_bitmap_cache (req_id, version, $set_bitmap_cache_str) VALUES (?, ?, $q_str)~);

    $c->execute($_->{id}, $dev_env->version, @{$_->{bitmap}}) for @needed_update_reqs;

    if ($dev_env->is_good_version(current_de_version())) {
        $dbh->commit;
        #warn 'ensure_request_de_bitmap_cache. updated reqs: ', join ', ', map $_->{id}, @needed_update_reqs;
    }
    else {
        $dbh->rollback;
        warn 'ensure_request_de_bitmap_cache. concurrent de change detected. trying again';
        goto &ensure_request_de_bitmap_cache;
    }

    $req_tree;
}

sub current_de_version {
    $db->current_sequence_value('de_bitmap_cache_seq');
}

sub ensure_problem_de_bitmap_cache {
    my ($problem_id, $dev_env) = @_ or return;

    $dev_env //= CATS::DevEnv->new(get_DEs);

    my ($problem_de_version) = $dbh->selectrow_array(q~
        SELECT PDEBC.version
        FROM problems P
            LEFT JOIN problem_de_bitmap_cache PDEBC ON PDEBC.problem_id = P.id
        WHERE P.id = ?~, { Slice => {} },
        $problem_id);

    return if $problem_de_version && $dev_env->version == $problem_de_version;

    my $de_ids = $dbh->selectcol_arrayref(q~
        SELECT COALESCE(psl.de_id, psle.de_id) FROM problem_sources ps
        LEFT JOIN problem_sources_local psl ON psl.id = ps.id
        LEFT JOIN problem_sources_imported psi ON psi.id = ps.id
        LEFT JOIN problem_sources_local psle ON psle.guid = psi.guid
        WHERE ps.problem_id = ?~, undef,
        $problem_id);

    warn $problem_de_version
        ? 'ensure_problem_de_bitmap_cache. update existing debc'
        : 'ensure_problem_de_bitmap_cache. create new problem debc';

    my @de_bitmap = $dev_env->bitmap_by_ids(@$de_ids);
    my $update_debc_str = join ', ', map "de_bits$_ = ?", 1..$cats::de_req_bitfields_count;
    my $insert_debc_str = join ', ', map "de_bits$_", 1..$cats::de_req_bitfields_count;
    my $q_str = join ', ', map '?', 1..$cats::de_req_bitfields_count;
    my $sql = !defined $problem_de_version
    ? qq~
        INSERT INTO problem_de_bitmap_cache (
            version, $insert_debc_str, problem_id
        ) VALUES (
            ?, $q_str, ?
        )~
    : qq~
        UPDATE problem_de_bitmap_cache
            SET version = ?, $update_debc_str
        WHERE problem_id = ?~;
    $dbh->do($sql, undef, $dev_env->version, @de_bitmap, $problem_id);

    $dbh->commit;

    warn 'new problem de bits: ', join ', ', @de_bitmap;

    return \@de_bitmap;
}

sub invalidate_de_bitmap_cache {
    $dbh->do(q~
        DELETE FROM req_de_bitmap_cache~);
    $dbh->do(q~
        DELETE FROM problem_de_bitmap_cache~);
    $db->next_sequence_value('de_bitmap_cache_seq');
    $dbh->commit;
}

sub _has_state_params {
    my ($p, $state, @params) = @_;
    $p->{state} == $state && 0 == grep !defined $p->{$_}, @params;
}

# job_id, req_id, problem_id, contest_id, account_id, state, failed_test
sub set_request_state {
    my ($p) = @_;

    $p->{req_id} or return;
    CATS::Job::is_canceled($p->{job_id}) and return;

    if (_has_state_params($p, $cats::st_awaiting_verification, qw(account_id problem_id contest_id))) {
        # Latest AW supercedes previous ones.
        $dbh->do(q~
            UPDATE reqs R SET state = ?
            WHERE
                R.account_id = ? AND R.contest_id = ? AND R.problem_id = ? AND
                R.state = ?~, undef,
            $cats::st_ignore_submit,
            $p->{account_id}, $p->{contest_id}, $p->{problem_id},
            $cats::st_awaiting_verification);
    }
    $dbh->do(q~
        UPDATE reqs SET state = ?, failed_test = ?, result_time = CURRENT_TIMESTAMP
        WHERE id = ?~, undef,
        $p->{state}, $p->{failed_test}, $p->{req_id});

    # Suspend further problem testing on unhandled error.
    if (_has_state_params($p, $cats::st_unhandled_error, qw(problem_id contest_id))) {
        $dbh->do(q~
            UPDATE contest_problems SET status = ?
            WHERE problem_id = ? AND contest_id = ? AND status < ?~, undef,
            $cats::problem_st_suspended, $p->{problem_id}, $p->{contest_id}, $cats::problem_st_suspended);
    }

    # Clear cache to save space after testing.
    $dbh->do(q~
        DELETE FROM req_de_bitmap_cache WHERE req_id = ?~, undef,
        $p->{req_id});
    $dbh->commit;
}

sub is_set_req_state_allowed {
    my ($job_id, $force) = @_;

    my $parent_id = $dbh->selectrow_array(qq~
        SELECT J.parent_id FROM jobs J
        WHERE J.id = ? AND EXISTS (
            SELECT 1 FROM jobs J1 WHERE J1.id = J.parent_id
            AND J1.state = $cats::job_st_in_progress
        )~, undef,
        $job_id) or return (undef, undef);

    my $jobs_count = $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM jobs
        WHERE parent_id = $parent_id AND
            parent_id IS NOT NULL AND
            (state = $cats::job_st_waiting OR state = $cats::job_st_in_progress)~);

    my $allow_set_req_state = 0;
    if ($jobs_count == 0 || $force) {
        eval {
            $allow_set_req_state = 1;
            $dbh->do(qq~
                UPDATE jobs SET state = $cats::job_st_waiting_for_verdict
                WHERE id = ? AND state = $cats::job_st_in_progress~, undef,
                $parent_id);
            $dbh->commit;
            1;
        } or return $db->catch_deadlock_error('is_set_req_state_allowed');
    }
    return ($parent_id, $allow_set_req_state);
}

sub update_judge_de_bitmap {
    my ($p, $dev_env) = @_;
    my $jid = { judge_id => $p->{jid} };
    my $jbmp = {
        version => $dev_env->version,
        map { +"de_bits$_" => $p->{"de_bits$_"} } 1..$cats::de_req_bitfields_count
    };
    my $cache = CATS::DB::select_row('judge_de_bitmap_cache', '*', $jid);
    if (!$cache) {
        $dbh->do(_u $sql->insert('judge_de_bitmap_cache', { %$jid, %$jbmp }));
    }
    elsif (grep +($cache->{$_} // '') ne ($jbmp->{$_} // ''), keys %$jbmp) {
        $dbh->do(_u $sql->update('judge_de_bitmap_cache', $jbmp, $jid));
        #warn Dumper($jbmp);
    }
}

sub dev_envs_condition {
    my ($p, $de_version, $table) = @_;
    # If DE cache is absent or obsolete, select request and try to refresh the cache.
    # Otherwise, select only if the judge supports all DEs indicated by the cached bitmap.
    my $des_cond_fmt = sub {
        my ($table) = @_;
        my $cond =
            join ' AND ', map "BIN_AND($table.de_bits$_, CAST(? AS BIGINT)) = $table.de_bits$_",
                1..$cats::de_req_bitfields_count;
        qq~
        (CASE
            WHEN $table.version IS NULL THEN 1
            WHEN $table.version = ? THEN (CASE WHEN $cond THEN 1 ELSE 0 END)
            ELSE 1
        END) = 1~;
    };
    my $des_condition = $des_cond_fmt->($table);
    my @r = ($des_condition, map $_ // '', ($de_version, CATS::DeBitmaps::extract_de_bitmap($p)));
    #warn join ' | ', @r;
    @r;
}

sub can_split {
    my $queue_size = $dbh->selectrow_array(q~
        SELECT COUNT(*) FROM jobs_queue~
    );
    $queue_size < $CATS::Config::split->{queue_size_limit};
}

sub take_job {
    my ($judge_id, $job_id) = @_;

    my $result;
    eval {
        $result = ($dbh->do(q~
            DELETE FROM jobs_queue WHERE id = ?~, undef,
            $job_id) // 0) > 0 or return 1;

        $result &&= ($dbh->do(qq~
            UPDATE jobs SET state = ?, judge_id = ?, start_time = CURRENT_TIMESTAMP
            WHERE id = ? AND state = $cats::job_st_waiting~, undef,
            $cats::job_st_in_progress, $judge_id, $job_id) // 0) > 0;

        $dbh->commit;
        1;
    # Another judge has probably acquired this problem concurrently.
    } or return $db->catch_deadlock_error('select_request');
    $result;
}

sub select_request {
    my ($p) = @_;

    my $dev_env = CATS::DevEnv->new(get_DEs);
    $dbh->do(q~
        UPDATE judges SET is_alive = 1, alive_date = CURRENT_TIMESTAMP WHERE id = ?~, undef,
        $p->{jid}) if $p->{was_pinged} || $p->{time_since_alive} > $CATS::Config::judge_alive_interval / 24;
    update_judge_de_bitmap($p, $dev_env);
    $dbh->commit;
    $dbh->selectrow_array(qq~
        SELECT 1 FROM jobs_queue $db->{LIMIT} 1~, undef) or return;

    return if $p->{pin_mode} == $cats::judge_pin_locked;

    return { error => $cats::es_old_de_version } if !$dev_env->is_good_version($p->{de_version});

    my ($req_des_condition, @req_params) = dev_envs_condition($p, $dev_env->version, 'RDEBC');
    my ($problem_des_condition, @problem_params) = dev_envs_condition($p, $dev_env->version, 'PDEBC');
    my @params = (@req_params, @problem_params);

    my $pin_condition = '';

    if ($p->{pin_mode} == $cats::judge_pin_contest) {
        $pin_condition =
            'EXISTS (
                SELECT 1
                FROM contest_accounts CA
                INNER JOIN judges J ON CA.account_id = J.account_id
                WHERE common.contest_id = CA.contest_id AND J.id = ?
            ) AND common.judge_id IS NULL';
        push @params, $p->{jid};
    }
    elsif ($p->{pin_mode} == $cats::judge_pin_any) {
        $pin_condition = 'common.judge_id IS NULL AND COALESCE(C.pinned_judges_only, 0) = 0';
    }

    if ($pin_condition) {
        # A problem may restrict its submissions to some judges (problem_judges, none means any).
        # A submission pinned to a judge explicitly (common.judge_id) ignores the restriction.
        $pin_condition = qq~($pin_condition AND (
            common.type NOT IN ($cats::job_type_submission, $cats::job_type_submission_part) OR
            NOT EXISTS (SELECT 1 FROM problem_judges PJ WHERE PJ.problem_id = common.problem_id) OR
            EXISTS (SELECT 1 FROM problem_judges PJ WHERE PJ.problem_id = common.problem_id AND PJ.judge_id = ?)
        )) OR~;
        push @params, $p->{jid};
    }

    push @params, $p->{jid};

    # Left joins with contest_problems in case the problem was removed from contest after submission.
    my $sel_req = $dbh->selectrow_hashref(qq~
        SELECT common.*, PDEBC.version AS problem_de_version FROM (
            SELECT
                JQ.id AS job_id,
                J.type,
                J.state AS job_state,
                CASE WHEN J.type = $cats::job_type_submission THEN R.judge_id
                ELSE J.judge_id END AS judge_id,
                R.id,
                R.problem_id,
                R.account_id,
                R.contest_id,
                R.elements_count,
                R.state AS req_state,
                RDEBC.version AS request_de_version
            FROM jobs_queue JQ
                INNER JOIN jobs J on J.id = JQ.id
                INNER JOIN reqs R on J.req_id = R.id
                INNER JOIN contest_accounts CA ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id
                LEFT JOIN contest_problems CP ON CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id
                INNER JOIN problems P ON P.id = R.problem_id
                LEFT JOIN req_de_bitmap_cache RDEBC ON RDEBC.req_id = R.id
            WHERE
                (J.type = $cats::job_type_submission OR
                J.type = $cats::job_type_submission_part) AND
                (CP.status <= $cats::problem_st_compile OR CA.is_jury = 1) AND
                $req_des_condition
        UNION
            SELECT
                JQ.id AS job_id,
                J.type,
                J.state AS job_state,
                J.judge_id,
                NULL AS id,
                J.problem_id,
                J.account_id,
                J.contest_id,
                NULL AS elements_count,
                NULL AS req_state,
                NULL AS request_de_version
            FROM jobs_queue JQ
                INNER JOIN jobs J on J.id = JQ.id
            WHERE
                J.type IN (
                    $cats::job_type_generate_snippets,
                    $cats::job_type_initialize_problem,
                    $cats::job_type_update_self,
                    $cats::job_type_run_command)
        ) common
        LEFT JOIN problem_de_bitmap_cache PDEBC ON PDEBC.problem_id = common.problem_id
        LEFT JOIN contests C ON C.id = common.contest_id

        WHERE
            common.job_state = $cats::job_st_waiting AND
            $problem_des_condition AND
            ($pin_condition common.judge_id = ?)
        ORDER BY CASE common.type
            WHEN $cats::job_type_update_self THEN 1
            WHEN $cats::job_type_generate_snippets THEN 2
            WHEN $cats::job_type_initialize_problem THEN 3
            WHEN $cats::job_type_submission_part THEN 4
            WHEN $cats::job_type_submission THEN 5
            ELSE 6
        END
        $db->{LIMIT} 1~, undef,
        @params) or return;

    if (grep $sel_req->{type} == $_,
        $cats::job_type_generate_snippets,
        $cats::job_type_initialize_problem,
        $cats::job_type_update_self,
        $cats::job_type_run_command,
    ) {
        $sel_req->{job_src} = $dbh->selectrow_array(q~
            SELECT COALESCE(JS.src, JS1.src) FROM jobs J
            LEFT JOIN job_sources JS ON JS.job_id = J.id
            LEFT JOIN job_sources JS1 ON JS1.job_id = J.parent_id
            WHERE J.id = ?~, undef,
            $sel_req->{job_id}) if $sel_req->{type} == $cats::job_type_run_command;
        take_job($p->{jid}, $sel_req->{job_id}) or return;
        return $sel_req;
    }
    if (!$dev_env->is_good_version($sel_req->{problem_de_version})) {
        # Our cache is behind judge's -- postpone until next API call.
        return if $sel_req->{problem_de_version} && $sel_req->{problem_de_version} > $dev_env->version;
        #warn "update problem de cache: $sel_req->{id}";
        my $updated_de = ensure_problem_de_bitmap_cache($sel_req->{problem_id}, $dev_env, 1);
        if (!CATS::DevEnv::check_supported($updated_de, [ CATS::DeBitmaps::extract_de_bitmap($p) ])) {
            warn "can't check this problem";
            return;
        }
    }

    my $req_tree;

    if (!$dev_env->is_good_version($sel_req->{request_de_version})) {
        # Our cache is behind judge's -- postpone until next API call.
        return if $sel_req->{request_de_version} && $sel_req->{request_de_version} > $dev_env->version;
        #warn "update request de cache: $sel_req->{id}";
        $req_tree = ensure_request_de_bitmap_cache($sel_req->{id}, $dev_env);
        my $updated_de = $req_tree->{$sel_req->{id}}->{bitmap};
        if (!CATS::DevEnv::check_supported($updated_de, [ CATS::DeBitmaps::extract_de_bitmap($p) ])) {
            warn "can't check this request";
            return;
        }
    }
    else {
        $req_tree = $sel_req->{elements_count} ?
            get_req_tree([ $sel_req->{id} ]) :
            { $sel_req->{id} => $sel_req };
    }

    add_info_to_req_tree({
        fields => [
            qw(R.id R.problem_id R.account_id R.contest_id R.state CA.is_jury C.run_all_tests
            CP.status S.fname S.src S.de_id), 'CP.id AS cpid',
            map "CPL.$_ AS cp_$_, RL.$_ AS req_$_", @cats::limits_fields, 'job_split_strategy'
        ],
        tables => [
            'INNER JOIN contest_accounts CA ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id',
            'INNER JOIN contests C ON C.id = R.contest_id',
            'LEFT JOIN sources S ON S.req_id = R.id',
            'LEFT JOIN default_de D ON D.id = S.de_id',
            'LEFT JOIN contest_problems CP ON CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id',
            'LEFT JOIN limits CPL ON CPL.id = CP.limits_id',
            'LEFT JOIN limits RL ON RL.id = R.limits_id',
        ],
    }, undef, $req_tree);

    my @testing_req_ids = ($sel_req->{id});

    my $check_req;
    $check_req = sub {
        my ($req, $level) = @_;
        $level //= 0;

        if ($level > 2) {
            warn 'request group is too deep';
            return 0;
        }

        if ($req->{elements_count} == 1) {
            my $element_req = $req->{elements}->[0];
            $check_req->($element_req, $level + 1) or return 0;
            $req->{$_} = $element_req->{$_} for qw(problem_id fname src de_id);
        } elsif ($req->{elements_count} > 1) {
            if ($level != 0) {
                warn 'group has too many elements ot its level';
                return 0;
            }
            my $different_problem_ids =
                scalar grep $_->{problem_id} != $req_tree->{$sel_req->{id}}->{problem_id}, @{$req->{elements}};
            my $different_contests_ids =
                scalar grep $_->{contest_id} != $req_tree->{$sel_req->{id}}->{contest_id}, @{$req->{elements}};
            if ($different_problem_ids || $different_contests_ids) {
                warn 'group request and elements requests must be for the same problem and contest';
                return 0;
            }
            $check_req->($_, $level + 1) or return 0 for @{$req->{elements}};
        }

        push @testing_req_ids, $req->{id} if $sel_req->{elements_count} > 1 && $level == 1;

        return 1;
    };

    # Copypasted this code here, because one day it should become more complicated.
    $sel_req->{judges_alive} = $dbh->selectrow_array(qq~
        SELECT
            SUM(CASE WHEN CAST(CURRENT_TIMESTAMP - J.alive_date AS DOUBLE PRECISION) < ? THEN 1 ELSE 0 END),
            COUNT(*)
        FROM judges J WHERE J.pin_mode > ?~, undef,
        3 * $CATS::Config::judge_alive_interval / 24, $CATS::Config::judge_alive_interval);

    my $set_state = sub {
        take_job($p->{jid}, $sel_req->{job_id}) or return;
        if ($sel_req->{type} == $cats::job_type_submission) {
            eval {
                my $c = $dbh->prepare(q~
                    UPDATE reqs SET state = ?, judge_id = ?, test_time = CURRENT_TIMESTAMP WHERE id = ?~);
                $c->execute_array(undef, $_[0], $p->{jid}, \@testing_req_ids);
                1;
            } or return $db->catch_deadlock_error('select_request');
        }
        1;
    };

    if (!$check_req->($req_tree->{$sel_req->{id}})) {
        $set_state->($cats::st_unhandled_error);
        return;
    }
    else {
        $set_state->($cats::st_install_processing) or return;
    }

    $req_tree->{$sel_req->{id}}->{job_id} = $sel_req->{job_id};
    $req_tree->{$sel_req->{id}}->{type} = $sel_req->{type};
    $req_tree->{$sel_req->{id}};
}

sub delete_req_details {
    my ($req_id, $judge_id, $job_id) = @_;

    CATS::Job::is_canceled($job_id) and return;

    $dbh->do(q~
        DELETE FROM req_details WHERE req_id = ?~, undef,
        $req_id);
    $dbh->commit;
    1;
}

sub get_tests_req_details {
    my ($req_id) = @_;

    $dbh->selectall_arrayref(q~
        SELECT test_rank, result FROM req_details
        WHERE req_id = ? ORDER BY test_rank~, { Slice => {} },
        $req_id);
}

# output output_size judge_id
# req_id test_rank result time_used memory_used disk_used checker_comment points
sub insert_req_details {
    my ($job_id, %p) = @_;

    CATS::Job::is_canceled($job_id) and return;

    my ($output, $output_size) = map $p{$_}, qw(output output_size);

    my $rd = { map { $_ => $p{$_} } qw(
        req_id test_rank result time_used memory_used disk_used checker_comment points) };

    eval { $dbh->do(_u $sql->insert(req_details => $rd)); };
    if (my $err = $@) {
        # Maybe retry from judge after crash.
        $err =~ /23505|duplicate key.*req_details/i or die $err;
        warn 'Duplicate req_details';
        # Postgres aborts the whole transaction on error; clear it before returning.
        $dbh->rollback;
        return 1;
    }

    if ($output_size) {
        my $sth = $dbh->prepare(q~
            INSERT INTO solution_output (req_id, test_rank, output, output_size, create_time)
            VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)~);
        $sth->bind_param(1, $p{req_id});
        $sth->bind_param(2, $p{test_rank});
        $sth->bind_param(3, $output, { pg_type => DBD::Pg::PG_BYTEA });
        $sth->bind_param(4, $output_size);
        $sth->execute;
    }

    $dbh->commit;
    1;
}

sub save_input_test_data {
    my ($problem_id, $test_rank, $input, $input_size, $hash) = @_;

    eval {
        if (defined $input) {
            $dbh->do(q~
                UPDATE tests SET in_file = ?, in_file_size = ?
                WHERE problem_id = ? AND rank = ? AND in_file IS NULL~, undef,
                $input, $input_size, $problem_id, $test_rank);
        }

        if (defined $hash) {
            $dbh->do(q~
                UPDATE tests SET in_file_hash = ?
                WHERE problem_id = ? AND rank = ? AND in_file_hash IS NULL~, undef, # OR in_file_hash = ?
                $hash, $problem_id, $test_rank#, $hash
            ); # or die "Invalid hash for test $test_rank";
        }

        $dbh->commit;
        1;
    } or $db->catch_deadlock_error('save_input_test_data');
}

sub save_answer_test_data {
    my ($problem_id, $test_rank, $answer, $answer_size) = @_;

    eval {
        $dbh->do(q~
            UPDATE tests SET out_file = ?, out_file_size = ?
            WHERE problem_id = ? AND rank = ? AND out_file IS NULL~, undef,
            $answer, $answer_size, $problem_id, $test_rank);

        $dbh->commit;
        1;
    } or $db->catch_deadlock_error('save_answer_test_data');
}

# snippets: { name => text }
sub save_problem_snippets {
    my ($problem_id, $contest_id, $account_id, $snippets) = @_;
    eval {
        my $sth = $dbh->prepare(q~
            UPDATE snippets SET text = ?
            WHERE problem_id = ? AND contest_id = ? AND
                account_id = ? AND name = ? AND text IS NULL~);
        for my $name (keys %$snippets) {
            $sth->execute($snippets->{$name}, $problem_id, $contest_id, $account_id, $name);
        }
        $dbh->commit;
        1;
    } or $db->catch_deadlock_error('save_problem_snippet');
}
1;
