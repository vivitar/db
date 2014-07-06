db - Concept (unstable)
=======================

About
=====
D language databse connection package, contains only base classes, interfaces, and mixin for creare database drivers.
But allows work with diffirent databases (if drivers present) with single interface.

Single connection
=================
For e.g. if driver for target database exists.

    import db;
    import std.stdio;

    URI uri1 = "postgresql://postgres@127.0.0.1/postgres";
    URI uri2 = "mysql://postgres@127.0.0.1/test1";

    Database db1 = Database(uri1);
    Database db2 = Database(uri2);

    if (!db1.open)
    {
        writeln(db1.error);
    }
    else
    {
        auto query1 = db1.query("SELECT a, a+1 as a_inc FROM generate_series(1, 10) a");

        // foreach in nearest plans =)
        foreach(row: query1) {
          writeln(text("a=", row[0], " a_inc=", query["a_inc"]));
        }
    }


Pool
====
Pool example:

    import db;
    import std.stdio;

    URI uri1 = "postgresql://postgres@127.0.0.1/postgres";
    URI uri2 = "mysql://postgres@127.0.0.1/test1";

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
    delete db1;
    delete db2;
    delete db3;

    // At now we have two free connections in pool "second", and one in pool "default"

Drivers
=======

* [PostgreSQL](https://github.com/anton-dutov/db-postgresql)

