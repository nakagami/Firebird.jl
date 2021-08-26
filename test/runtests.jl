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
using Test, Firebird, DBInterface, Tables, Dates, Decimals

const DEBUG_PRIVATE_KEY = big"0x60975527035CF2AD1989806F0407210BC81EDC04E2762A56AFD529DDDA2D4393"
const DEBUG_SALT = hex2bytes("02E268803000000079A478A700000002D1A6979000000026E1601C000000054F")

@testset "connection" begin
    user = if haskey(ENV, "ISC_USER")
        ENV["ISC_USER"]
    else
        "SYSDBA"
    end
    password = if haskey(ENV, "ISC_PASSWORD")
        ENV["ISC_PASSWORD"]
    else
        "masterkey"
    end
    conn = DBInterface.connect(Firebird.Connection, "localhost", user, password, "/tmp/julia_test.fdb"; create_new=true)

    DBInterface.execute(
        conn, raw"""
            CREATE TABLE foo (
                a INTEGER NOT NULL,
                b VARCHAR(30) NOT NULL UNIQUE,
                c VARCHAR(1024),
                d DECIMAL(16,3) DEFAULT -0.123,
                e DATE DEFAULT '1967-08-11',
                f TIMESTAMP DEFAULT '1967-08-11 23:45:01',
                g TIME DEFAULT '23:45:01',
                h BLOB SUB_TYPE 0,
                i DOUBLE PRECISION DEFAULT 0.0,
                j FLOAT DEFAULT 0.0,
                PRIMARY KEY (a),
                CONSTRAINT CHECK_A CHECK (a <> 0)
            )"""
    )
    DBInterface.execute(
        conn, raw"insert into foo(a, b, c, h) values (1, 'a', 'b','This is a memo')")
    DBInterface.execute(
        conn, raw"insert into foo(a, b, c, h) values (2, 'A', 'B','This is a memo2')")

    expected = (
        A = Int64[1, 2],
        B = String["a", "A"],
        C = Union{Missing, String}["b", "B"],
        D = Union{Missing, Decimal}[Decimal(-0.123), Decimal(-0.123)],
        E = Union{Missing, Dates.Date}[Dates.Date("1967-08-11"), Dates.Date("1967-08-11")],
        F = Union{Missing, Dates.DateTime}[Dates.DateTime("1967-08-11T23:45:01"), Dates.DateTime("1967-08-11T23:45:01")],
        G = Union{Missing, Dates.Time}[Dates.Time("23:45:01"), Dates.Time("23:45:01")],
        H = Union{Missing, Vector{UInt8}}[Vector{UInt8}("This is a memo"), Vector{UInt8}("This is a memo2")],
        I = Union{Missing, Float64}[Float64(0.0), Float64(0.0)],
        J = Union{Missing, Float32}[Float32(0.0), Float32(0.0)],
    )

    cursor = DBInterface.execute("SELECT * from foo")
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

    # TODO:
    # as a prepared statement
    # stmt = DBInterface.prepare(conn, raw"SELECT * from foo")
    # cursor = DBInterface.execute(stmt)

    DBInterface.close!(conn)
    @test !isopen(conn)
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
