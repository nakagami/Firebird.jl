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
using Test, Firebird

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
    conn = DBInterface.connect(Firebird.Connection, "localhost", user, password, "/tmp/test.fdb", port=UInt16(3050), wire_crypt=true, create_new=true)
end

@testset "srp" begin
    user = "SYSDBA"
    password = "masterkey"

    keyA, keya = Firebird.get_client_sheed()
    salt = Firebird.get_salt()
    v = Firebird.get_verifier(user, password, salt)
    keyB, keyb = Firebird.get_server_seed(v)
    server_key = Firebird.get_server_session(user, password, salt, keyA, keyB, keyb)
    _, client_key = Firebird.get_client_proof(user, password, salt, keyA, keyB, keya, "Srp")
    @test server_key == client_key

    _, client_key = Firebird.get_client_proof(user, password, salt, keyA, keyB, keya, "Srp256")
    @test server_key == client_key
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
