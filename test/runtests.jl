################################################################################
# MIT License
#
# Copyright (c) 2021 Hajime Nakagami
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
################################################################################
using Test, Firebird, TimeZones, DBInterface, Tables, Dates, Decimals

const DEBUG_PRIVATE_KEY = big"0x60975527035CF2AD1989806F0407210BC81EDC04E2762A56AFD529DDDA2D4393"
const DEBUG_SALT = hex2bytes("02E268803000000079A478A700000002D1A6979000000026E1601C000000054F")

@testset "connection" begin
    user = if haskey(ENV, "ISC_USER")
        ENV["ISC_USER"]
    else
        "sysdba"
    end
    password = if haskey(ENV, "ISC_PASSWORD")
        ENV["ISC_PASSWORD"]
    else
        "masterkey"
    end

    conn = DBInterface.connect(Firebird.Connection, "localhost", user, password, "/tmp/julia_test.fdb"; create_new=true, timezone="Asia/Tokyo")
    DBInterface.execute(
        conn, raw"""
            CREATE TABLE foo (
                a INTEGER NOT NULL,
                b VARCHAR(30) NOT NULL UNIQUE,
                c VARCHAR(1024),
                d DECIMAL(16,3) DEFAULT -0.123,
                e DATE DEFAULT '1967-08-11',
                f TIMESTAMP DEFAULT '1967-08-11 23:45:01.1234',
                g TIME DEFAULT '23:45:01.1234',
                h BLOB SUB_TYPE 0,
                i DOUBLE PRECISION DEFAULT 0.0,
                j FLOAT DEFAULT 0.0,
                PRIMARY KEY (a),
                CONSTRAINT CHECK_A CHECK (a <> 0)
            )"""
    )
    DBInterface.close!(conn)

    conn = DBInterface.connect(Firebird.Connection, "localhost", user, password, "/tmp/julia_test.fdb")
    DBInterface.execute(
        conn, raw"insert into foo(a, b, c, h) values (1, 'a', 'b', 'This is a pen')")
    DBInterface.execute(
        conn, raw"insert into foo(a, b, c, h) values (2, 'A', 'B', NULL)")

    expected = (
        A = Int64[1, 2],
        B = String["a", "A"],
        C = Union{Missing, String}["b", "B"],
        D = Union{Missing, Decimal}[Decimal(-0.123), Decimal(-0.123)],
        E = Union{Missing, Dates.Date}[Dates.Date("1967-08-11"), Dates.Date("1967-08-11")],
        F = Union{Missing, Dates.DateTime}[Dates.DateTime("1967-08-11T23:45:01.123"), Dates.DateTime("1967-08-11T23:45:01.123")],
        G = Union{Missing, Dates.Time}[Dates.Time("23:45:01.123"), Dates.Time("23:45:01.123")],
        H = Union{Missing, Vector{UInt8}}[Vector{UInt8}("This is a pen"), missing],
        I = Union{Missing, Float64}[Float64(0.0), Float64(0.0)],
        J = Union{Missing, Float32}[Float32(0.0), Float32(0.0)],
    )

    cursor = DBInterface.execute(conn, "SELECT * FROM foo")
    @test eltype(cursor) == Firebird.Row
    @test Tables.istable(cursor)
    @test Tables.rowaccess(cursor)
    @test Tables.rows(cursor) === cursor
    @test Tables.schema(cursor) == Tables.Schema(propertynames(expected), eltype.(collect(expected)))
    @test Base.IteratorSize(typeof(cursor)) == Base.HasLength()
    @test length(cursor) == 2

    row = first(cursor)
    @test Base.IndexStyle(typeof(row)) == Base.IndexLinear()
    @test length(row) == length(expected)
    @test propertynames(row) == collect(propertynames(expected))
    for (i, prop) in enumerate(propertynames(row))
        @test getproperty(row, prop) == row[prop] == row[i] == expected[prop][1]
    end

    res = DBInterface.execute(conn, raw"SELECT * FROM foo where a=?", (1, )) |> columntable
    @test length(res[1]) == 1

    # as a prepared statement
    stmt = DBInterface.prepare(conn, raw"SELECT * FROM foo")
    cursor = DBInterface.execute(stmt)
    @test eltype(cursor) == Firebird.Row
    @test Tables.istable(cursor)
    @test Tables.rowaccess(cursor)
    @test Tables.rows(cursor) === cursor
    @test Tables.schema(cursor) == Tables.Schema(propertynames(expected), eltype.(collect(expected)))
    @test Base.IteratorSize(typeof(cursor)) == Base.HasLength()
    @test length(cursor) == 2

    row = first(cursor)
    @test Base.IndexStyle(typeof(row)) == Base.IndexLinear()
    @test length(row) == length(expected)
    @test propertynames(row) == collect(propertynames(expected))
    for (i, prop) in enumerate(propertynames(row))
        @test getproperty(row, prop) == row[prop] == row[i] == expected[prop][1]
    end

    res = DBInterface.execute(stmt) |> columntable
    @test length(res) == 10
    @test length(res[1]) == 2
    @test isequal(res, expected)

    stmt = DBInterface.prepare(conn, raw"SELECT * FROM foo where a=?")
    cursor = DBInterface.execute(stmt, (1,))
    row = first(cursor)
    @test length(row) == length(expected)
    res = DBInterface.execute(stmt, (1, )) |> columntable
    @test length(res[1]) == 1

    DBInterface.close!(stmt)
    DBInterface.close!(conn)
    @test !isopen(conn)
