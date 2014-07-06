module db.interfaces;

public import db.api;
public import db.versioning;

import std.regex;

auto regexDbParam = ctRegex!(`\{(\w+)\}`, "g");

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
    @property void* handle();
    @property string name() const;
    @property DbError error() const;
    @property DbResult result();

    bool hasFeature(Database.Feature);
    bool transactionBegin();
    bool transactionCommit();
    bool transactionRollback();

    bool open(URI uri);
    void close();
}

interface DbResult
{
    alias Database.NumPrecision NumPrecision;
    @property ulong length() const;
    @property ulong rowsAffectedCount() const;
    @property ulong fieldsCount() const;
    @property DbError  error()  const;
    @property string[] fieldsNames();
    @property Variant  lastInsertId();
    @property NumPrecision numPrecision() const;
    @property NumPrecision numPrecision(Database.NumPrecision p);

    bool prepare(string query);
    bool exec(Variant[string] params = (Variant[string]).init);
    void clear();

    bool seek(long index, bool relative = false);
    bool first();
    bool previous();
    bool next();
    bool last();
    bool nextSet(); 

    Variant opIndex(ulong index);
}

mixin template DbDriverMixin()
{
    private
    {
        Version           _version;
        URI               _uri;
        DbDriverCreator   _creator;
        DbError           _error;
    }

    @property string name() const
    {
        return _creator.name;
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
        bool            _firstFetch;
        ulong           _row;
        ulong           _length;
        ulong           _fieldsCount;
        ulong           _affectedCount;
        DbError         _error;
        string[]        _fieldsNames = [];
        string[]        _paramsTokens;
        string[]        _paramsKeys;
        NumPrecision	_precision;
    }

    @property DbError error() const
    {
        return _error;
    }

    @property ulong length() const
    {
        return _length;
    }

    @property ulong rowsAffectedCount() const
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

  	@property NumPrecision numPrecision() const {
        return _precision;
    }

    @property Database.NumPrecision numPrecision(Database.NumPrecision p) {
        return _precision = p;
    }

    bool seek(long pos, bool relative = false)
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
private:
    void cleanup() {
        _row      = 0;
        _length   = 0;
        _firstFetch   = false;
        _fieldsCount  = 0;
        _fieldsTypes.length  = 0;
        _paramsTokens.length = 0;
        _paramsKeys.length   = 0;  
        _fieldsNames.length  = 0;
    }

    void errorClear() {
        if (_error.type != DbError.Type.none) {
            _error = DbError(DbError.Type.none);
        }
    }

    void checkForError(string txt, bool ok, DbError.Type t = DbError.Type.statement) {
        if (!ok) {
            errorTake(t, txt);
        }
    }
}