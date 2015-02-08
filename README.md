db - Concept (unstable API)
=======================
[![Build Status](https://travis-ci.org/anton-dutov/db.svg?branch=master)](https://travis-ci.org/anton-dutov/db)


About
=====
D language databse connection package. Like Qt5 database layer.
Allows work with diffirent databases (if drivers present) with single interface.

Drivers
=======
* SQLite - Basic functions, lib should
link at compile time manualy (section "libs", that will be fixed in future versions), Version **USE_SQLITE**.
* PostgreSQL - Complete, lib loads dynamicaly throuth derelict-pq. Version **USE_POSTGRESQL**.

Single connection example
=========================
dub.json

    "dependencies" : {
        "db":">=0.2.5"
    }
    "versions": [
        "USE_DB_DEBUG",
        "USE_SQLITE",
        "USE_POSTGRESQL"
    ],
    "libs":["sqlite3"]

Where:
* **USE_DB_DEBUG** enables API debuging output to console.
* **USE_SQLITE** enables SQLite driver.
* **USE_POSTGRESQL** enables PostgreSQL driver.

main.d

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
        testPostgreSQL();
        testSQLite();
    }

    void testPostgreSQL()
    {
        auto db = new Database("postgres://postgres@127.0.0.1/postgres"); 
        if (!db.open())
        {
            writefln("SQLite open error: %s", db.error.text);
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


    void testSQLite()
    {
        auto db = new Database("sqlite:/tmp/test.sqlite"); 
        if (!db.open())
        {
            writefln("SQLite open error: %s", db.error.text);
            return;
        }

        auto q1 = new Query(db);
            
        q1.exec("SELECT 1 as X");
        writeln("Query.Error: ", q1.error);
        writefln("Result: Positional 0=%s Named X=%s", q1.result[0], q1.result["X"]);

            
        db.transaction();
        q1.exec("
        CREATE TEMP TABLE tmp_users(
            id        INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            is_active BOOL    NOT NULL,
            login     VARCHAR NOT NULL
        )");
        writefln("Table create error: %s", q1.error);

        q1.prepare("INSERT INTO tmp_users (is_active, login) VALUES (${0}, ${1})");
        writefln("Prepared error: %s", q1.error);

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

            q1.exec("SELECT * FROM tmp_users");

            writeln(" id  | is_active | login");
            writeln("-------------------------");

            foreach (row; q1.result)
            {
                writefln("%4s | %-9s | %s", row["id"].get!long, row["is_active"].get!string, row["login"].get!string);
            }

    }


Pool
====
Pool example:

    import db;
    import std.stdio;

    string uri1 = "postgresql://postgres@127.0.0.1/postgres";
    string uri2 = "mysql://postgres@127.0.0.1/test1";

    auto dbPool = new DbPool;

    // Create pull named "default" with connection defined by uri1 and max con limit is 100
    dbPool.add("default", uri1, 100);

    // Create pull named "second" with connection defined by uri2 and without connections limit
    dbPool.add("second", uri2) ;

    // At now no any connections present

    // Creates connection in pool "default" marks it as "busy" and returns
    auto db1 = dbPool.db("default");

    // Creates connection in pool "second" marks it as "busy" and returns
    auto db2 = dbPool.db("second");

    // Creates connection in pool "second" marks it as "busy" and returns
    auto db3 = dbPool.db("second");

    ....

    // Destructors marks connections as "free", but no closes
    db1.destroy();
    db2.destroy();
    db3.destroy();

    // At now we have two free connections in pool "second", and one in pool "default"


