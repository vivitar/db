db - Concept (unstable API)
=======================
[![Build Status](https://travis-ci.org/anton-dutov/db.svg?branch=master)](https://travis-ci.org/anton-dutov/db)


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
        auto db1 = new Database("postgresql://postgres@127.0.0.1/postgres");
        if (!db1.open)
        {
            writeln(db1.error);
            return;
        } 

        void qInfo(Query q)
        {
            writeln("Query.Error:            ", q.error);
            writeln("Query.Result.query:     ", q.result.query);
            writeln("Query.Result.length:    ", q.result.length);
        }
        auto query1 = new Query(db1);
        auto query2 = new Query(db1);
    //
        if(!query1.exec("SELECT a, a+1 as a_inc FROM generate_series(1, 10) a"))
        {
            qInfo(query1);
            return;
        }
        qInfo(query1);

        if(!query2.exec("SELECT a, a+1 as a_inc FROM generate_series(10, 30) a")) 
        {
            qInfo(query2);
            return;
        }
        qInfo(query2);
        
        foreach (row; query1.result)
        {
           writeln("Result(Positional) 0=", row[0], " 1=", row[1]);
           writeln("Result(Named)      a=", row["a"], " a_inc=", row["a_inc"]);
        }
        foreach (row; query2.result)
        {
           writeln("Result(Positional) 0=", row[0], " 1=", row[1]);
           writeln("Result(Named)      a=", row["a"], " a_inc=", row["a_inc"]);
        }

        
        /*
         * Prepared statements
         */

        // Force begin transaction
        db1.transaction();
        query1.exec("CREATE TEMP TABLE tmp_users(
            id        SERIAL  NOT NULL PRIMARY KEY,
            is_active BOOL    NOT NULL,
            login     VARCHAR NOT NULL
        )");
        
        query1.prepare("INSERT INTO tmp_users (is_active, login) VALUES (${0}, ${1})");
        writeln(query1.error);
        
        if (!query1.execPrepared(true,  "root")
         || !query1.execPrepared(true,  "postgres")
         || !query1.execPrepared(false, "anon"))
        {
            writeln(query1.error);
            // Rolback transaction
            db1.rollback();
        }
        else
        {
            // Commit transaction
            db1.commit();
        }

        query2.exec("SELECT * FROM tmp_users");

        writeln("Result.length: ", query2.result.length);

        writeln(" id  | is_active | login");
        writeln("-------------------------");

        foreach (row; query2.result)
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

