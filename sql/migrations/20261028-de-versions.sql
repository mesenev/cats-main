/* Show language versions in DE names, so students know which syntax and
   library features they get. Versions are the judge image's
   (dockerfiles/cats-judge.dockerfile, registry tag 2026-10-28b), to the minor
   version, so routine patch updates of the image need no rename.
   Update these names whenever a compiler or interpreter in the image changes. */
UPDATE default_de SET description = 'GNU C++ 12.2 (C++23)' WHERE code = 102;
UPDATE default_de SET description = 'GNU C 12.2 (C17)' WHERE code = 105;
UPDATE default_de SET description = 'Free Pascal 3.2.2' WHERE code = 202;
UPDATE default_de SET description = 'Free Pascal 3.2.2, Delphi mode' WHERE code = 204;
UPDATE default_de SET description = 'Go 1.27' WHERE code = 404;
UPDATE default_de SET description = 'Perl 5.36' WHERE code = 501;
UPDATE default_de SET description = 'Python 3.15' WHERE code = 502;
UPDATE default_de SET description = 'Haskell (GHC 9.10)' WHERE code = 503;
UPDATE default_de SET description = 'PyPy 3.11' WHERE code = 510;
UPDATE default_de SET description = 'SQLite 3.40' WHERE code = 520;
