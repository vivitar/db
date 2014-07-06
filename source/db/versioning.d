module db.versioning;

import std.array;
import std.conv;

struct Version
{
    private
    {
        uint    _hash;
        string  _str;
    }
    enum ReleaseLevel: ubyte {
        dev,
        alpha,
        beta,
        candidate,
        release
    };

    @property uint hash() const
    {
        return _hash;
    }

    @property string toString() const
    {
        return _str;
    }
    
    this(uint hash)
    {
        this(
            cast(ubyte)(hash >> 24),
            cast(ubyte)(hash >> 16),
            cast(ubyte)(hash >> 8),
            cast(ReleaseLevel)((hash >> 4) & 0x0F),
            cast(ubyte)(hash & 0x0F)
        );
    };

    this(ubyte major, ubyte minor, ubyte patch, ReleaseLevel releaseLevel, ubyte releaseSerial = 0)
    {
        auto tmp = appender!string();
        tmp.put(to!string(major));
        tmp.put('.');
        tmp.put(to!string(minor));

        if (patch)
        {
            tmp.put(to!string(patch));
        }

        final switch(releaseLevel)
        {
        case ReleaseLevel.dev:
            tmp.put("dev");
            break;
        case ReleaseLevel.alpha:
            tmp.put("alpha");
            if (releaseSerial > 1) {
                tmp.put(to!string(releaseSerial));
            }
            break;
        case ReleaseLevel.beta:
            tmp.put("beta");
            if (releaseSerial > 1) {
                tmp.put(to!string(releaseSerial));
            }
            break;
        case ReleaseLevel.candidate:
            tmp.put("rc");
            if (releaseSerial > 1) {
                tmp.put(to!string(releaseSerial));
            }
            break;
        case ReleaseLevel.release:
        }
        _str = tmp.data;
    }
};
