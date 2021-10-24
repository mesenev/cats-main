package CATS::Router;

use strict;
use warnings;

use FindBin;
use File::Spec;

use CATS::ApiJudge;
use CATS::RouteParser;

BEGIN {
    require $_ for glob File::Spec->catfile($ENV{CATS_DIR} || $FindBin::Bin, 'CATS', 'UI', '*.pm');
}

my %console_params = (
    selection => clist_of integer, uf => clist_of integer, se => ident, page => integer,
    i_value => signed_integer, i_unit => ident,
    by_reference => bool, retest => bool, create_group => bool,
    show_contests => bool0, show_messages => bool0, show_results => bool0,
);

my %user_params = (
    (map { $_ => str } CATS::User::param_names, CATS::User::setting_names, qw(password1 password2)),
    set_password => bool,
);

my $main_routes = {
    login => [ \&CATS::UI::LoginLogout::login_frame,
        logout => bool, login => str, passwd => str, redir => str, cid => integer,
        token => str, salt => integer ],
    api_login_token => [ \&CATS::UI::LoginLogout::login_token_api,
        login => str, redir => str, cid => integer, apikey => str,
        team_id => str, token => str, # ONTI
    ],
    api_login_available => [ \&CATS::UI::LoginLogout::login_available_api, login => str, ],
    logout => \&CATS::UI::LoginLogout::logout_frame,
    registration => [ \&CATS::UI::UserDetails::registration_frame, %user_params, register => bool, ],
    profile => [ \&CATS::UI::UserDetails::profile_frame, %user_params,
        json => bool, clear => bool, edit_save => bool, ],
    contests => [ \&CATS::UI::Contests::contests_frame,
        summary_rank => bool, create_group => bool, delete => integer,
        online_registration => bool, virtual_registration => bool,
        edit_save => bool, new_save => bool, id => integer, original_id => integer,
        contests_selection => array_of integer,
        (map { $_ => bool } CATS::UI::Contests::contest_checkbox_params),
        (map { $_ => str } CATS::UI::Contests::contest_string_params),
        $CATS::UI::Contests::form->route,
        exclude_verdict_max_reqs => array_of ident,
        exclude_verdict_penalty => array_of ident,
        penalty => integer,
        ical => bool, filter => ident,
        set_tags => bool, tag_name => str,
        add_children => bool, remove_children => bool,
    ],
    api_find_contest_tags => [ \&CATS::UI::ContestTags::find_contest_tags_api, query => str, ],
    api_find_contests => [ \&CATS::UI::Contests::find_contests_api, query => str, ],
    contests_rss => [ \&CATS::UI::Contests::contests_rss_frame, ],
    contests_new => [ \&CATS::UI::Contests::contests_new_frame, ],
    contest_params => [ \&CATS::UI::Contests::contest_params_frame, id => integer, ],
    contest_xml => [ \&CATS::UI::Contests::contest_xml_frame, edit_save_xml => bool, contest_xml => str ],
    contest_caches => [ \&CATS::UI::ContestCaches::contest_caches_frame,
        clear_text_cache => bool, clear_rank_cache => bool ],
    contest_sites => [ \&CATS::UI::Sites::contest_sites_frame,
        add => bool, delete => integer, check => array_of integer, with_org => integer,
        multi_console => bool, multi_rank_table => bool, ],
    contest_sites_edit => [ \&CATS::UI::Sites::contest_sites_edit_frame,
        site_id => integer,
        diff_time => fixed, diff_units => ident,
        ext_time => fixed, ext_units => ident,
        save => bool, ],
    contest_problems_installed => [
        \&CATS::UI::Contests::contest_problems_installed_frame,
        install_missing => bool,
        install_selected => bool,
        selected_problems => array_of qr/^\d+_\d+$/,
    ],
    contest_wikis => [ \&CATS::UI::ContestWikis::contest_wikis_frame, delete => integer, ],
    contest_wikis_edit => [ \&CATS::UI::ContestWikis::contest_wikis_edit_frame,
        $CATS::UI::ContestWikis::form->route, ],
    contest_tags => [ \&CATS::UI::ContestTags::contest_tags_frame,
        delete => integer, saved => integer,
        add => bool, remove => bool, check => array_of integer,
    ],
    contest_tags_edit => [ \&CATS::UI::ContestTags::contest_tags_edit_frame,
        $CATS::UI::ContestTags::form->route, ],
    console_content => [ \&CATS::UI::Console::console_content_frame,
        %console_params,
    ],
    console => [ \&CATS::UI::Console::console_frame,
        delete_question => integer, delete_message => integer, send_question => bool, question_text => str,
        %console_params,
    ],
    console_export => \&CATS::UI::Console::export_frame,
    console_graphs => \&CATS::UI::Console::graphs_frame,

    acc_groups => [ \&CATS::UI::AccGroups::acc_groups_frame,
        delete => integer, saved => integer,
        add => bool, remove => bool, check => array_of integer,
    ],
    api_find_acc_groups => [ \&CATS::UI::AccGroups::find_acc_groups_api, query => str, ],
    acc_groups_edit => [ \&CATS::UI::AccGroups::acc_groups_edit_frame,
        $CATS::UI::AccGroups::form->route, ],
    acc_group_users => [ \&CATS::UI::AccGroups::acc_group_users_frame,
        group => integer, exclude_user => integer, user_selection => array_of integer,
        exclude_selected => bool,
        is_admin => bool, set_admin => bool,
        is_hidden => bool, set_hidden => bool,
    ],
    acc_group_add_users => [ \&CATS::UI::AccGroups::acc_group_add_users_frame,
        group => integer, logins_to_add => str, make_hidden => bool, by_login => bool,
        source_cid => integer, from_contest => bool, include_ooc => bool,
        source_group_id => integer, from_group => bool, include_admins => bool,
    ],

    problems => [
        \&CATS::UI::Problems::problems_frame,
        problem_id => integer,
        problems_selection => array_of integer,
        participate_online => bool, participate_virtual => bool, start_offset => bool,
        submit => bool, replace => bool, add_new => bool,
        add_remote => bool, std_solution => bool, delete_problem => integer,
        de_id => qr/\d+|by_extension/, ignore => bool,
        change_status => integer, status => integer,
        change_code => integer, code => problem_code,
        link_save => bool, move => bool,
        zip => upload, allow_rename => bool, add_zip => upload,
        remote_url => str, repo_path => qr/[A-Za-z0-9_\/]*/,
        submit_as => str,
        source => upload, source_text => str,
        new_title => str, new_lang => ident, add_new_template => bool,
        limits_cpid => integer,
    ],
    problems_all => [
        \&CATS::UI::Problems::problems_all_frame,
        link => bool, move => bool,
    ],
    problems_udebug => [ \&CATS::UI::ProblemsUdebug::problems_udebug_frame, ],
    problems_retest => [ \&CATS::UI::ProblemsRetest::problems_retest_frame,
        mass_retest => bool, recalc_points => bool, new_state => ident, all_runs => bool,
        problem_id => array_of integer, ignore_states => array_of ident,
    ],
    problem_select_testsets => [
        \&CATS::UI::ProblemDetails::problem_select_testsets_frame,
        pid => integer, save => bool, from_problems => bool,
        sel_testsets => array_of integer,
        sel_points_testsets => array_of integer,
        save_text => bool, testsets_text => str, points_testsets_text => str,
    ],
    problem_select_tags => [
        \&CATS::UI::ProblemDetails::problem_select_tags_frame,
        pid => integer, tags => str, save => bool, from_problems => bool, ],
    problem_des => [
        \&CATS::UI::ProblemDetails::problem_des_frame,
        pid => integer, allow => array_of integer, save => bool, ],
    problem_limits => [ \&CATS::UI::ProblemLimits::problem_limits_frame,
        pid => integer, cpid => integer, override => bool, clear_override => bool,
        override_contest => bool,
        $CATS::UI::ProblemLimits::form->route_fields,
        (map { $_ => str } @cats::limits_fields), job_split_strategy => str, from_problems => bool,
    ],
    problem_download => [ \&CATS::UI::ProblemDetails::problem_download, pid => integer, ],
    problem_git_package => [ \&CATS::UI::ProblemDetails::problem_git_package, pid => integer, sha => sha, ],
    problem_details => [ \&CATS::UI::ProblemDetails::problem_details_frame, pid => integer, ],
    problem_test_data => [
        \&CATS::UI::ProblemDetails::problem_test_data_frame,
        pid => integer, test_rank => integer, clear_test_data => bool, clear_input_hashes => bool, ],
    problem_link => [ \&CATS::UI::ProblemDetails::problem_link_frame,
        pid => integer, contest_id => integer,
        link_to => bool, move_to => bool, move_from => bool,
        code => problem_code,
    ],

    problem_history => [ \&CATS::UI::ProblemHistory::problem_history_frame,
        a => ident, pid => integer, pull => bool, replace => bool,
        message => str, is_amend => bool, allow_rename => bool, zip => upload, ],
    problem_history_edit => [ \&CATS::UI::ProblemHistory::problem_history_edit_frame,
        pid => required integer, hb => required sha, file => str,
        save => bool, src_enc => encoding, message => str, src => undef,
        is_amend => bool, source => upload, upload => bool, new_name => str, new => bool,
    ],
    problem_history_blob => [ \&CATS::UI::ProblemHistory::problem_history_blob_frame,
        pid => required integer, hb => required sha, file => required str, src_enc => str,
    ],
    problem_history_raw => [ \&CATS::UI::ProblemHistory::problem_history_raw_frame,
        pid => required integer, hb => required sha, file => required str,
    ],
    problem_history_commit => [ \&CATS::UI::ProblemHistory::problem_history_commit_frame,
        pid => required integer, h => required sha, src_enc => str,
    ],
    problem_history_tree => [ \&CATS::UI::ProblemHistory::problem_history_tree_frame,
        pid => required integer, hb => required sha, file => str, repo_enc => encoding, delete_file => str,
    ],
    set_problem_color => [ \&CATS::UI::Problems::set_problem_color,
        cpid => integer, color => qr/^#[0-9A-Fa-f]{6}$/,
    ],

    users => [
        \&CATS::UI::Users::users_frame,
        %user_params,
        save_attributes => bool, id => integer, locked => bool,
        set_tag => bool, tag_to_set => str,
        set_site => bool, site_id => integer,
        to_group => integer, add_to_group => bool,
        gen_passwords => bool, password_len => integer,
        send_message => bool, message_text => str, send_all => bool, send_all_contests => bool,
        delete_user => integer, new_save => bool, edit_save => bool,
        user_set => clist_of integer, sel => array_of integer,
    ],
    users_all_settings => [ \&CATS::UI::Users::users_all_settings_frame, ],
    users_import => [ \&CATS::UI::Users::users_import_frame,
        go => bool, do_import => bool, user_list => str, ],
    users_add_participants => [ \&CATS::UI::Users::users_add_participants_frame,
        logins_to_add => str, make_jury => bool, by_login => bool,
        source_cid => integer, from_contest => bool, include_ooc => bool,
        source_group_id => integer, from_group => bool, include_admins => bool,
    ],
    users_new => \&CATS::UI::UserDetails::users_new_frame,
    users_edit => [ \&CATS::UI::UserDetails::users_edit_frame, uid => integer, ],
    user_stats => [ \&CATS::UI::UserDetails::user_stats_frame, uid => integer, make_token => bool, ],
    user_settings => [ \&CATS::UI::UserDetails::user_settings_frame, uid => integer, clear => bool, ],
    user_ip => [ \&CATS::UI::UserDetails::user_ip_frame, uid => integer, ],
    user_vdiff => [ \&CATS::UI::UserDetails::user_vdiff_frame,
        uid => integer,
        diff_time => fixed, diff_units => ident,
        ext_time => fixed, ext_units => ident,
        is_virtual => bool, save => bool, finish_now => bool ],
    user_contacts => [ \&CATS::UI::UserContacts::user_contacts_frame,
        uid => integer, delete => integer, saved => integer,
    ],
    user_contacts_edit => [ \&CATS::UI::UserContacts::user_contacts_edit_frame,
        uid => integer, $CATS::UI::UserContacts::user_contact_form->route,
    ],
    user_relations => [ \&CATS::UI::UserRelations::user_relations_frame,
        uid => required integer, delete => integer, saved => integer,
    ],
    user_relations_edit => [ \&CATS::UI::UserRelations::user_relations_edit_frame,
        uid => required integer, $CATS::UI::UserRelations::form->route,
        from_login => str, to_login => str, js => bool,
    ],
    api_find_users => [ \&CATS::UI::UserRelations::find_users_api,
        query => str, in_contest => integer, ],
    impersonate => [ \&CATS::UI::UserDetails::impersonate_frame, uid => integer, ],
    contact_types => [
        \&CATS::UI::ContactTypes::contact_types_frame,
        delete => integer, saved => integer,
    ],
    contact_types_edit => [
        \&CATS::UI::ContactTypes::contact_types_edit_frame,
        $CATS::UI::ContactTypes::form->route,
    ],
    account_tokens => [ \&CATS::UI::AccountTokens::account_tokens_frame, delete => str, ],
    compilers => [ \&CATS::UI::Compilers::compilers_frame, delete => integer, saved => integer, ],
    compilers_edit => [ \&CATS::UI::Compilers::compilers_edit_frame, $CATS::UI::Compilers::form->route, ],
    judges => [ \&CATS::UI::Judges::judges_frame,
        delete => integer, saved => integer,
        ping => integer, pin_mode => integer,
        selected => array_of integer, update => bool, set_pin_mode => bool,
    ],
    judges_edit => [ \&CATS::UI::Judges::judges_edit_frame,
        account_name => str, $CATS::UI::Judges::form->route,
    ],
    keywords => [ \&CATS::UI::Keywords::keywords_frame,
        delete => integer, saved => integer,
        sel => array_of integer, search_selected => bool, ],
    keywords_edit => [ \&CATS::UI::Keywords::keywords_edit_frame, $CATS::UI::Keywords::form->route, ],
    import_sources => [ \&CATS::UI::ImportSources::import_sources_frame, ],
    download_import_source => [ \&CATS::UI::ImportSources::download_frame, psid => integer, ],
    prizes => [ \&CATS::UI::Prizes::prizes_frame,
        edit => integer, delete => integer, edit_save => bool, id => integer,
        clist => clist_of integer, name => str, ],
    contests_prizes => [ \&CATS::UI::Prizes::contests_prizes_frame, clist => clist_of integer, ],
    sites => [ \&CATS::UI::Sites::sites_frame, delete => integer, saved => integer, ],
    sites_edit => [ \&CATS::UI::Sites::sites_edit_frame, $CATS::UI::Sites::form->route ],
    snippets => [ \&CATS::UI::Snippets::snippets_frame, delete => integer, saved => integer, ],
    snippets_edit => [ \&CATS::UI::Snippets::snippets_edit_frame, $CATS::UI::Snippets::form->route,
        login => str, js => bool,
    ],
    answer_box => [ \&CATS::UI::Messages::answer_box_frame,
        qid => integer, clarify => 1, answer_text => str, ],
    send_message_box => [ \&CATS::UI::Messages::send_message_box_frame,
        caid => integer, send => bool, message_text => str, ],

    run_log => [ \&CATS::UI::RunDetails::run_log_frame,
        rid => integer, delete_log => bool, delete_jobs => bool, ],
    view_source => [ \&CATS::UI::ViewSource::view_source_frame,
        rid => integer, replace => bool, replace_and_submit => bool,
        de_id => qr/\d+|by_extension/, syntax => ident,
        src_enc => encoding_default('UTF-8'),
        source => upload,
        submit => bool, source_text => str, np => integer, submitted => bool,
    ],
    download_source => [ \&CATS::UI::ViewSource::download_source_frame,
        rid => integer, hash => str,
        src_enc => encoding_default('UTF-8'),
    ],
    print_source => [ \&CATS::UI::ViewSource::print_source_frame,
        rid => integer, syntax => ident, src_enc => encoding_default('UTF-8'), ],
    run_details => [ \&CATS::UI::RunDetails::run_details_frame,
        rid => required clist_of integer,
        comment_enc => encoding_default('UTF-8'),
        as_user => bool,
    ],
    job_details => [ \&CATS::UI::Jobs::job_details_frame,
        jid => integer, delete_log => bool, delete_jobs => bool,
    ],
    visualize_test => [ \&CATS::UI::RunDetails::visualize_test_frame,
        rid => integer, vid => integer, test_rank => integer, as_user => bool, ],
    diff_runs => [ \&CATS::UI::ViewSource::diff_runs_frame,
        r1 => integer, r2 => integer,
        src_enc => encoding_default('UTF-8'),
        ignore_ws => bool,
        similar => bool, reject_both => bool, reject_both_message => str,
    ],
    view_test_details => [
        \&CATS::UI::RunDetails::view_test_details_frame,
        comment_enc => encoding_default('UTF-8'),
        rid => integer, test_rank => integer,
        delete_request_outputs => bool, delete_test_output => bool, as_user => bool,
        noimage => bool,
    ],
    request_params => [
        \&CATS::UI::RequestParams::request_params_frame,
        rid => integer,
        status_ok => bool,
        reinstall => bool,
        single_judge => bool,
        retest => bool,
        clone => bool,
        delete_request => bool,
        set_state => bool,
        failed_test => integer,
        points => integer,
        state => ident,
        set_tag => bool, tag => str,
        set_user => bool, new_login => str,
        (map { $_ => str, "set_$_" => bool } @cats::limits_fields, 'job_split_strategy'),
        testsets => str,
        judge => str, set_judge => bool,
    ],
    api_get_last_verdicts => [ \&CATS::UI::RunDetails::get_last_verdicts_api, problem_ids => clist_of integer ],
    api_get_request_state => [ \&CATS::UI::RunDetails::get_request_state_api, req_ids => clist_of integer ],

    test_diff => [ \&CATS::UI::Stats::test_diff_frame, pid => integer, test => integer, ],
    compare_tests => [ \&CATS::UI::Stats::compare_tests_frame, pid => required integer, ],
    rank_table_content => [ \&CATS::UI::RankTable::rank_table_content_frame,
        (map { $_ => bool0 } @CATS::UI::RankTable::router_bool_params),
        filter => str,
        groups => clist_of integer,
        sites => clist_of integer,
        sort => ident,
    ],
    rank_table => [ \&CATS::UI::RankTable::rank_table_frame,
        (map { $_ => bool0 } @CATS::UI::RankTable::router_bool_params),
        filter => str,
        groups => clist_of integer,
        sites => clist_of integer,
        sort => ident,
    ],
    rank_problem_details => \&CATS::UI::RankTable::rank_problem_details,
    api_submit_problem => [ \&CATS::UI::Problems::submit_problem_api,
        source => upload, source_text => str, problem_id => integer, de_id => qr/\d+|by_extension/,
    ],
    api_get_sources_info => [ \&CATS::UI::RunDetails::get_sources_info_api,
        problem_id => integer, contest_id => integer, src_enc => encoding_default('UTF-8'),
        uid => integer, rid => integer,
    ],
    problem_text => [ \&CATS::UI::Problems::problem_text_frame,
        pid => integer, cpid => integer, cid => integer,
        explain => bool, nospell => bool, noformal => bool, noif => bool, pl => ident, nokw => bool,
        tags => str, raw => bool, nomath => bool, uid => integer, noauthor => bool, noformats => bool,
    ],
    get_snippets => [ \&CATS::UI::Snippets::get_snippets,
        cpid => integer, snippet_names => array_of ident, uid => integer,
    ],
    envelope => [ \&CATS::UI::Messages::envelope_frame, rid => integer, ],
    about => \&CATS::UI::About::about_frame,

    similarity => [ \&CATS::UI::Stats::similarity_frame,
        %CATS::UI::Stats::similarity_route, cont => bool,
    ],
    personal_official_results => [ \&CATS::UI::ContestResults::personal_official_results,
        search => str, group => ident,
    ],
    wiki => [ \&CATS::UI::Wiki::wiki_frame, name => str, ],
    wiki_pages => [ \&CATS::UI::Wiki::wiki_pages_frame, delete => integer, saved => integer, ],
    wiki_pages_edit => [ \&CATS::UI::Wiki::wiki_pages_edit_frame,
        delete => integer, $CATS::UI::Wiki::page_form->route, ],
    wiki_edit => [ \&CATS::UI::Wiki::wiki_edit_frame, $CATS::UI::Wiki::text_form->route, ],
    jobs => [ \&CATS::UI::Jobs::jobs_frame, delete => integer, ],
    files => [ \&CATS::UI::Files::files_frame,
        delete => integer, saved => integer,
    ],
    files_edit => [ \&CATS::UI::Files::files_edit_frame,
        $CATS::UI::Files::form->route, file => upload, ],
    de_tags => [ \&CATS::UI::DeTags::de_tags_frame,
        delete => integer, saved => integer,
        add => bool, remove => bool, check => array_of integer,
    ],
    de_tags_edit => [ \&CATS::UI::DeTags::de_tags_edit_frame,
        $CATS::UI::ContestTags::form->route, include => array_of integer, ],
    api_questions => [ \&CATS::UI::Messages::questions_api,
        clarified => bool, ],
    api_answer => [ \&CATS::UI::Messages::answer_api,
        qid => integer, answer => str, ],
};

