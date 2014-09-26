module db.interfaces;

public import db.api;
public import db.versioning;

import std.regex;

auto regexDbParam = ctRegex!(`\$\{(\w+)\}`, "g");

interface DbDriverCreator
{
    DbDriver  create();
    @property string   name() const;
    @property string[] aliases() const;
}

interface DbDriver
{
    alias Database.Feature Feature;
    @property bool isOpen() const;
    @property bool isPrepared() const;
    @property void* handle();
    @property string name() const;
    @property string lastQuery() const;
    @property DbError error() const;
    @property DbResult result();

    bool hasFeature(Database.Feature);
    bool transactionBegin();
    bool transactionCommit();
    bool transactionRollback();

    bool prepare(string query);
    bool exec(string query);
    bool exec(Variant[string] params = (Variant[string]).init);
    void clear();
    
    bool open(URI uri);
    void close();
}

interface DbResult
{
    alias Database.NumPrecision NumPrecision;

    @property uint length() const;
    @property uint rowsAffectedCount() const;
    @property uint fieldsCount() const;
    @property string[] fieldsNames();
    @property string   query() const;
    @property Variant  lastInsertId();
    @property NumPrecision numPrecision() const;
    @property NumPrecision numPrecision(Database.NumPrecision p);

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
        string              _lastQuery;
        string[]            _paramsTokens;
        string[]            _paramsKeys;
    }

    @property bool isPrepared() const
    {
        return _isPrepared;
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

    @property DbResult result()
    {
        return _result;
    }

    @property string name() const
    {
        return _creator.name;
    }

    @property string lastQuery() const
    {
        return _lastQuery;
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
    private void cleanup() {
        _paramsTokens.length = 0;
        _paramsKeys.length   = 0;  
    }
}

mixin template DbResultMixin()
{
    alias Database.NumPrecision NumPrecision;
    private
    {
        bool            _firstFetch;
        uint            _row;
        uint            _length;
        uint            _fieldsCount;
        uint            _affectedCount;
        DbError         _error;
        string          _query;
        string[]        _fieldsNames = [];
        NumPrecision	_precision;
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
}