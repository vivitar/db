module db.driver.postgresql;

//version (USE_POSTGRESQL):

import db.core;

import derelict.pq.pq;

import std.algorithm;
import std.datetime;
import std.array;
import std.conv;
import std.string;
import std.regex;
import std.uuid;

shared static this()
{
	DerelictPQ.load();

	if (DerelictPQ.isLoaded)
	{
		Database.regDriver(new PostgreSQLDriverCreator);
	}
}

final class PostgreSQLDriverCreator: DbDriverCreator
{
	mixin DbDriverCreatorMixin!("postgresql", ["psql", "pgsql", "postgres"], PostgreSQLDriver);
}

final class PostgreSQLDriver: DbDriver
{
	mixin DbDriverMixin!(PGconn*, PostgreSQLResult);

	bool hasFeature(Database.Feature f)
	{
		switch (f)
		{
			case Database.Feature.blob:
			case Database.Feature.cursors:
			case Database.Feature.transactions:
			case Database.Feature.resultSize:
			case Database.Feature.lastInsertId:
			case Database.Feature.preparedQueries:
				return true;
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
		uri ~= " port="   ~ (_uri.port ? _uri.port.to!string : "5432");
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
			exec("SET CLIENT_ENCODING TO 'UNICODE'");
			exec("SET DATESTYLE TO 'ISO'");
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
			PQfinish(_handle);
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

		auto result = PQexec(_handle, toStringz(query));
		switch(PQresultStatus(result))
		{
			case ExecStatusType.PGRES_COMMAND_OK:
			case ExecStatusType.PGRES_TUPLES_OK:
				PQclear(result);
				return true;
				default:
		}
		errorTake(DbError.Type.transaction);
		PQclear(result);
		return false;
	}

	private void errorTake(DbError.Type t)
	{
		_error = DbError(t, to!string(PQerrorMessage(_handle)));
	}
}

final class PostgreSQLResult: DbResult
{
	mixin DbResultMixin!(PGresult*, PostgreSQLDriver);
	private
	{
		bool        _fetch;
		Oid[]       _fieldsTypes;
	}

