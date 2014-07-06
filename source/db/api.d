module db.api;

public import std.variant;
public import db.uri;

import std.algorithm;
import std.conv;
import db.interfaces;

DbDriverCreator[] DbDriverCreators;

/// DbError
struct DbError
{
  enum Type
    {
        none        = 0,
        pool        = 1,
        driver      = 2,
        connection  = 10,
        statement   = 11,
        transaction = 12,
        unknown     = 0xFFFF,
    }

    private
    {
        Type    _type = DbError.Type.none;
        int     _code = -1;
        string  _text;
    }

    this(DbError.Type type, string driverText = "", string dbText = "", int code = -1)
    {
        _type = type;
        _text = driverText ~ dbText;
        _code = code;
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
}


/// DbQuery
class DbQuery
{
    private
    {
        DbResult  _result;
        DbError   _error;
        string[]  _fieldsNames = [];
    }

    private this(Database db, string query = "")
    {
        if (db._driver is null)
        {
            _error = DbError(DbError.Type.unknown, "Invalid database, no driver or unknown pool");
            return;
        }

        _result = db._driver.result;

        if (query.length)
        {
            prepare(query);
        }
    }

    @property auto length() const
    {
        return _result is null ? 0 : _result.length;
    }
    @property auto error()  const { return _result is null ? _error : _result.error; }
    @property auto result() { return _result; }
    @property auto fieldsCount()  { return _result is null ? 0  : _result.fieldsCount; }
    @property auto fieldsNames()  { return _result is null ? [] : _result.fieldsNames; }
    @property auto lastInsertId() { return _result is null ? Variant() : _result.lastInsertId; }
//    @property string lastQuery() {
//    return _result is null ? "" : _result.lastQuery;
//  }
    @property auto rowsAffectedCount() { return _result is null ? 0 : _result.rowsAffectedCount; }

    @property auto numPrecision() { return _result.numPrecision; }
    @property auto numPrecision(Database.NumPrecision p) {
        return _result.numPrecision(p);
    }
  auto opIndex(ulong index) { return _result.opIndex(index); }
  auto opIndex(string name) { return _result.opIndex(cast(ulong)(_fieldsNames.countUntil(name))); }
  void clear() {
    if (_result !is null) {
      _result.clear();
    }
  }

  bool prepare(string query)  { return _result is null ? false : _result.prepare(query); }
  bool exec(Variant[] params) {
    Variant[string] tmp;
    auto len = params.length;
    for(int i = 0; i < len; ++i) {
      tmp[to!string(i)] = params[i];
    }
    return exec(tmp);
  }
  bool exec(Variant[string] params = (Variant[string]).init) {
    _fieldsNames.length = 0;
    auto result = _result is null ? false : _result.exec(params);
    if (result) {
      _fieldsNames = _result.fieldsNames;
    }
    return result;
  }
  bool exec(string query, Variant[] params) { return prepare(query) && exec(params); }
  bool exec(string query, Variant[string] params = (Variant[string]).init) {
    return prepare(query) && exec(params);
  }
  bool seek(long index, bool relative = false) { return _result is null ? false : _result.seek(index, relative); }
  bool first()    { return _result is null ? false : _result.first();    }
  bool previous() { return _result is null ? false : _result.previous(); }
  bool next()     { return _result is null ? false : _result.next(); }
  bool last()     { return _result is null ? false : _result.last(); }
  bool nextSet()  { return _result is null ? false : _result.nextSet(); }
  int opApply(scope int delegate(ref DbQuery) dg) {
    int  result;
    auto len = length;
    for (size_t i = 0; i < len; ++i) {
       next();
       result = dg(this);
       if (result)
         break;
    }
    return result;
  }
}


/// Databse
class Database {
      enum Feature
      {
          unicode  = 0,
        resultSize = 1,
        blob = 2,
        lastInsertId = 3,
        transactions = 4,
        cursors = 5,
        preparedQueries = 6,
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
        DbError          _error;
        DbPool.Connect*  _connect;
        NumPrecision     _precision;
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
        if (_driver is null) {
            _error = DbError(DbError.Type.pool, "Driver '" ~ s ~ "' not found");
        }
    }

    this(string uri) {
        this(URI(uri));
    }

    ~this() {
        if (_connect != null) {
            _connect.busy = false;
        } else {
            delete _driver;
        }
    }

    @property auto poolId()  const
    {
        return _poolId;
    }
      @property auto isOpen()  const
      {
          return _driver is  null ? false : _driver.isOpen;
      }
      @property auto isValid() const
      {
          return _driver !is null;
      }
      @property auto uri()     const
      {
          return _uri;
      }
      @property auto error() const
      {
          return _driver is null ? _error : _driver.error;
      }
      @property auto driver()
      {
          return _driver;
      }
      @property auto numPrecision()
      {
          return _driver is null ? NumPrecision.f64 : _driver.result.numPrecision;
      }
      @property auto numPrecision(Database.NumPrecision p)
      {
        return _driver is null ? numPrecision.common : _driver.result.numPrecision(p);
    }

    bool hasFeature(Database.Feature f)
    {
        return _driver is null ? false : _driver.hasFeature(f);
    }

    bool  transaction()
    {
        return _driver is null ? false : _driver.transactionBegin();
    }

    bool commit()
    {
        return _driver is null ? false : _driver.transactionCommit();
    }

    bool rollback() {
        return _driver is null ? false : _driver.transactionRollback();
    }

    bool open(string username = "", string password = "")
    {
        return _driver is null ? false : _driver.open(_uri);
    }

    bool close()
    {
        auto result = false;
        if (_connect != null)
        {
            _error = DbError(DbError.Type.pool, "Can't close connection in pool");
        }
        else
        {
            if (_driver !is null) {
                _driver.close();
            }
            result = true;
        }
        return result;
    }

    DbQuery query(string query = "") {
        auto q = new DbQuery(this, query);
        return q;
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
            DbDriverCreator    creator;
            uint            maxCon;
            Connect*[]      connections;
        };
        Pool*[string]     _pools;
        DbError           _error;
    }

    @property error()
    {
        return _error;
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
        if (creator is null) {
            _error = DbError(DbError.Type.pool, "Driver '" ~ s ~ "' not found");
            return false;
          }
        _pools[id] = new Pool(id, uri, creator, maxCon);
        return true;
    }
    bool del(string id)
    {
        return false;
    }

    Database db(string id) {
        auto pool = id in _pools;
        if (pool is null)
        {
              auto db = Database("");
              db._error  = DbError(DbError.Type.pool, "Pool '" ~ id ~ "' not found");
              db._poolId = id;
              return db;
          }
        Connect* connect;
        foreach (conn; (*pool).connections)
        {
              if (conn.busy)
              {
                continue;
            }
              conn.busy = true;
              connect   = conn;
          }
        if (connect is null && (!(*pool).maxCon || (*pool).maxCon > (*pool).connections.length)) {
              (*pool).connections ~= new Connect(true, (*pool).creator.create());
              connect = (*pool).connections[$ - 1];
          }
        if (connect != null) {
              return new Database(id, (*pool).uri, connect);
          }
        auto db = Database("");
        db._uri    = (*pool).uri;
        db._poolId = id;
        db._error  = DbError(DbError.Type.pool, "Pool '" ~ id ~ "' is busy");
        return db;
    }
}