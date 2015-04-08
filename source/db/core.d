module db.core;

public import db.api;
public import db.versioning;

import std.regex;

auto regexDbParam = ctRegex!(`\$\{(\w+)\}`, "g");


version (USE_DB_DEBUG)
{
	import std.stdio: writefln;
}

void dbDebug(A...)(lazy A args)
{
	version (USE_DB_DEBUG)
	{
		writefln(args);
	}
}

interface DbDriverCreator
{
	DbDriver  create();
	@property string   name() const pure nothrow;
	@property string[] aliases() const pure nothrow;
}

interface DbDriver
{
	alias Database.Feature Feature;
	@property bool isOpen() const;
	@property void* handle();
	@property string name() const;
	@property DbError error() const;

	bool hasFeature(Database.Feature);

	bool transactionBegin();
	bool transactionCommit();
	bool transactionRollback();

	bool open(URI uri);
	void close();

	DbResult mkResult();
}

interface DbResult
{
	alias Database.NumPrecision NumPrecision;

	@property bool isActive()   const;
	@property bool isPrepared() const;
	@property void* handle();
	@property ulong length() const;
	@property ulong affectedRowsLength();
	@property ulong fieldsCount() const;
	@property string[] fieldsNames();
	@property string   query() const;
	@property Variant  lastInsertId();
	@property DbError  error() const;
	@property NumPrecision numPrecision() const;
	@property NumPrecision numPrecision(Database.NumPrecision p);

	bool exec(string query, Variant[string] params = null);
	bool prepare(string query);
	bool execPrepared(Variant[string] params = null);
	void clear();

	bool seek(long index, bool relative = false);
	bool first();
	bool previous();
	bool next();
	bool last();
	bool nextSet(); 

	Variant opIndex(ulong  index);
	Variant opIndex(string name);

	int opApply(scope int delegate(DbResult) dg);
}

mixin template DbDriverCreatorMixin(string N, string[] A, D)
{
	@property string name() const pure nothrow
	{
		return N;
	}

	@property string[] aliases() const pure nothrow
	{
		return A;
	}

	DbDriver create()
	{
		dbDebug("%s.create -> %s", typeid(this), D.stringof);
		return new D(this);
	}
}

mixin template DbDriverMixin(H, R)
{
	private
	{
		bool                _isPrepared;
		Version             _version;
		URI                 _uri;
		DbDriverCreator     _creator;
		DbError             _error;
		H                   _handle;
		R[]                 _results;
	}

	@property bool isOpen() const
	{
		return _handle !is null;
	}

	@property void* handle()
	{
		return cast(void*)(_handle);
	}

	@property DbError error() const
	{
		return _error;
	}

	@property string name() const
	{
		return _creator.name;
	}

	bool transactionBegin()
	{
		dbDebug("%s.transactionBegin", typeid(this));
		return !hasFeature(Feature.transactions) ? false : exec("BEGIN");
	}

	bool transactionCommit()
	{
		dbDebug("%s.transactionCommit", typeid(this));
		return !hasFeature(Feature.transactions) ? false : exec("COMMIT");
	}

	bool transactionRollback()
	{
		dbDebug("%s.transactionRollback", typeid(this));
		return !hasFeature(Feature.transactions) ? false : exec("ROLLBACK");
	}

	DbResult mkResult()
	{
		dbDebug("%s.mkResult", typeid(this));
		auto result = new R(this);
		_results ~= result;
		return result;
	}

	this(DbDriverCreator creator)
	{
		dbDebug("%s.this", typeid(this));
		_creator = creator;
	}

	~this()
	{
		dbDebug("%s.~this", typeid(this));
		close();
	}

	private void errorClear()
	{
		if (_error.type != DbError.Type.none)
		{
			_error = DbError(DbError.Type.none);
		}
	}
}

