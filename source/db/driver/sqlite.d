module db.driver.sqlite;

version (USE_SQLITE):

import db.core;

import std.array: replace;
import std.algorithm: count;
import std.string: toStringz;
import std.regex: match;
//import std.datetime;
import etc.c.sqlite3;



version (Windows)
{
	pragma (lib, "sqlite3");
}
else version (linux)
{
	pragma (lib, "sqlite3");
}
else version (Posix)
{
	pragma (lib, "libsqlite3");
}
else version (darwin)
{
	pragma (lib, "libsqlite3");
}
else
{
	pragma (msg, "Please link in the SQLite library.");
} 

shared static this()
{
	Database.regDriver(new SQLiteDriverCreator);
}

final class SQLiteDriverCreator: DbDriverCreator
{
	mixin DbDriverCreatorMixin!("sqlite", ["sqlite3"], SQLiteDriver);
}

final class SQLiteDriver: DbDriver
{
	mixin DbDriverMixin!(sqlite3*, SQLiteResult);

	bool hasFeature(Database.Feature f)
	{
		switch (f)
		{
			case Database.Feature.blob:
			case Database.Feature.transactions:
			case Database.Feature.lastInsertId:
			case Database.Feature.preparedQueries:
				return true;
			default:
		}
		return false;
	}

	bool open(URI u)
	{
		_uri  = u;

		string uri = u.path;

		auto conStr = toStringz(uri);

		if (isOpen)
		{
			close();
		}

		if (!uri.length)
		{
			return false;
		}

		auto result = sqlite3_open(conStr, &_handle) == SQLITE_OK;
		if (result)
		{
		}
		else
		{
			errorTake(DbError.Type.connection);
			close();
		}
		dbDebug("%s.open(%s) -> %s [%s]", typeid(this), uri, result, _handle);
		return result;
	}

	void close()
	{
		dbDebug("%s.close [%s]", typeid(this), _handle);

//		foreach(r; _results)
//		{
//			r.clear();
//		}

		if (_handle !is null)
		{
			sqlite3_close(_handle);
			_handle = null;
		}
	}

	private bool exec(string query)
	{
		if (!isOpen)
		{
			return false;
		}

		errorClear();

		dbDebug("%s.exec: %s", typeid(this), query);

		char* 			qId;
		sqlite3_stmt*  	qStmt;
		auto res = sqlite3_prepare_v2(_handle, cast(char*) toStringz(query), cast(int) query.length + 1, &qStmt, &qId);

		if (res == SQLITE_OK) {
			res = sqlite3_step(qStmt);
			if (res != SQLITE_DONE && res != SQLITE_ROW)
			{
				errorTake(DbError.Type.statement);
			}
		}
		else
		{
			errorTake(DbError.Type.statement);
		}
		sqlite3_finalize(qStmt);
		return false;
	}

	private void errorTake(DbError.Type t)
	{
		int code = sqlite3_errcode(_handle);
		string drvStr;
		string dbStr;
		if (code)
		{
			drvStr = to!string(sqlite3_errmsg(_handle));
		}
		_error = DbError(t, drvStr, "", code);
	}
}

final class SQLiteResult: DbResult
{
	mixin DbResultMixin!(sqlite3_stmt*, SQLiteDriver);
	private
	{
		bool	_isOK;
		int[]   _fieldsTypes;
	}

	@property Variant lastInsertId()
	{
		if (isActive)
		{
			auto id = sqlite3_last_insert_rowid(_driver._handle);
			if (id)
			{
				return Variant(id);
			}
		}
		return Variant(null);
	}

	@property ulong affectedRowsLength()
	{
		if (isActive)
		{
			return to!ulong(to!string(sqlite3_changes(_driver._handle)));
		}
		return 0;
	}

	bool prepare(string query)
	{
		_isPrepared = false;
		clear();

		if (!_driver.isOpen)
		{
			return false;
		}

		errorClear();
		
		_query = query;

		char* pzTail = null;

		foreach(c; match(query, regexDbParam))
		{
			auto token = c[0], key = c[1];
			if (!_paramsTokens.count(token))
			{
				_paramsTokens ~= token;
				_paramsKeys   ~= key;
			}
			query = query.replace(token, "?");// ~ to!string(_paramsTokens.countUntil(token) + 1));
		}

		int res = sqlite3_prepare_v2(_driver._handle,
									cast(char*) toStringz(query),
									cast(int)   query.length + 1,
									&_handle, &pzTail);

		auto ex = to!string(pzTail);
		_isPrepared = res == SQLITE_OK && !ex.length;
		

		if (res != SQLITE_OK)
		{
			errorTake(DbError.Type.statement, "(Unable prepare statement)");
			clear();
		}
		else if (ex.length)
		{
			errorTake(DbError.Type.statement, "(Unable to execute multiple statements at a time)");
			clear();
		}

		dbDebug("%s.prepare: -> %s QueryID: %s\nQuery: %s\nReal query: %s\n", typeid(this), _isPrepared, null, _query, query);
		return _isPrepared;
	}

