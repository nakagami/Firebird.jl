# Firebird.jl

A Julia interface to the Firebird RDBMS https://firebirdsql.org/ .

It follows the interface of DBInterface https://github.com/JuliaDatabases/DBInterface.jl .

## Example

```
using Firebird, DBInterface
conn = DBInterface.connect(Firebird.Connection, host, user, password, db_path)

# execute
DBInterface.execute(conn, "INSERT INTO some_tbale(...) VALUES (...)")

res = columntable(DBInterface.execute("SELECT * FROM some_table))

# prepared statement and execute
stmt = DBInterface.prepare(conn, raw"SELECT * from foo")
res = columntable(DBInterface.execute(stmt))

```
