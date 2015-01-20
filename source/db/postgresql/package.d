module db.postgresql;

version (PostgreSQLDriver):

import db.interfaces;
import db.postgresql.libpq;

import std.algorithm;
import std.datetime;
import std.array;
import std.conv;
import std.string;
import std.regex;
import std.uuid;

version (DbDebug)
{
	import std.stdio;
}

shared static this()
{
	Database.regDriver(new PostgreSQLDriverCreator);
}

class PostgreSQLDriverCreator: DbDriverCreator
{
	@property string name() const pure nothrow
	{
		return "postgresql";
	}

	@property string[] aliases() const pure nothrow
	{
		return ["psql", "pgsql", "postgres"];
	}

	DbDriver create()
	{
		version (DbDebug)
		{
			writefln("PostgreSQLDriverCreator.create");
		}
		return new PostgreSQLDriver(this);
	}
}

class PostgreSQLDriver: DbDriver
{
	mixin DbDriverMixin;

	private
	{
		PGconn*             _handle;
		string              _queryName;
		PostgreSQLResult[]  _results;
	}

	this(PostgreSQLDriverCreator creator)
	{
		version (DbDebug)
		{
			writefln("PostgreSQLDriver.this");
		}
		_creator = creator;
	}

	~this()
	{
		version (DbDebug)
		{
			writefln("PostgreSQLDriver.~this");
		}
		close();
	}

	bool hasFeature(Database.Feature f)
	{
		switch (f)
		{
			case Database.Feature.unicode:
			case Database.Feature.transactions:
			case Database.Feature.resultSize:
			case Database.Feature.lastInsertId:
				return true;
			case Database.Feature.preparedQueries:
				return _version.hash >= 0x08020000; // 8.2;
			case Database.Feature.blob:
				return _version.hash >= 0x07010000; // 7.1;
			default:
		}
		return false;
	}

	bool open(URI u)
	{
		if (isOpen)
		{
			close();
		}
		_uri  = u;
		string uri;
		uri ~= " host="   ~ (_uri.host.length ? _uri.host : "127.0.0.1");
		uri ~= " port="   ~ (_uri.port ? to!string(_uri.port) : "5432");
		uri ~= " dbname=" ~ _uri.path.chompPrefix("/");
		if (_uri.username.length)
		{
			uri ~= " user=" ~ _uri.username;
		}
		if (_uri.password.length)
		{
			uri ~= " password=" ~ _uri.password;
		}
		auto conStr = toStringz(uri);
		_handle = PQconnectdb(conStr);
		auto result = (PQstatus(_handle) == ConnStatusType.CONNECTION_OK);
		if (result)
		{
//			if (exec("SELECT version()"))
//			{
//				auto m = to!string(_result[0]).match(reVer);
//				if (m.captures.length)
//				{
//					auto p = m.captures[4].length ? m.captures[4] : "0";
//					_version = Version(
//						to!ubyte(m.captures[1]),
//						to!ubyte(m.captures[2]),
//						to!ubyte(p),
//						Version.ReleaseLevel.release
//					);
//				}
//			}
			exec("SET CLIENT_ENCODING TO 'UNICODE'");
			exec("SET DATESTYLE TO 'ISO'");
		}
		else
		{
			errorTake(DbError.Type.connection);
			close();
		}
		return result;
	}

	void close()
	{
		version (DbDebug)
		{
			writefln("PostgreSQLDriver.close");
		}

//		foreach(r; _results)
//		{
//			r.clear();
//		}

		if (_handle != null)
		{
			PQfinish(_handle);
			_handle = null;
		}
	}

	DbResult mkResult()
	{
		version (DbDebug)
		{
			writefln("PostgreSQLDriver.mkResult");
		}
		auto result = new PostgreSQLResult(this);
		_results ~= result;
		return result;
	}