    @property Variant lastInsertId()
	{
		if (isActive)
		{
			Oid id = PQoidValue(_handle);
			if (id) // not InvalidOid
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
			return to!ulong(to!string(PQcmdTuples(_handle)));
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
		queryIdClear();
		queryIdGen();

		_query = query;

//        bool hasIndexes = false;
//        bool hasStrings = false;
        foreach(c; match(query, regexDbParam)) {
            auto token = c[0], key = c[1];
            if (!_paramsTokens.count(token)) {
                _paramsTokens ~= token;
                _paramsKeys   ~= key;
            }
            query = query.replace(token, "$" ~ to!string(_paramsTokens.countUntil(token) + 1));
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

        dbDebug("%s.prepare: %s\nReal query: %s\nQueryID: %s\nPrepared: %s", typeid(this), _query, query, _queryId, _isPrepared);

        PQclear(pgResult);
        return _isPrepared;
    }

	bool exec(string query, Variant[string] params = null)
	{
		_isPrepared = false;

		clear();


		if (!_driver.isOpen)
		{
			return false;
		}

		errorClear();

		if (!params.length)
		{
			dbDebug("%s.exec: %s", typeid(this), query);

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
		if (!_driver.isOpen || !isPrepared)
		{
			return false;
		}

		clear();

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
        dbDebug("%s.execPrepared  QueryID: %s, Params: %s", typeid(this), _queryId, params);
        _handle = PQexecPrepared(_driver._handle,
        	cast(char*)toStringz(_queryId),
            nParams,
            values.ptr,
            lengths.ptr,
            formats.ptr,
            0);
        return takeResult();
    }


	bool fetch()
	{
		_fieldsValues = null;

		if (!isActive)
		{
			return false;
		}
		
		if (_row >= _length)
		{
			return false;
		}

		foreach(i, t; _fieldsTypes)
		{
			if (PQgetisnull(_handle, cast(int)(_row), cast(int)(i)))
			{
				_fieldsValues ~= Variant(null);
				continue;
			}
			auto str = to!string(cast(char*)(PQgetvalue(_handle, cast(int)(_row), cast(int)(i))));
			switch (t)
			{
				case Type.BOOLOID:
					_fieldsValues ~= Variant(str == "t");
					continue;
				case Type.INT2OID:
				case Type.INT4OID:
					_fieldsValues ~= Variant(to!int(str));
					continue;
				case Type.INT8OID:
					_fieldsValues ~= Variant(to!int(str));
					continue;
				case Type.FLOAT4OID:
				case Type.FLOAT8OID:
					_fieldsValues ~= Variant(to!double(str));
					continue;
				case Type.NUMERICOID:
					_fieldsValues ~= Variant(to!real(str));
					continue;
				case Type.DATEOID:
					_fieldsValues ~= Variant(Date.fromISOExtString(str));
					continue;
				case Type.TIMESTAMPOID:
					_fieldsValues ~= Variant(SysTime.fromISOExtString(str.replace(" ", "T")));
					continue;
				case Type.TIMESTAMPTZOID:
					_fieldsValues ~= Variant(SysTime.fromISOExtString(str.replace(" ", "T")));
					continue;
				case 1015:
					_fieldsValues ~= Variant(str[1 .. $ - 1].split(","));
					continue;
				case Type.CHAROID:
				case Type.VARCHAROID:
				case Type.TEXTOID:
				default:
					_fieldsValues ~= Variant(str);
			}
		}
		return true;
	}

	void clear()
	{
		if (_handle !is null)
		{
			PQclear(_handle);
			_handle = null;
		}
		cleanup(isPrepared);
	}

	private bool takeResult()
	{
		if (!isActive)
		{
			return false;
		}
		switch(PQresultStatus(_handle))
		{
			case ExecStatusType.PGRES_COMMAND_OK:
				return true;
			case ExecStatusType.PGRES_TUPLES_OK:
				_length        = PQntuples(_handle);
				_fieldsCount   = PQnfields(_handle);
				for (ulong i = 0; i < _fieldsCount; ++i)
				{
					auto fName  = to!string(PQfname(_handle, cast(int) i));
					_fieldsTypes ~= PQftype(_handle, cast(int) i);
					_fieldsNames ~= fName;
					_fieldsMap[fName] = i;
				}
				if (_length)
				{
					fetch();
//					_firstFetched = false;
				}
				return true;
			default:
		}
		errorTake(DbError.Type.statement);
		return false;
	}

	private void errorTake(DbError.Type t)
	{
		_error = DbError(t, to!string(PQerrorMessage(_driver._handle)));
	}

	private void queryIdClear()
	{
		if (!_queryId.length)
		{
			return;
		}

		_driver.exec("DEALLOCATE " ~ _queryId);

		_queryId.length = 0;
	}

	private void queryIdGen()
	{
		_queryId = "qid_" ~ to!string(randomUUID())[0 .. 8];
	}

	private string formatValue(Variant v)
	{
		if (v.type == typeid(null))
		{
			return "NULL";
		}

		if (v.type == typeid(bool))
		{
			return v.get!bool ? "TRUE" : "FALSE";
		}

		return to!string(v);
	}
}


enum Type {
      BOOLOID  = 16,
      BYTEAOID = 17,
      CHAROID  = 18,
//      NAMEOID   19
      INT8OID  = 20,
      INT2OID  = 21,
      INT2VECTOROID = 22,
      INT4OID  = 23,
//      REGPROCOID   24
      TEXTOID  = 25,
//      OIDOID   26
//      TIDOID   27
//      XIDOID   28
//      CIDOID   29
//      OIDVECTOROID   30
      JSONOID = 114,
//         XMLOID   142
//         PGNODETREEOID   194
//         POINTOID   600
//         LSEGOID   601
//         PATHOID   602
//         BOXOID   603
//         POLYGONOID   604
//         LINEOID   628
      FLOAT4OID = 700,
      FLOAT8OID = 701,
//      ABSTIMEOID   702
//      RELTIMEOID   703
//      TINTERVALOID   704
//      UNKNOWNOID   705
//      CIRCLEOID   718
//      CASHOID   790
//      MACADDROID   829
//      INETOID   869
//      CIDROID   650
      INT2ARRAYOID = 1005,
      INT4ARRAYOID = 1007,
      TEXTARRAYOID = 1009,
//      OIDARRAYOID   1028
      FLOAT4ARRAYOID = 1021,
//      ACLITEMOID   1033
//      CSTRINGARRAYOID   1263
//      BPCHAROID   1042
      VARCHAROID = 1043,
      DATEOID = 1082,
      TIMEOID = 1083,
      TIMESTAMPOID = 1114,
      TIMESTAMPTZOID = 1184,
//      INTERVALOID   1186
//      TIMETZOID   1266
//      BITOID   1560
//      VARBITOID   1562
      NUMERICOID = 1700,
//      REFCURSOROID   1790
//      REGPROCEDUREOID   2202
//      REGOPEROID   2203
//      REGOPERATOROID   2204
//      REGCLASSOID   2205
//      REGTYPEOID   2206
//       REGTYPEARRAYOID   2211
//      UUIDOID   2950
//      LSNOID   3220
//      TSVECTOROID   3614
//      GTSVECTOROID   3642
//      TSQUERYOID   3615
//      REGCONFIGOID   3734
//      REGDICTIONARYOID   3769
      JSONBOID = 3802,
//      INT4RANGEOID   3904
//      RECORDOID   2249
//      RECORDARRAYOID   2287
//      CSTRINGOID   2275
//      ANYOID   2276
//      ANYARRAYOID   2277
//      VOIDOID   2278
//      TRIGGEROID   2279
//      EVTTRIGGEROID   3838
//      LANGUAGE_HANDLEROID   2280
//      INTERNALOID   2281
//      OPAQUEOID   2282
//      ANYELEMENTOID   2283
//      ANYNONARRAYOID   2776
//      ANYENUMOID   3500
//      FDW_HANDLEROID   3115
//      ANYRANGEOID   3831
}