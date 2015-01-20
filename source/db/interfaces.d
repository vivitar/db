module db.interfaces;

public import db.api;
public import db.versioning;

import std.regex;

auto regexDbParam = ctRegex!(`\$\{(\w+)\}`, "g");

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
    @property uint length() const;
    @property uint rowsAffectedCount() const;
    @property uint fieldsCount() const;
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
    
    bool seek(int index, bool relative = false);
    bool first();
    bool previous();
    bool next();
    bool last();
    bool nextSet(); 

    Variant opIndex(uint index);
    Variant opIndex(string name);

    int opApply(scope int delegate(DbResult) dg);
}

mixin template DbDriverMixin()
{
    private
    {
        bool                _isPrepared;
        Version             _version;
        URI                 _uri;
        DbDriverCreator     _creator;
        DbError             _error;
    }

    @property bool isOpen() const
    {
        return _handle != null;
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
        return !hasFeature(Feature.transactions) ? false : exec("BEGIN");
    }

    bool transactionCommit()
    {
        return !hasFeature(Feature.transactions) ? false : exec("COMMIT");
    }

    bool transactionRollback()
    {
        return !hasFeature(Feature.transactions) ? false : exec("ROLLBACK");
    }

    private void errorClear()
    {
        if (_error.type != DbError.Type.none) {
            _error = DbError(DbError.Type.none);
        }
    }
}

mixin template DbResultMixin()
{
    alias Database.NumPrecision NumPrecision;
    private
    {
    	bool            _isPrepared;
        bool            _firstFetch;
        uint            _row;
        uint            _length;
        uint            _fieldsCount;
        uint            _affectedCount;
        DbError         _error;
        string          _query;
        string          _queryId;
        string[]        _fieldsNames = [];
        string[]        _paramsTokens;
        string[]        _paramsKeys;
        NumPrecision	_precision;
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

    @property uint length() const
    {
        return _length;
    }

    @property DbError error() const
    {
        return _error;
    }

    @property uint rowsAffectedCount() const
    {
        return _affectedCount;
    }

    @property uint fieldsCount() const
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

    @property NumPrecision numPrecision(NumPrecision p) {
        return _precision = p;
    }

    bool seek(int pos, bool relative = false)
    {
        if (_length == 0) {
            return false;
        }
        if (relative) {
            auto newPos = _row;
            if (_firstFetch)
            {
                newPos += pos;
            }
            else
            {
                _firstFetch = true;
            }
            if (newPos >= 0 && newPos < _length)
            {
                _row = newPos;
            }
            else
            {
                return false;
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
        return fetch();
    }

    bool first() {
        _row = 0;
        return seek(0); 
    }

    bool previous() {
        return seek(-1, true);
    }

    bool next() {
        return seek(+1, true);
    }

    bool last() {
        return seek(_length - 1);
    }

    bool nextSet(){
        return false;
    }

    int opApply(scope int delegate(DbResult) dg) {
        int  result;
        auto len = length;
        for (size_t i = 0; i < len; ++i) {
            next();
            result = dg(cast(DbResult) this);
            if (result)
                break;
        }
        return result;
    }

    private void cleanup()
    {
    	_length				 = 0;
        _paramsTokens.length = 0;
        _paramsKeys.length   = 0;  
    }

    private void errorClear()
    {
        if (_error.type != DbError.Type.none) {
            _error = DbError(DbError.Type.none);
        }
    }
}