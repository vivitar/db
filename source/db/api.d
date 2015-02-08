module db.api;

import core.vararg;

public import std.variant;
public import db.uri;

import std.algorithm;
import std.conv;
import db.interfaces;


version (DbDebug)
{
	import std.stdio: writefln;
}

DbDriverCreator[] DbDriverCreators;

class DbException: Exception
{
	enum Type: ubyte 
	{
		none        = 0x00,
		pool        = 0x01,
		driver      = 0x02,
		connection  = 0x10,
		statement   = 0x11,
		transaction = 0x12,
		unknown     = 0xFF,
	}

	private
	{
		Type    _type;
		string  _msg;
	}

	@property Type type() const pure nothrow
	{
		return _type;
	}

	@property string msg() const pure nothrow
	{
		return _msg;
	}

	this() @safe pure nothrow
	{
		super("Db Exception");
	}

	this(Type type, string msg) @safe pure nothrow
	{
		super("Db Exception: " ~ msg);
		_type = type;
		_msg  = msg;
	}
}

pure void enforceDb(bool chk, DbException.Type type, lazy string msg)
{
	if (!chk)
	{
		throw new DbException(type, msg);
	}
}

/// DbError
struct DbError
{
	alias DbException.Type Type;

	private
	{
		Type    _type = Type.none;
		int     _code = -1;
		string  _text;
	}

    @property auto isNoError() const
    {
        return _type == DbError.Type.none;
    }

    @property auto code() const
    {
        return _code;
    }

    @property auto type() const
    {
        return _type;
    }

    @property auto text() const
    {
        return _text;
    }
    
    this(DbError.Type type, string driverText = "", string dbText = "", int code = -1)
    {
        _type = type;
        _text = driverText ~ dbText;
        _code = code;
    }
}

/// Database
class Database
{
	enum Feature
	{
		resultSize         = 1,
		blob               = 2,
		lastInsertId       = 3,
		transactions       = 4,
		cursors            = 5,
		preparedQueries    = 6,
		multipleResultSets = 20
	}

	enum NumPrecision
	{
		f32,
		f64,
		f128,
		numeric,
		common = f64
	};

	private
	{
		string           _poolId;
		URI              _uri;
		DbDriver         _driver;
		DbPool.Connect*  _connect;
	}

	static bool regDriver(DbDriverCreator creator)
	{
		version (DbDebug)
		{
			writefln("Database.regDriver \"%s\", aliases: %s", creator.name, creator.aliases);
		}
		DbDriverCreators ~= creator;
		return true;
	}

	static Database opCall(string uri)
	{
		return new Database(uri);
	}

	private this(string id, URI uri, DbPool.Connect* connect)
	{
		_poolId  = id;
		_uri     = uri;
		_connect = connect;
		_driver  = connect.driver;
	}

	this(string uri)
	{
		version (DbDebug)
		{
			writefln("Database.this(%s)", uri);
		}
		URI  u = uri;
		auto s = u.scheme;
		foreach (c; DbDriverCreators)
		{
			if (s == c.name || count(c.aliases, s))
			{
				_driver = c.create();
				break;
			}
		}
		_uri = uri;
		enforceDb(_driver !is null, DbError.Type.driver, "Driver '" ~ s ~ "' not found");
	}

	~this()
	{
		version (DbDebug)
		{
			writefln("Database.~this");
		}
		if (_connect !is null)
		{
			_connect.busy = false;
		}
	}

	@property auto poolId() pure const
	{
		return _poolId;
	}

	@property auto isOpen()  const
	{
		return _driver.isOpen;
	}

	@property pure auto uri() const
	{
		return _uri;
	}

    @property DbError error() const
    {
        return _driver.error;
    }

    @property pure DbDriver driver()
    {
        return _driver;
    }

//    @property auto numPrecision()
//    {
//        return _driver.result.numPrecision;
//    }
//
//    @property auto numPrecision(Database.NumPrecision p)
//    {
//        return _driver.result.numPrecision(p);
//    }

	bool hasFeature(Database.Feature f)
	{
		return _driver.hasFeature(f);
	}

