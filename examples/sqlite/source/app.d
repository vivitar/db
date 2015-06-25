import std.stdio;

import db;
import std.stdio;

void main()
{
	auto db = new Database("sqlite:///tmp/test.sqlite"); 
	if (!db.open())
	{
		writefln("SQLite open error: %s", db.error.text);
		return;
	}

	auto q = new Query(db);

	q.exec("SELECT 1 as X");
	writeln("Query.Error: ", q.error);
	writefln("Result: Positional 0=%s Named X=%s", q.result[0], q.result["X"]);


	db.transaction();
	q.exec("
	CREATE TEMP TABLE tmp_users(
		id        INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
		is_active BOOL    NOT NULL,
		login     VARCHAR NOT NULL
	)");
	writefln("Table create error: %s", q.error);

	q.prepare("INSERT INTO tmp_users (is_active, login) VALUES (${0}, ${1})");
	writefln("Prepared error: %s", q.error);

	if (!q.execPrepared(true,  "root")
	 || !q.execPrepared(true,  "postgres")
	 || !q.execPrepared(false, "anon")
	)
	{
		writefln("Error: %s", q.error.text);
		// Rolback transaction
		db.rollback();
	}
	else
	{
		// Commit transaction
		db.commit();
	}

	q.exec("SELECT * FROM tmp_users");

	writeln("Query.Error:         ", q.error);
	writeln("Query.Result.query:  ", q.result.query);
	writeln("Query.Result.length: ", q.result.length);

	writeln(" id  | is_active | login");
	writeln("-------------------------");

	foreach (row; q.result)
	{
		writefln("%4s | %-9s | %s", row["id"].get!long, row["is_active"].get!string, row["login"].get!string);
	}
}
