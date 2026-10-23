# Runs a SQL submission (DE 520, SQLite) the way the std.sql.main module's
# launcher.py runs one submitted as Python: build an in-memory SQLite database
# from test.sql (plus 00.sql and query.sql if present), run the submission,
# and write test.log for the std.sql.check checker: an error code line, then
# the result rows as JSON. Same files, format and exit codes as launcher.py;
# only the submission's file name comes from the command line.
import sqlite3
import sys
from json import dumps

ERR_OK = 0
ERR_WA = 1
ERR_PE = 2
ERR_UH = 3

solution = sys.argv[1] if len(sys.argv) > 1 else 'solve.sql'

with (
    sqlite3.connect(":memory:") as con,
    open("test.sql") as sql,
    open("test.log", "w") as log
):
    try:
        with open("00.sql") as common_sql:
            con.executescript(common_sql.read())
    except OSError:
        pass

    con.executescript(sql.read())

    try:
        with open("query.sql") as fquery:
            query = fquery.read()
    except OSError:
        query = None

    try:
        with open(solution, 'r') as fid:
            sql = fid.read()
    except:
        log.write(str(ERR_PE) + '\n')
        log.write('File with query couldn\'t be read!')
        exit(ERR_UH)

    try:
        cur = con.cursor()
        cur.execute('pragma foreign_keys = on')
        if query is not None:
            cur.execute('pragma query_only = off')
            cur.executescript(sql)
            cur.execute(query)
        else:
            cur.execute('pragma query_only = on')
            cur.execute(sql)
    except (sqlite3.Warning, sqlite3.Error) as e:
        if type(e) in (sqlite3.ProgrammingError,
                       sqlite3.OperationalError,
                       sqlite3.Warning):
            log.write(str(ERR_PE) + '\n')
            log.write(str(e))
            exit(ERR_UH)

        print(e, file=sys.stderr)
        exit(ERR_UH)

    log.write(str(ERR_OK) + '\n')
    ans = dumps(cur.fetchall())
    print(ans, file=log)