my $api_judge_routes = {
    get_judge_id => [ \&CATS::ApiJudge::get_judge_id, version => str ],
    api_judge_get_des => [ \&CATS::ApiJudge::get_DEs, active_only => bool, id => integer, ],
    api_judge_get_problem => [ \&CATS::ApiJudge::get_problem, pid => integer, ],
    api_judge_get_problem_sources => [ \&CATS::ApiJudge::get_problem_sources, pid => integer, ],
    api_judge_get_problem_tests => [ \&CATS::ApiJudge::get_problem_tests, pid => integer, ],
    api_judge_get_snippet_text => [ \&CATS::ApiJudge::get_snippet_text, pid => integer, cid => integer,
        uid => integer, name => ident, ],
    api_judge_get_problem_tags => [ \&CATS::ApiJudge::get_problem_tags, pid => integer, cid => integer, ],
    api_judge_get_problem_snippets => [ \&CATS::ApiJudge::get_problem_snippets, pid => integer, ],
    api_judge_is_problem_uptodate => [ \&CATS::ApiJudge::is_problem_uptodate, pid => integer, date => str, ],
    api_judge_save_logs => [ \&CATS::ApiJudge::save_logs, job_id => integer, dump => undef, ],
    api_judge_is_set_req_state_allowed => [
        \&CATS::ApiJudge::is_set_req_state_allowed,
        job_id => integer,
        force => bool,
    ],
    api_judge_select_request => [
        \&CATS::ApiJudge::select_request,
        de_version => integer,
        map { +"de_bits$_" => integer } 1..$cats::de_req_bitfields_count,
    ],
    api_judge_set_request_state => [
        \&CATS::ApiJudge::set_request_state,
        req_id => integer,
        state => integer,
        job_id => integer,
        problem_id => integer,
        contest_id => integer,
        failed_test => integer,
    ],
    api_judge_create_job => [
        \&CATS::ApiJudge::create_job,
        job_type => integer,
        (map { $_ => integer } @CATS::ApiJudge::create_job_params),
    ],
    api_judge_create_splitted_jobs => [
        \&CATS::ApiJudge::create_splitted_jobs,
        job_type => integer,
        (map { $_ => integer } @CATS::ApiJudge::create_job_params),
        testsets => array_of str,
    ],
    api_judge_finish_job => [
        \&CATS::ApiJudge::finish_job,
        job_id => integer,
        job_state => integer,
    ],
    api_judge_cancel_all => [
        \&CATS::ApiJudge::cancel_all,
        req_id => integer,
    ],
    api_judge_get_tests_req_details => [\&CATS::ApiJudge::get_tests_req_details, req_id => integer, ],
    api_judge_delete_req_details => [ \&CATS::ApiJudge::delete_req_details, req_id => integer, job_id => integer, ],
    api_judge_insert_req_details => [
        \&CATS::ApiJudge::insert_req_details,
        job_id => integer,
        %CATS::ApiJudge::req_details_fields,
    ],
    api_judge_save_input_test_data => [
        \&CATS::ApiJudge::save_input_test_data,
        problem_id => integer,
        test_rank => integer,
        input => undef,
        input_size => integer,
    ],
    api_judge_save_answer_test_data => [
        \&CATS::ApiJudge::save_answer_test_data,
        problem_id => integer,
        test_rank => integer,
        answer => undef,
        answer_size => integer,
    ],
    api_judge_save_problem_snippet => [
        \&CATS::ApiJudge::save_problem_snippet,
        problem_id => integer,
        contest_id => integer,
        account_id => integer,
        snippet_name => ident,
        text => undef,
    ],
    api_judge_get_testset => [
        \&CATS::ApiJudge::get_testset,
        table => qr/^(reqs|jobs)$/, id => integer, update => integer,
    ],
};

sub parse_uri { $_[0]->get_uri =~ m~/cats/(|main.pl)$~ }

my $common_params = [ 1,
    f => ident, enc => encoding, cid => integer, cpid => integer, json => qr/^[a-zA-Z0-9_]+$/,
    lang => ident, clist => clist_of integer, notime => bool, noiface => bool, csv => clist_of ident ];

sub common_params {
    my ($p) = @_;
    CATS::RouteParser::parse_route($p, $common_params);

    $p->{jsonp} = $p->{json} if $p->{json} && $p->{json} =~ /^[a-zA-Z_][a-zA-Z0-9_]*$/;
    $p->{json} &&= 1;
    $p->{f} //= '';
}

sub route {
    my ($p) = @_;
    my $default_route = \&CATS::UI::About::about_frame;

    my $route =
        $main_routes->{$p->{f}} ||
        $api_judge_routes->{$p->{f}}
        or return $default_route;
    CATS::RouteParser::parse_route($p, $route) // $default_route;
}

1;
