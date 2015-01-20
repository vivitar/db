db - Concept (unstable API)
=======================

About
=====
D language databse connection package, contains only base classes, interfaces, and mixin for creare database drivers.
But allows work with diffirent databases (if drivers present) with single interface.

Single connection
=================
dub.json

    "dependencies" : {
        "db":">=0.1.7"
    },
    versions:["PostgreSQLDriver"]

main.d

    import std.stdio;
    import db;
    void main()
    {
        auto db1 = new Database("postgresql://postgres@127.0.0.1/test");
        if (!db1.open)
        {
            writeln(db1.error);
            return;
        }

        if(!db1.exec("SELECT a, a+1 as a_inc FROM generate_series(1, 10) a"))
        {
            writeln(db1.error);
            return;
        }

        writeln("Driver.lastQuery: ", db1.driver.lastQuery);
        writeln("Result.query:     ", db1.result.query);
        writeln("Result.length:    ", db1.result.length);

        foreach (row; db1.result)
        {
           writeln("Result(Positional) 0=", row[0], " 1=", row[1]);
           writeln("Result(Named)      a=", row["a"], " a_inc=", row["a_inc"]);
        }

        /*
         * Prepared statements
         */
        
        // Force begin transaction
        db1.transaction();
        db1.exec("CREATE TEMP TABLE tmp_users(
            id        SERIAL  NOT NULL PRIMARY KEY,
            is_active BOOL    NOT NULL,
            login     VARCHAR NOT NULL
        )");
        
        db1.prepare("INSERT INTO tmp_users (is_active, login) VALUES (${0}, ${1})");
        
        if (!db1.execPrepared(true,  "root")
         || !db1.execPrepared(true,  "postgres")
         || !db1.execPrepared(false, "anon"))
        {
            // Rolback transaction
            db1.rollback();
        }
        else
        {
            // Commit transaction
            db1.commit();
        }
        
        db1.exec("SELECT * FROM tmp_users");

        writeln("Result.length: ", db1.result.length);

        writeln(" id  | is_active | login");
        writeln("-------------------------");

        foreach (row; db1.result)
        {
            writefln("%4s | %-9s | %s ", row["id"].get!int, row["is_active"].get!bool, row["login"].get!string);
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

Included drivers
================

* PostgreSQL

