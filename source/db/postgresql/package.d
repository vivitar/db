module db.postgresql;

version (PostgreSQLDriver):

public import db.interfaces;
public import std.datetime;

import db.postgresql.libpq;

import std.algorithm;
import std.array;
import std.conv;
import std.string;
import std.regex;

debug import std.stdio;

auto reVer = ctRegex!(`(\d+).(\d+)(.(\d+))?`);

shared static this()
{
	Database.regDriver(new PostgreSQLDriverCreator);
}

class PostgreSQLDriverCreator: DbDriverCreator
{
	@property string name() const pure
	{
		return "postgresql";
	}

	@property string[] aliases() const pure
	{
		return ["psql", "pgsql", "postgres"];
	}

	DbDriver create()
	{
		return new PostgreSQLDriver(this);
	}
}

class PostgreSQLDriver: DbDriver
{
	mixin DbDriverMixin;

	private
	{
		PGconn*           _handle;
		PGresult*         _pgResult;
		PostgreSQLResult  _result;
		string            _queryName;
	}

	this(PostgreSQLDriverCreator creator)
	{
		_creator = creator;
		_result  = new PostgreSQLResult(this);
	}

	~this()
	{
		_result.destroy();
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
			if (exec("SELECT version()"))
			{
				auto m = to!string(_result[0]).match(reVer);
				if (m.captures.length)
				{
					auto p = m.captures[4].length ? m.captures[4] : "0";
					_version = Version(
						to!ubyte(m.captures[1]),
						to!ubyte(m.captures[2]),
						to!ubyte(p),
						Version.ReleaseLevel.release
					);
				}
			}
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

    void clear() {
        if (_pgResult != null)
        {
            PQclear(_pgResult);
            _pgResult = null;
        }
        cleanup();
    }

    void close()
    {
        clear();
        if (_handle != null)
        {
            PQfinish(_handle);
            _handle = null;
        }
    }

    bool prepare(string query)
    {
        clear();
        _lastQuery = query;
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
        auto pgResult = PQprepare(
            _handle,
            cast(char*)toStringz(_queryName),
            cast(char*)toStringz(query),
            cast(int)(_paramsTokens.length),
            cast(Oid*)(null)
        );
        _isPrepared = (PQresultStatus(pgResult) == ExecStatusType.PGRES_COMMAND_OK);
        if (!_isPrepared)
        {
            clear();
            errorTake(DbError.Type.transaction);
        }
        PQclear(pgResult);
        return _isPrepared;
    }

    bool exec(Variant[string] params = null)
    {
        errorClear();

        if (_handle is null)
        {
            return false;
        }

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
            string tmp = to!string(*ptr);
            if (ptr.type == typeid(null)) {
              values  ~= null;
              lengths ~= 0;
            } else {
              values  ~= cast(char*)(toStringz(tmp));
              lengths ~= cast(int)(tmp.length);
            }
            formats ~= 0;
        }
        _pgResult = PQexecPrepared(
            _handle,
            cast(char*)toStringz(_queryName),
            nParams,
            values.ptr,
            lengths.ptr,
            formats.ptr,
            0);
        switch(PQresultStatus(_pgResult)) {
        case ExecStatusType.PGRES_COMMAND_OK:
            return true;
        case ExecStatusType.PGRES_TUPLES_OK:
            _result.reset();
            return true;
        default: 
        }
        errorTake(DbError.Type.statement);
        return false;
    }

    bool exec(string query)
    {
        errorClear();
        _pgResult = PQexec(_handle, toStringz(query));
        switch(PQresultStatus(_pgResult)) {
        case ExecStatusType.PGRES_COMMAND_OK:
            return true;
        case ExecStatusType.PGRES_TUPLES_OK:
            _result.reset();
            return true;
        default: 
        }
        errorTake(DbError.Type.statement);
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
        bool                _fetch;
        PostgreSQLDriver    _driver;
        Oid[]               _fieldsTypes;
    }

    this(PostgreSQLDriver  driver)
    {
        _driver = driver;
    }

    @property Variant lastInsertId()
    {
        if (_driver._pgResult)
        {
            Oid id = PQoidValue(_driver._pgResult);
            if (id) // not InvalidOid
            {
                return Variant(id);
            }
        }
        return Variant();
    }

    Variant opIndex(uint index)
    {
        if ((_driver._handle is null || _row < 0 || _row >= _length || index >= _fieldsCount)
            || PQgetisnull(_driver._pgResult, cast(int)(_row), cast(int)(index)))
        {
            return Variant(null);
        }
        auto str = to!string(cast(char*)(PQgetvalue(_driver._pgResult, cast(int)(_row), cast(int)(index))));
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

    private void reset() {
        _row      = 0;
        _length   = 0;
        _firstFetch   = false;
        _fieldsCount  = 0;
        _fieldsTypes.length  = 0;
        _query.length        = 0;
        _fieldsNames.length  = 0;

        if (_driver is null || _driver._pgResult is null)
        {
            return;
        }
        _query         = _driver._lastQuery;
        _length        = PQntuples(_driver._pgResult);
        _fieldsCount   = PQnfields(_driver._pgResult);
        _affectedCount = to!uint(to!string(PQcmdTuples(_driver._pgResult)));
        for (int i = 0; i < _fieldsCount; ++i) {
           _fieldsTypes ~= PQftype(_driver._pgResult, i);
        }
        for (int i = 0; i < _fieldsCount; ++i) {
           _fieldsNames ~= to!string(PQfname(_driver._pgResult, i));
        }
    }
}