    private bool exec(string query)
	{
		if (!isOpen)
		{
			return false;
		}

		auto result = PQexec(_handle, toStringz(query));
		switch(PQresultStatus(result))
		{
			case ExecStatusType.PGRES_COMMAND_OK:
			case ExecStatusType.PGRES_TUPLES_OK:
				PQclear(result);
				return true;
				default: 
		}
		return false;
	}

    private void errorTake(DbError.Type t)
    {
        _error = DbError(t, to!string(PQerrorMessage(_handle)));
    }
}

class PostgreSQLResult: DbResult
{
	mixin DbResultMixin;
	private
	{
		PGresult*         	_handle;
		bool                _fetch;
		PostgreSQLDriver    _driver;
		Oid[]               _fieldsTypes;
	}

	this(PostgreSQLDriver  driver)
	{
		version (DbDebug)
		{
			writefln("PostgreSQLResult.this");
		}
        _driver = driver;
    }

    ~this()
    {
    	version (DbDebug)
		{
			writefln("PostgreSQLResult.~this");
		}
    }

    @property Variant lastInsertId()
    {
        if (_handle)
        {
            Oid id = PQoidValue(_handle);
            if (id) // not InvalidOid
            {
                return Variant(id);
            }
        }
        return Variant();
    }
//
//	@property uint rowsAffectedCount()
//	{
//		return _affectedCount;
//	}

	bool prepare(string query)
	{
		version (DbDebug)
		{
			writefln("PostgreSQLDriver.prepare");
		}

		clear();

		if (!_driver.isOpen)
		{
			return false;
		}

		queryIdClear();
		queryIdGen();

		_query = query;

        bool hasIndexes = false;
        bool hasStrings = false;
        foreach(c; match(query, regexDbParam)) {
            auto token = c[0], key = c[1];
            if (!_paramsTokens.count(token)) {
                _paramsTokens ~= token;
                _paramsKeys   ~= key;
            }
            query = query.replace(token, "$" ~ to!string(_paramsTokens.countUntil(token) + 1));
        }
        version (DbDebug)
		{
			writefln("PostgreSQLDriver.prepare: %s\nReal query: %s\nQueryID: %s", _query, query, _queryId);
		}
        auto pgResult = PQprepare(
            _driver._handle,
            cast(char*)toStringz(_queryId),
            cast(char*)toStringz(query),
            cast(int)(_paramsTokens.length),
            cast(Oid*)(null)
        );
        _isPrepared = (PQresultStatus(pgResult) == ExecStatusType.PGRES_COMMAND_OK);
        if (!_isPrepared)
        {
            clear();
            errorTake(DbError.Type.statement);
        }
        PQclear(pgResult);
        return _isPrepared;
    }

	bool exec(string query, Variant[string] params = null)
	{
		version (DbDebug)
		{
			writefln("PostgreSQLDriver.exec");
		}

		clear();

		if (!_driver.isOpen)
		{
			return false;
		}

		errorClear();

		if (!params.length)
		{
			_query  = query;
			_handle = PQexec(_driver._handle, toStringz(query));
		}
		else
		{
			return prepare(query) && execPrepared(params);
		}
		return takeResult();
	}

    bool execPrepared(Variant[string] params = null)
    {
    	if (!_driver.isOpen)
        {
            return false;
        }

        errorClear();

        if (_paramsTokens.length != params.length)
        {
            throw new DbException(DbError.Type.statement, "Invalid parameters count");
        }

        char*[]  values;
        int[]    lengths;
        int[]    formats;
        int nParams = cast(int)(_paramsKeys.length);
        foreach (k; _paramsKeys)
        {
            auto ptr = k in params;
            if (ptr == null) {
                throw new DbException(DbError.Type.statement, "Param key '" ~ k ~ "' not found");
            }
            string tmp = formatValue(*ptr);
            if (ptr.type == typeid(null)) {
              values  ~= null;
              lengths ~= 0;
            } else {
              values  ~= cast(char*)(toStringz(tmp));
              lengths ~= cast(int)(tmp.length);
            }
            formats ~= 0;
        }
        version (DbDebug)
		{
			writefln("PostgreSQLDriver.execPrepared\nQueryId: %s", _queryId);
		}
        _handle = PQexecPrepared(
            _driver._handle,
            cast(char*)toStringz(_queryId),
            nParams,
            values.ptr,
            lengths.ptr,
            formats.ptr,
            0);
        return takeResult();
    }


