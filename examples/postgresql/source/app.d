import db;
import std.stdio;

void qInfo(Query q)
{
    writeln("Query.Error:         ", q.error);
    writeln("Query.Result.query:  ", q.result.query);
    writeln("Query.Result.length: ", q.result.length);
}

void main()
{
auto db = new Database("postgres://postgres@127.0.0.1/postgres"); 
    if (!db.open())
    {
        writefln("PostgreSQL open error: %s", db.error.text);
        return;
    }

    writefln("db.open: '%s', Driver '%s'", db.uri.path , db.driver.name);

    auto q1 = new Query(db);
    auto q2 = new Query(db);

    if(!q1.exec("SELECT a, a+1 as a_inc FROM generate_series(1, 3) a"))
    {
        qInfo(q1);
        return;
    }

    if(!q2.exec("SELECT a, a+1 as a_inc FROM generate_series(500, 505) a")) 
    {
        qInfo(q2);
        return;
    }
    qInfo(q1);
    qInfo(q2);

    writefln("Result: Positional 0=%s 1=%s Named a=%s a_inc=%s",
                    q1.result[0], q1.result[1],
                    q1.result["a"], q1.result["a_inc"]);

    foreach (row; q1.result)
    {
        writefln("Result: Positional 0=%s 1=%s Named a=%s a_inc=%s",
                    row[0], row[1],
                    row["a"], row["a_inc"]);
    }

    foreach (row; q2.result)
    {
        writefln("Result: Positional 0=%s 1=%s Named a=%s a_inc=%s",
                    row[0], row[1],
                    row["a"], row["a_inc"]);
    }

    /*
    * Prepared statements
    */

    db.transaction();
    q1.exec("
    CREATE TEMP TABLE tmp_users(
        id        SERIAL  NOT NULL PRIMARY KEY,
        is_active BOOL    NOT NULL,
        login     VARCHAR NOT NULL
    )");

    q1.prepare("INSERT INTO tmp_users (is_active, login) VALUES (${0}, ${1})");

    if (!q1.execPrepared(true,  "root")
     || !q1.execPrepared(true,  "postgres")
     || !q1.execPrepared(false, "anon")
    )
    {
        writefln("Error: %s", q1.error.text);
        // Rolback transaction
        db.rollback();
    }
    else
    {
        // Commit transaction
        db.commit();
    }

    q2.exec("SELECT * FROM tmp_users");
    writeln("Result.text: ", q2.error.text);
    writeln("Result.length: ", q2.result.length);

    writeln(" id  | is_active | login");
    writeln("-------------------------");

    foreach (row; q2.result)
    {
        writefln("%4s | %-9s | %s ", row["id"].get!int, row["is_active"].get!bool, row["login"].get!string);
    }
    q1.destroy();
    q2.destroy();
    db.destroy();
}