	bool execPrepared(Variant[string] params = null)
	{
		if (!_driver.isOpen || !isPrepared)
		{
			return false;
		}

		clear(true);

		errorClear();


		if (_paramsTokens.length != params.length)
		{
			throw new DbException(DbError.Type.statement, "Invalid parameters count");
		}

		auto res = sqlite3_reset(_handle);
		if (res != SQLITE_OK)
		{
			errorTake(DbError.Type.statement, "(Unable to reset statement)");
			clear();
			return false;
		}
		foreach (i, k; _paramsKeys)
		{
			auto ptr = k in params;
			if (ptr == null)
			{
				throw new DbException(DbError.Type.statement, "Param key '" ~ k ~ "' not found");
			}
			if (ptr.type == typeid(null))
			{
				res = sqlite3_bind_null(_handle, cast(int) i + 1);
			}
			else if (ptr.type == typeid(int))
			{
				res = sqlite3_bind_int(_handle, cast(int) i + 1, ptr.get!int);
			}
			else
			{
				string tmp = to!string(*ptr);
				res = sqlite3_bind_text(_handle, cast(int) i + 1,
										cast(char*)toStringz(tmp), 
										cast(int)  tmp.length + 1, SQLITE_TRANSIENT);
			}

			if (res != SQLITE_OK)
			{
				errorTake(DbError.Type.statement);
				return false;
			}
 		}

 		dbDebug("%s.execPrepared QueryID: %s, Params: %s", typeid(this), _queryId, params);
 		_isOK = false;
 		fetch(true);
		return _isOK;
	}

	bool fetch(bool isFirst = false)
	{

		if (!isActive)
		{
			return false;
		}

		if (!isFirst && !_row)
		{
			return true;
		}

		_fieldsValues = null;

		auto res = sqlite3_step(_handle);

		switch(res)
		{
			case SQLITE_ROW:
				_isOK = true;
				if (!_fieldsCount)
				{
					initFields(false);
				}

				_fieldsValues = null;
				foreach(i, t; _fieldsTypes)
				{
					switch (t)
					{
						case SQLITE_NULL:
							_fieldsValues ~= Variant(null);
							continue;
						case SQLITE_INTEGER:
							_fieldsValues ~= Variant(sqlite3_column_int64(_handle,  cast(int) i));
							continue;
						case SQLITE_FLOAT:
							_fieldsValues ~= Variant(sqlite3_column_double(_handle, cast(int) i));
							continue;
						case SQLITE_BLOB:
							auto bSize = sqlite3_column_bytes(_handle, cast(int) i);
							auto bData = cast(const ubyte *) sqlite3_column_blob(_handle, cast(int) i);
							byte[] data;
							data.length = bSize;
							foreach (j; 0 .. bSize)
							{
								data[j] = bData[j];
							}
							_fieldsValues ~= Variant(data);
							break;
						case SQLITE3_TEXT:
						default:
							_fieldsValues ~= Variant(to!string(sqlite3_column_text(_handle, cast(int) i)));
					}
				}
				return true;
			case SQLITE_DONE:
				_isOK = true;
				if (!_fieldsCount)
				{
					initFields(true);
				}
				sqlite3_reset(_handle);
				return false;
			case SQLITE_CONSTRAINT:
			case SQLITE_ERROR:
			case SQLITE_MISUSE:
			case SQLITE_BUSY:
			default:
				errorTake(DbError.Type.statement, "Unable to fetch row");
				sqlite3_reset(_handle);
		}
		return false;
	}

	private void errorTake(DbError.Type t, lazy string dbText = "")
	{
		int code = sqlite3_errcode(_driver._handle);
		string drvStr;
		string dbStr;
		if (code)
		{
			dbStr  = dbText;
			drvStr = to!string(sqlite3_errmsg(_driver._handle));
		}
		_error = DbError(t, drvStr, dbStr, code);
//		dbDebug("errorTake: %s %s %s %s", code, dbStr, drvStr, _error);
	}

	private void clear(bool saveHandle)
	{
		if (!saveHandle && _handle !is null)
		{
			sqlite3_finalize(_handle);
			_handle = null;
		}
		cleanup(isPrepared);
	}

	void clear()
	{
		clear(false);
	}

	private void initFields(bool noData)
	{
		_fieldsCount = sqlite3_column_count(_handle);
		
		for (ulong i = 0; i < _fieldsCount; ++i)
		{
			auto fName = to!string(sqlite3_column_name(_handle, cast(int) i));
			_fieldsTypes ~= noData ? -1 : sqlite3_column_type(_handle, cast(int) i);
			_fieldsNames ~= fName;
			_fieldsMap[fName] = i;
		}			
	}
}