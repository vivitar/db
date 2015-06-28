db - D lang Database Layer
=========================
[![Build Status](https://travis-ci.org/anton-dutov/db.svg?branch=master)](https://travis-ci.org/anton-dutov/db)


About
=====
D language database connection package. Like Qt5 database layer.
Allows work with diffirent databases (if drivers present) with single interface.

[See examples folder](https://github.com/anton-dutov/db/tree/master/examples)

Drivers
=======
* SQLite - Basic functions, lib should link at compile time manualy (section "libs", that will be fixed in future versions), Version **USE_SQLITE**.
* PostgreSQL - Complete, lib loads dynamicaly throuth derelict-pq. Version **USE_POSTGRESQL**.


Versions
========

* **USE_DB_DEBUG** enables API debuging output to console.
* **USE_SQLITE** enables SQLite driver.
* **USE_POSTGRESQL** enables PostgreSQL driver.


Pool
====
Pool example:

    import db;
    import std.stdio;

    string uri1 = "postgresql://postgres@127.0.0.1/postgres";
    string uri2 = "postgresql://postgres@127.0.0.1/test1";

    auto dbPool = new DbPool;

    // Create pool named "default" with connection defined by uri1 and max con limit is 100
    dbPool.add("default", uri1, 100);

    // Create pool named "second" with connection defined by uri2 and without connections limit
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