mixin template DbResultMixin(H, D)
{
	alias Database.NumPrecision NumPrecision;
	private
	{
		bool            _isPrepared;
		bool            _firstFetched;
		ulong           _row;
		ulong           _length;
		ulong           _fieldsCount;
		ulong           _affectedCount;
		DbError         _error;
		string          _query;
		string          _queryId;
		string[]        _fieldsNames;
		ulong[string]   _fieldsMap;
		Variant[]   	_fieldsValues;
		string[]        _paramsTokens;
		string[]        _paramsKeys;
		NumPrecision	_precision;
		H               _handle;
		D               _driver;
	}

    @property bool isActive() const
    {
        return _driver.isOpen && _handle !is null;
    }
    @property bool isPrepared() const
    {
        return _isPrepared;
    }

    @property void* handle()
    {
        return cast(void*)(_handle);
    }

    @property ulong length() const
    {
        return _length;
    }

    @property DbError error() const
    {
        return _error;
    }

    @property ulong affectedRowsLength()
    {
        return _affectedCount;
    }

    @property ulong fieldsCount() const
    {
        return _fieldsCount;
    }

    @property string[] fieldsNames()
    {
        return _fieldsNames;
    }

    @property string query() const
    {
        return _query;
    }

    @property NumPrecision numPrecision() const {
        return _precision;
    }

    @property NumPrecision numPrecision(NumPrecision p)
    {
        return _precision = p;
    }

	this(D  driver)
	{
		dbDebug("%s.this", typeid(this));
		_driver = driver;
	}

	~this()
	{
		dbDebug("%s.~this", typeid(this));
	}

	bool exec(string query, Variant[string] params = null)
	{
		dbDebug("%s.exec Query: %s, Params: %s", typeid(this), query, params);
		auto ok = prepare(query);
		if (ok)
		{
			ok = execPrepared(params);
		}
		return ok;
	}

	bool seek(long pos, bool relative = false)
	{
		if (!_driver.hasFeature(Database.Feature.cursors))
		{
			if (!relative || pos != +1)
			{
				return false;
			}
		}
		else if (_length == 0)
		{
			return false;
		}

		if (relative)
		{
			if (!_firstFetched && pos == +1)
			{
			}
			else
			{
				_row += pos;
			}
		}
		else if (pos < 0)
		{
			return false;
		}
		else
		{
			_row = pos;
		}
		_firstFetched = true;
		return fetch();
    }

    bool first()
    {
		dbDebug("%s.first", typeid(this));
        return seek(0); 
    }

    bool previous()
    {
    	dbDebug("%s.previous", typeid(this));
        return seek(-1, true);
    }

    bool next()
    {
    	dbDebug("%s.next", typeid(this));
        return seek(+1, true);
    }

    bool last()
    {
    	dbDebug("%s.last", typeid(this));
        return seek(_length - 1);
    }

    bool nextSet()
    {
    	dbDebug("%s.nextSet", typeid(this));
        return false;
    }

	Variant opIndex(ulong index)
	{
		if (!isActive || index >= _fieldsValues.length)
		{
			return Variant(null);
		}
		return _fieldsValues[index];
	}

	Variant opIndex(string name)
	{
		auto index = name in _fieldsMap;
		if (index !is null)
		{
			return opIndex(*index);
		}
		return Variant();
	}
	
	int opApply(scope int delegate(DbResult) dg)
	{
		int  result;
		while (next())
		{
			result = dg(cast(DbResult) this);
			if (result)
				break;
		}
		return result;
	}

	private void cleanup(bool savePrepared)
	{
		if (!savePrepared)
		{
			_query.length = 0;
			_isPrepared   = false;	
			_paramsTokens.length = 0;
			_paramsKeys.length   = 0; 
		}

		_row    = 0;
		_length = 0;
		_fieldsCount   = 0;
		_affectedCount = 0;
		_fieldsTypes.length  = 0;
		_fieldsNames.length  = 0;
		_fieldsMap  = null;
		_firstFetched = false;
	}

	private void errorClear()
	{
		if (_error.type != DbError.Type.none)
		{
			_error = DbError(DbError.Type.none);
		}
	}
}


