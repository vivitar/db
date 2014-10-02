module db.api;

public import std.variant;
public import db.uri;

import std.algorithm;
import std.conv;
import db.interfaces;


debug {
  import std.stdio;
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
    @property auto type() const
    {
        return _type;
    }
    @property auto msg() const
    {
        return _msg;
    }

    @safe pure nothrow this()
    {
        super("Db Exception");
    }

    @safe pure nothrow this(Type type, string msg)
    {
        super("Db Exception: " ~ msg);
        _type = type;
        _msg  = msg;
    }
}

void enforceDb(bool chk, DbException.Type type, string msg)
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

/// Databse
class Database {
    enum Feature
    {
        unicode            = 0,
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
        DbDriverCreators ~= creator;
        return true;
    }

    static Database opCall(URI uri)
    {
        return new Database(uri);
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

    this(string uri) {
        this(URI(uri));
    }

    this(URI uri)
    {
        auto s = uri.scheme;
        foreach (c; DbDriverCreators) {
            if (s == c.name || count(c.aliases, s)) {
                _driver = c.create();
                break;
            }
        }
        _uri = uri;
        enforceDb(_driver !is null, DbError.Type.driver, "Driver '" ~ s ~ "' not found");
    }

    ~this() {
        if (_connect !is null) {
            _connect.busy = false;
        } else {
           _driver.destroy();
        }
    }

    @property auto poolId()  const
    {
        return _poolId;
    }

    @property auto isOpen()  const
    {
        return _driver.isOpen;
    }

    @property auto uri()     const
    {
        return _uri;
    }

    @property auto error() const
    {
        return _driver.error;
    }

    @property auto driver()
    {
        return _driver;
    }

    @property auto numPrecision()
    {
        return _driver.result.numPrecision;
    }

    @property auto numPrecision(Database.NumPrecision p)
    {
        return _driver.result.numPrecision(p);
    }

    bool hasFeature(Database.Feature f)
    {
        return _driver.hasFeature(f);
    }

    bool  transaction()
    {
        return _driver.transactionBegin();
    }

    bool commit()
    {
        return _driver.transactionCommit();
    }

    bool rollback() {
        return _driver.transactionRollback();
    }

    bool open()
    {
        if (isOpen)
        {
            return true;
        }
        return _driver.open(_uri);
    }

    void close()
    {
        enforceDb(_connect is null, DbError.Type.pool, "Can't close connection in pool");
        _driver.close();
    }

    bool prepare(string query)
    {
        return _driver.prepare(query);
    }

    bool exec(Variant[] params)
    {
        Variant[string] tmp;
        auto len = params.length;
        for (int i = 0; i < len; ++i)
        {
            tmp[to!string(i)] = params[i];
        }
        return exec(tmp);
    }

    bool exec(Variant[string] params = (Variant[string]).init)
    {
        return _driver.exec(params);
    }

    bool exec(string query, Variant[] params)
    {
        if (!params.length) {
            return exec(query);
        }
        return prepare(query) && exec(params);
    }

    bool exec(string query, Variant[string] params = (Variant[string]).init)
    {
        if (!params.length) {
            return exec(query);
        }
        return prepare(query) && exec(params);
    }
    DbResult result() {
        return _driver.result;
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

    bool add(string id, URI uri, uint maxCon = 0)
    {
        auto s = uri.scheme;
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

        _pools[id] = Pool(id, uri, creator, maxCon);

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