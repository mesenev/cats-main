/* de_de_tags had no key, and its seed row per DE was inserted again on every
   database initialization: prod had 294 rows for 38 (tag, DE) pairs, which
   broke the DE tags page ("more than one row returned by a subquery").
   Keep one row per pair, then add the keys so it cannot happen again. */
DELETE FROM de_de_tags a USING de_de_tags b
    WHERE a.ctid < b.ctid AND a.de_id = b.de_id AND a.tag_id = b.tag_id;
ALTER TABLE de_de_tags ADD CONSTRAINT de_de_tags_pk PRIMARY KEY (de_id, tag_id);

DELETE FROM contest_de_tags a USING contest_de_tags b
    WHERE a.ctid < b.ctid AND a.contest_id = b.contest_id AND a.tag_id = b.tag_id;
ALTER TABLE contest_de_tags ADD CONSTRAINT contest_de_tags_pk PRIMARY KEY (contest_id, tag_id);