end

@testset "timezone" begin
    user = if haskey(ENV, "ISC_USER")
        ENV["ISC_USER"]
    else
        "sysdba"
    end
    password = if haskey(ENV, "ISC_PASSWORD")
        ENV["ISC_PASSWORD"]
    else
        "masterkey"
    end

    conn = DBInterface.connect(Firebird.Connection, "localhost", user, password, "/tmp/julia_test.fdb"; create_new=true, timezone="Asia/Tokyo")

    cursor = DBInterface.execute(conn, raw"SELECT rdb$get_context('SYSTEM', 'ENGINE_VERSION') version from rdb$database")
    row = first(cursor)
    major_version = parse(Int, split(row.VERSION, ".")[1])
    if major_version < 4
        DBInterface.close!(conn)
        return
    end

    DBInterface.execute(
        conn, raw"""
            CREATE TABLE tz_test (
                id INTEGER NOT NULL,
                t TIME WITH TIME ZONE DEFAULT '12:34:56' NOT NULL,
                ts TIMESTAMP WITH TIME ZONE DEFAULT '1967-08-11 23:45:01' NOT NULL,
                PRIMARY KEY (id)
            )"""
    )

    DBInterface.execute(
        conn, raw"insert into tz_test (id) values (1)")
    DBInterface.execute(
        conn, raw"insert into tz_test (id, t, ts) values (2, '12:34:56 Asia/Seoul', '1967-08-11 23:45:01.0000 Asia/Seoul')")
    DBInterface.execute(
        conn, raw"insert into tz_test (id, t, ts) values (3, '03:34:56 UTC', '1967-08-11 14:45:01.0000 UTC')")

    expected = (
        ID = Int64[1, 2, 3],
        T = TimeZones.ZonedDateTime[TimeZones.ZonedDateTime(0, 1, 1, 12, 53, 55, tz"Asia/Tokyo"), TimeZones.ZonedDateTime(0, 1, 1, 12, 2, 48, tz"Asia/Seoul"), TimeZones.ZonedDateTime(0, 1, 1, 3, 34, 56, tz"UTC")],
        TS = TimeZones.ZonedDateTime[TimeZones.ZonedDateTime(1967, 8, 11, 23, 45, 1, tz"Asia/Tokyo"), TimeZones.ZonedDateTime(1967, 8, 11, 23, 45, 1, tz"Asia/Seoul"), TimeZones.ZonedDateTime(1967, 8, 11, 14, 45, 1, tz"UTC")]
    )

    cursor = DBInterface.execute(conn, "select * from tz_test")
    @test eltype(cursor) == Firebird.Row
    @test Tables.istable(cursor)
    @test Tables.rowaccess(cursor)
    @test Tables.rows(cursor) === cursor
    @test Tables.schema(cursor) == Tables.Schema(propertynames(expected), eltype.(collect(expected)))
    @test Base.IteratorSize(typeof(cursor)) == Base.HasLength()
    @test length(cursor) == 3

    DBInterface.close!(conn)
