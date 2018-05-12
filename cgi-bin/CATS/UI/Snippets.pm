package CATS::UI::Snippets;

use strict;
use warnings;

use CATS::Globals qw($cid $is_jury $is_root $sid $t $uid);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(url_f);
use CATS::DB;
use CATS::Web qw(param print_json);
use CATS::Job;

sub fields() {qw(id account_id problem_id contest_id text name)}

my $form = CATS::Form->new({
    table => 'snippets',
    fields => [ map +{ name => $_ }, fields() ],
    templates => { edit_frame => 'snippets_edit.html.tt' },
    href_action => 'snippets',
});

sub edit_frame {
    my ($p) = @_;
    $form->edit_frame($p, after => sub {
        $_[0]->{problems} = $dbh->selectall_arrayref(q~
            SELECT P.id AS "value", CP.code || ': ' || P.title AS text
            FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
            WHERE CP.contest_id = ?
            ORDER BY CP.code~, { Slice => {} },
            $cid);

        $_[0]->{accounts} = $dbh->selectall_arrayref(q~
            SELECT A.id AS "value", A.team_name AS text
            FROM accounts A INNER JOIN contest_accounts CA ON A.id = CA.account_id
            WHERE CA.contest_id = ?
            ORDER BY A.team_name~, { Slice => {} },
            $cid);
    });
}

sub edit_save {
    my ($p) = @_;
    $p->{contest_id} = $cid;

    my ($snippet_id) = $dbh->selectrow_array(q~
        SELECT id FROM snippets
        WHERE problem_id = ? AND account_id = ? AND contest_id = ? AND name = ?~, undef,
        @$p{qw(problem_id account_id contest_id name)}
    );
    return msg(1077, $p->{name}) if $snippet_id && $snippet_id != ($p->{id} // 0);

    $form->edit_save($p) and msg(1075, $p->{name});
}

sub _problem_visible {
    my ($cpid) = @_;
    return 1 if $is_root;

    my $c = $dbh->selectrow_hashref(qq~
        SELECT
            CAST(CURRENT_TIMESTAMP - $CATS::Time::contest_start_offset_sql AS DOUBLE PRECISION) AS since_start,
            C.local_only, C.is_hidden, CA.id AS caid, CA.is_jury, CA.is_remote, CA.is_ooc, CP.status
        FROM contest_problems CP INNER JOIN contests C ON CP.contest_id = C.id
        LEFT JOIN contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
        LEFT JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = CA.site_id
        WHERE CP.id = ?~, undef,
    $uid, $cpid) or return 0;

    return 1 if $c->{is_jury};

    $c->{status} < $cats::problem_st_hidden or return 0;

    if (($c->{since_start} || 0) > 0 && (!$c->{is_hidden} || $c->{caid})) {
        $c->{local_only} or return 1;
        defined $uid or return 0;
        return 1 if defined $c->{is_remote} && $c->{is_remote} == 0 || defined $c->{is_ooc} && $c->{is_ooc} == 0;
    }

    0;
}

sub get_snippets {
    my ($p) = @_;

    $uid && _problem_visible($p->{cpid}) or return print_json({});

    my $snippets = $dbh->selectall_arrayref(my @d = _u $sql->select(q~
        snippets S
        INNER JOIN contest_problems CP ON S.contest_id = CP.contest_id AND S.problem_id = CP.problem_id~,
        'name, text',
        { name => $p->{snippet_names}, 'CP.id' => $p->{cpid}, account_id => $uid }));

    my $res = {};
    $res->{$_->{name}} = $_->{text} //= '' for @$snippets;

    my ($contest_id, $problem_id) = $dbh->selectrow_array(q~
        SELECT contest_id, problem_id FROM contest_problems WHERE id = ?~, undef,
        $p->{cpid});

    my $snippet_names = $dbh->selectcol_arrayref(q~
        SELECT snippet_name FROM problem_snippets WHERE problem_id = ?~, undef,
        $problem_id);

    my @gen_snippets = grep !exists $res->{$_}, @$snippet_names;
    if (@gen_snippets) {
        for (@gen_snippets) {
            $dbh->do(q~
                INSERT INTO snippets (id, name, contest_id, problem_id, account_id) VALUES (?, ?, ?, ?, ?)~, undef,
                new_id, $_, $contest_id, $problem_id, $uid);
        }
        CATS::Job::create($cats::job_type_generate_snippets,
            { account_id => $uid, contest_id => $contest_id, problem_id => $problem_id });
        $dbh->commit;
    }

    print_json($res);
}

sub snippet_frame {
    my ($p) = @_;

    $is_root or return;

    $form->edit_delete(id => $p->{delete}, descr => 'name', msg => 1076);
    $p->{edit_save} and edit_save($p);
    $p->{new} || $p->{edit} and return edit_frame($p);

    my $lv = CATS::ListView->new(
        name => 'snippets',
        template => 'snippets.html.tt');

    my @cols = (
        { caption => res_str(602), order_by => 'problem_name', width => '20%' },
        { caption => res_str(608), order_by => 'team_name', width => '20%' },
        { caption => res_str(601), order_by => 'name', width => '20%' },
        { caption => res_str(672), order_by => 'text', width => '40%' },
    );

    $lv->define_columns(url_f('snippets'), 0, 0, \@cols);
    $lv->define_db_searches([ fields() ]);

    my $sth = $dbh->prepare(q~
        SELECT
            S.id, S.name, S.problem_id, S.account_id,
            SUBSTRING(S.text FROM 1 FOR 100) AS text,
            P.title AS problem_name,
            A.team_name
        FROM snippets S
        INNER JOIN contests C ON C.id = S.contest_id
        INNER JOIN problems P ON P.id = S.problem_id
        INNER JOIN accounts A ON A.id = S.account_id
        WHERE S.contest_id = ?
        ~ . $lv->order_by
    );
    $sth->execute($cid);


    my $fetch_record = sub {
        my $c = $_[0]->fetchrow_hashref or return ();
        return (
            %$c,
            href_delete => url_f('snippets', delete => $c->{id}),
            href_edit => url_f('snippets', edit => $c->{id}),
        );
    };

    $lv->attach(url_f('snippets'), $fetch_record, $sth);

    $sth->finish;

    $t->param(
        submenu => [ CATS::References::menu('snippets') ],
        editable => $is_root,
     );
}

1;
