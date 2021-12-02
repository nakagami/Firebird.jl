# Firebird.jl

A Julia interface to the Firebird RDBMS https://firebirdsql.org/ .

It follows the interface of DBInterface https://github.com/JuliaDatabases/DBInterface.jl .

## Supported Firebird

Firebird 3.0+ is supported

## Example

```
using Firebird, DBInterface
conn = DBInterface.connect(Firebird.Connection, host, user, password, db_path)

# execute
DBInterface.execute(conn, "INSERT INTO some_tbale(...) VALUES (...)")

res = columntable(DBInterface.execute("SELECT * FROM some_table"))

# execute with parameter
res = columntable(DBInterface.execute("SELECT * FROM some_table where some_column=?", (1, )))

# prepared statement and execute
stmt = DBInterface.prepare(conn, raw"SELECT * FROM some_table")
res = columntable(DBInterface.execute(stmt))

# prepared statement and execute with parameter
stmt = DBInterface.prepare(conn, raw"SELECT * FROM some_table where some_column=?")
res = columntable(DBInterface.execute(stmt, (1, )))
```

## Restriction

Timestamp and Time data type values more detailed than millisecond are truncated.
(It only hold up to milliseconds.)