	bool transaction()
	{
		version (DbDebug)
		{
			writefln("Database.transaction");
		}
		return _driver.transactionBegin();
	}

	bool commit()
	{
		version (DbDebug)
		{
			writefln("Database.commit");
		}
		return _driver.transactionCommit();
	}

	bool rollback()
	{
		version (DbDebug)
		{
			writefln("Database.rollback");
		}
		return _driver.transactionRollback();
	}

	bool open()
	{
		if (isOpen)
		{
			version (DbDebug)
			{
				writefln("Database.open (Already open, closing)");
			}
			close();
		}
		auto r = _driver.open(_uri);
		version (DbDebug)
		{
			writefln("Database.open -> %s", r);
		}
		return r;
	}

	void close()
	{
		version (DbDebug)
		{
			writefln("Database.close (%s)", &this);
		}
		_driver.close();
	}
}

class Query
{
	private
	{
		Database	_db;
		DbResult	_result;
	}

	@property DbError error() const
	{
		return _db._driver.error;
	}

	this(Database db)
	{
		version (DbDebug)
		{
			writefln("Query.this");
		}
		_db     = db;
		_result = db._driver.mkResult();
	}

	~this()
	{
		version (DbDebug)
		{
			writefln("Query.~this");
		}
//		_result.destroy();
	}

	bool exec(A...)(string query, A args)
	{
		auto params = variantArray(args);
		Variant[string] tmp;

		foreach (i; 0 .. params.length)
		{
			tmp[to!string(i)] = params[i];
		}
		return exec(query, tmp);
	}

	bool exec(string query, Variant[string] params)
	{
		version (DbDebug)
		{
			writefln("Query.exec: \"%s\"\nParams: %s", query, params);
		}
		return _result.exec(query, params);
	}

	bool prepare(string query)
	{
		return _result.prepare(query);
	}

	bool execPrepared(A ...)(A args)
	{
		auto params = variantArray(args);
		Variant[string] tmp;

		foreach (i; 0 .. params.length)
		{
			tmp[to!string(i)] = params[i];
		}
		return execPrepared(tmp);
	}

	bool execPrepared(Variant[string] params)
	{
		version (DbDebug)
		{
			writefln("Query.execPrepared: \"%s\"\nParams: %s", _result.query, params);
		}
		return _result.execPrepared(params);
	}

	DbResult result()
	{
		return _result;
	}
}


class DbPool {
    alias Database.regDriver regDriver;

    private {
        struct Connect {
            bool      busy;
            DbDriver  driver;
        };
        struct Pool
        {
            string          id;
            URI             uri;
            DbDriverCreator creator;
            uint            maxCon;
            Connect*[]      connections;
        };
        Pool[string]        _pools;
    }

    bool add(string id, string uri, uint maxCon = 0)
    {
        URI  u = uri;
        auto s = u.scheme;
        DbDriverCreator creator;
        foreach (c; DbDriverCreators)
        {
            if (s == c.name || count(c.aliases, s))
            {
                creator = c;
                break;
            }
        }

        enforceDb(creator !is null, DbError.Type.driver, "Driver '" ~ s ~ "' not found");

        _pools[id] = Pool(id, u, creator, maxCon);

        return true;
    }

//    bool del(string id)
//    {
//        return false;
//    }

    Database db(string id)
    {
        auto pool = id in _pools;
        
        enforceDb(pool !is null, DbError.Type.pool, "Pool '" ~ id ~ "' not found");

        Connect* connect;
        foreach (conn; pool.connections)
        {
              if (conn.busy)
              {
                continue;
              }
              conn.busy = true;
              connect   = conn;
          }
        if (connect is null && (!pool.maxCon || pool.maxCon > pool.connections.length))
        {
            pool.connections ~= new Connect(true, pool.creator.create());
            connect = pool.connections[$ - 1];
        }
        enforceDb(connect !is null, DbError.Type.pool, "Pool '" ~ id ~ "' is busy");
        return new Database(id, (*pool).uri, connect);
    }
}