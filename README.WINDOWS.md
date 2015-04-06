Windows specified configuration
===============================
OBSOLETE

FIXME

PostgreSQL
==========
For example we using dmd 32bit on Windows 64bit

Steps

1. Install PostgreSQL 9.x 32bit (Where 9.x is version current stable is 9.3)
2. Create folder "lib-x32" inner project
3. Copy C:\Program Files (x86)\PostgreSQL\9.x\lib\libpq.lib to the "lib-x32" folder inner project
4. Read about utility http://www.digitalmars.com/ctg/coffimplib.html
5. Download ftp://ftp.digitalmars.com/coffimplib.zip and unzip
6. Run "coffimplib PROJECT\lib-x32\libpq.lib -f" to convert
7. Correct dub.json

lines

    "dependencies": {
        "db":">=0.1.7"
    },
    versions:["USE_POSTGRESQL"],
    "copyFiles-windows-x86":       [
        "C:/Program Files (x86)/PostgreSQL/9.x/lib/libpq.dll",
        "C:/Program Files (x86)/PostgreSQL/9.x/bin/libintl.dll",
    ],
    "sourceFiles-windows-x86" : ["lib-x32/libpq.lib"],