    Variant opIndex(uint index)
    {
        if ((_driver._handle is null || _row < 0 || _row >= _length || index >= _fieldsCount)
            || PQgetisnull(_handle, cast(int)(_row), cast(int)(index)))
        {
            return Variant(null);
        }
        auto str = to!string(cast(char*)(PQgetvalue(_handle, cast(int)(_row), cast(int)(index))));
        switch (_fieldsTypes[index])
        {
        case Type.BOOLOID:
            return Variant(str == "t");
        case Type.INT2OID:
        case Type.INT4OID:
            return Variant(to!int(str));
        case Type.INT8OID:
            return Variant(to!int(str));
        case Type.FLOAT4OID:
        case Type.FLOAT8OID:
            return Variant(to!double(str));
        case Type.NUMERICOID:
            return Variant(to!real(str));
        case Type.DATEOID:
            return Variant(Date.fromISOExtString(str));
        case Type.TIMESTAMPOID:
            return Variant(SysTime.fromISOExtString(str.replace(" ", "T")));
        case Type.TIMESTAMPTZOID:
            return Variant(SysTime.fromISOExtString(str.replace(" ", "T")));
        case 1015:
            return Variant(str[1 .. $ - 1].split(","));
        case Type.CHAROID:
        case Type.VARCHAROID:
        case Type.TEXTOID:
        default:
        }
        return Variant(str);
    }

    Variant opIndex(string name)
    {
        return opIndex(cast(uint)(_fieldsNames.countUntil(name)));
    }

    bool fetch()
    {
        return true;
    }

    void clear()
    {
        if (_handle != null)
        {
            PQclear(_handle);
            _handle = null;
        }
        cleanup();
    }

	private bool takeResult()
	{
		switch(PQresultStatus(_handle))
		{
        case ExecStatusType.PGRES_COMMAND_OK:
            return true;
        case ExecStatusType.PGRES_TUPLES_OK:
            reset();
            return true;
        default: 
        }
        errorTake(DbError.Type.statement);
        return false;
	}
    private void reset()
    {
        _row      = 0;
        _length   = 0;
        _firstFetch   = false;
        _fieldsCount  = 0;
        _fieldsTypes.length  = 0;
        _query.length        = 0;
        _fieldsNames.length  = 0;

        if (!isActive)
        {
            return;
        }
        _length        = PQntuples(_handle);
        _fieldsCount   = PQnfields(_handle);
        _affectedCount = to!uint(to!string(PQcmdTuples(_handle)));
        for (int i = 0; i < _fieldsCount; ++i) {
           _fieldsTypes ~= PQftype(_handle, i);
        }
        for (int i = 0; i < _fieldsCount; ++i) {
           _fieldsNames ~= to!string(PQfname(_handle, i));
        }
    }

    private void errorTake(DbError.Type t)
    {
        _error = DbError(t, to!string(PQerrorMessage(_driver._handle)));
    }

	private void queryIdClear()
	{
		if (!_queryId.length)
			return; 
		
		if (!_driver.exec("DEALLOCATE " ~ _queryId))
		{
		}
		_queryId.length = 0;
	}

	private void queryIdGen()
	{
		_queryId = to!string(randomUUID());
	}

	private string formatValue(Variant v)
	{
		if (v.type == typeid(null))
			return "NULL";

		if (v.type == typeid(bool))
			return v.get!bool ? "TRUE" : "FALSE";

		return to!string(v);
	}
}