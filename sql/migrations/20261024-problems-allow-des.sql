/* DE codes a problem package allows by default (<AllowDEs>), e.g. '520,502'.
   A contest's own list for the problem (contest_problem_des) takes precedence. */
ALTER TABLE problems ADD allow_des VARCHAR(200);