end

@testset "srp" begin
    user = "SYSDBA"
    password = "masterkey"

    keyA, keya = Firebird.get_client_seed()
    salt = Firebird.get_salt()
    v = Firebird.get_verifier(user, password, salt)
    keyB, keyb = Firebird.get_server_seed(v)
    server_key = Firebird.get_server_session(user, password, salt, keyA, keyB, keyb)
    _, client_key = Firebird.get_client_proof(user, password, salt, keyA, keyB, keya, "Srp")
    @test server_key == client_key

    _, client_key = Firebird.get_client_proof(user, password, salt, keyA, keyB, keya, "Srp256")
    @test server_key == client_key

    keyA, keya = Firebird.get_client_seed(DEBUG_PRIVATE_KEY)
    salt = DEBUG_SALT
    v = Firebird.get_verifier(user, password, salt)
    keyB, keyb = Firebird.get_server_seed(v, DEBUG_PRIVATE_KEY)
    server_key = Firebird.get_server_session(user, password, salt, keyA, keyB, keyb)
    keyM, client_key = Firebird.get_client_proof(user, password, salt, keyA, keyB, keya, "Srp")
    @test server_key == client_key
    @test keyM == hex2bytes("8c12324bb6e9e683a3ee62e13905b95d69f028a9")

    keyM, client_key = Firebird.get_client_proof(user, password, salt, keyA, keyB, keya, "Srp256")
    @test server_key == client_key
    @test keyM == hex2bytes("4675c18056c04b00cc2b991662324c22c6f08bb90beb3677416b03469a770308")
end

@testset "arc4" begin
    session_key = Vector{UInt8}("a key")
    src = Vector{UInt8}("plain text")

    a1 = Firebird.Arc4(session_key)
    enc = Firebird.translate(a1, src)
    @test enc == UInt8[0x4b, 0x4b, 0xdc, 0x65, 0x02, 0xb3, 0x08, 0x17, 0x48, 0x82]
    a2 = Firebird.Arc4(session_key)
    plain = Firebird.translate(a2, enc)
    @test plain == src
end

@testset "chacha20" begin
    session_key = hex2bytes("23AD52B15FA7EBDC4672D72289253D95DC9A4324FC369F593FDCC7733AD77617")
    nonce = hex2bytes("5A5F6C13C1F12653")
    enc = hex2bytes("6bd00ba222523f58de196fb471eea08d9fff95b5bbe6123dd3a8b9026ac0fa84")
    chacha = Firebird.ChaCha20(session_key, nonce, 0)
    @test Firebird.translate(chacha, enc) == b"TMCTF{Whose_garden_is_internet?}"

    src = Vector{UInt8}("plain text")
    chacha1 = Firebird.ChaCha20(session_key, nonce, 123)
    enc = Firebird.translate(chacha1, src)
    @test enc == UInt8[0x39, 0xdf, 0x7f, 0xdf, 0xcd, 0xd6, 0x6c, 0x56, 0xe7, 0x62]
    chacha2 = Firebird.ChaCha20(session_key, nonce, 123)
    plain = Firebird.translate(chacha2, enc)
    @test plain == src
end
