/* Judges allowed to test the problem's submissions. No rows: any judge. */
CREATE TABLE problem_judges (
    problem_id  INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    judge_id    INTEGER NOT NULL REFERENCES judges(id) ON DELETE CASCADE,

    CONSTRAINT problem_judges_pk PRIMARY KEY (problem_id, judge_id)
);
