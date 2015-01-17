module db.utils;

public import std.variant;

import core.vararg;

static Variant[] args2variant(...)
{
	Variant[] params;

	foreach(i; 0 .. _arguments.length)
	{
		Variant param;
		auto arg = _arguments[i];

		// null
		if (arg == typeid(null))
		{
			param = null;

		}
		// bool
		else if(arg == typeid(bool) || arg == typeid(immutable(bool)) || arg == typeid(const(bool)))
		{
			param = va_arg!bool(_argptr);
		}
		// byte
		else if(arg == typeid(byte) || arg == typeid(immutable(byte)) || arg == typeid(const(byte)))
		{
			param = va_arg!byte(_argptr);
		}
		// short
		else if(arg == typeid(short) || arg == typeid(immutable(short)) || arg == typeid(const(short)))
		{
			param = va_arg!short(_argptr);
		}
		// int
		else if(arg == typeid(int) || arg == typeid(immutable(int)) || arg == typeid(const(int)))
		{
			param = va_arg!int(_argptr);
		}
		// long
		else if(arg == typeid(long) || arg == typeid(immutable(long)) || arg == typeid(const(long)))
		{
			param = va_arg!long(_argptr);
		}
		// float
		else if(arg == typeid(float) || arg == typeid(immutable(float)) || arg == typeid(const(float)))
		{
			param = va_arg!float(_argptr);
		}
		// double
		else if(arg == typeid(double) || arg == typeid(immutable(double)) || arg == typeid(const(double)))
		{
			param = va_arg!double(_argptr);
		}
		// real
		else if(arg == typeid(real) || arg == typeid(immutable(real)) || arg == typeid(const(real)))
		{
			param = va_arg!real(_argptr);
		}
		// string
		else if(arg == typeid(string) || arg == typeid(immutable(string)) || arg == typeid(const(string)))
		{
			param = va_arg!string(_argptr);
		}
		// Unsupported
		else
		{
			assert(0, "Unsupported type: " ~ arg.toString);
		}
		params ~= param;
	}
	return params;
}