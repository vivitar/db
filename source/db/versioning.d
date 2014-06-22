module db.versioning;

import std.conv;

class Version {
  enum ReleaseLevel: ubyte {
    Dev,
    Alpha,
    Beta,
    Candidate,
    Release
  };

  this(ulong hash = 0) {
    this(cast(uint)(hash >> 32), cast(uint)(hash & 0xFFFF_FFFF));
  };
  this(uint  ver, uint build) {
    _numeric = ver;
    _build   = build;
    mkStr();
  };

  this(ubyte major, ubyte minor, ubyte micro,
       ReleaseLevel releaseLevel, ubyte releaseSerial = 0, uint build = 0) {
    this(
      (cast(uint)major << 24) | (cast(uint)minor        << 16)  |
      (cast(uint)micro << 8)  | (cast(uint)releaseLevel << 4)   | cast(uint)(releaseSerial & 0x0F)
    ,build);
  }

  @property uint numeric() {
    return _numeric;
  }
  @property string shortString() {
    return _string;
  }
  @property string longString() {
    string s = _string;
    if (_build) {
      s ~= ", build " ~ to!string(_build);
    }
    return s;
  }
  @property uint build()   {
    return _build;
  }

  @property ulong hash() {
    return (cast(ulong)_numeric << 32) | cast(ulong)_build;
  }



private:
  uint    _numeric;
  uint    _build;
  string  _string;

  void mkStr() {
    _string = "";
    _string ~= to!string(cast(ubyte)(_numeric >> 24));
    _string ~= "." ~ to!string(cast(ubyte)(_numeric >> 16));
    auto vMicro = cast(ubyte)(_numeric >> 8);
    auto rLev   = cast(ReleaseLevel)((_numeric >> 4) & 0x0F);
    auto rSer   = cast(ubyte)(_numeric & 0x0F);

    if (vMicro)
      _string ~= "." ~ to!string(vMicro);

    switch(rLev){
    case ReleaseLevel.Dev:
      _string ~= "dev";
      break;
    case ReleaseLevel.Alpha:
      _string ~= "alpha";
      if (rSer > 1){
        _string ~= to!string(rSer);
      }
      break;
    case ReleaseLevel.Beta:
      _string ~= "beta";
      if (rSer > 1){
        _string ~= to!string(rSer);
      }
      break;
    case ReleaseLevel.Candidate:
      _string ~= "rc";
      if (rSer > 1){
        _string ~= to!string(rSer);
      }
      break;
    default:
      break;
    }
  }
};

class VersionCompatibility {
  enum Type {
    EQ,     // ==
    LT,     // <
    LE,     // <=
    GT,     // >
    GE,     // >=
    Range
  };

  this(Type type, const Version ver, const string tag = "") {
  }
  this(const Version ver, const Version verEx, const string tag = "") {
  }

//  bool isCompatible(const Version ver, const string tag = "") {
//    return true;
//  }
//  bool isCompatible(const Version ver, const string tag = "") {
//    return true;
//  }

private:
  Type    _type;
  uint     _version;
  uint     _versionEx;
  string  _display;
  string  _tag;
};
