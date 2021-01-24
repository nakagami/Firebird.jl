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
using SHA

const SRP_KEY_SIZE = 128
const SRP_SALT_SIZE = 32

function pad(n::BigInt)::Vector{UInt8}
    v::Vector{UInt8} = []
    for x in 1:SRP_KEY_SIZE
        push!(v, UInt8(n & 255))
        n >>= 8
        if n == 0
            break
        end
    end

    reverse!(v)
    v
end

function bigint_to_bytes(v::BigInt)::Vector{UInt8}
    pad(v)
end

function bytes_to_bigint(v::Vector{UInt8})::BigInt
    r::BigInt = 0
    for ui in v
        r = r * 256 + ui
    end
    r
end

function bigint_to_sha1(n::BigInt)::Vector{UInt8}
    v::Vector{UInt8} = []
    while n > 0
        push!(v, UInt8(n & 255))
        n >>= 8
    end
    reverse!(v)
    sha1(v)
end

function get_prime()::Tuple{BigInt, BigInt, BigInt}
    N = big"0xE67D2E994B2F900C3F41F08F5BB2627ED0D49EE1FE767A52EFCD565CD6E768812C3E1E9CE8F0A8BEA6CB13CD29DDEBF7A96D4A93B55D488DF099A15C89DCB0640738EB2CBDD9A8F7BAB561AB1B0DC1C6CDABF303264A08D1BCA932D1F1EE428B619D970F342ABA9A65793B8B2F041AE5364350C16F735F56ECBCA87BD57B29E7"
    g = big"2"
    k = big"1277432915985975349439481660349303019122249719989"
    return N, g, k
end

function get_scramble(keyA::BigInt, keyB::BigInt)::BigInt
    # keyA:A client public ephemeral values
    # keyB:B server public ephemeral values
    bytes_to_bigint(sha1(vcat(pad(keyA), pad(keyB))))
end

function get_string_hash(s::AbstractString)::BigInt
    bytes_to_bigint(sha1(s))
end

function get_user_hash(salt::Vector{UInt8}, user::AbstractString, password::AbstractString)::BigInt
    hash1 = sha1(string(user, ":", password))
    hash2 = sha1(vcat(salt, hash1))
    bytes_to_bigint(hash2)
end

function get_client_sheed()::Tuple{BigInt, BigInt}
    prime, g, _ = get_prime()
    keya = rand(big"1":big"340282366920938463463374607431768211456") # 1 << 128
    keyA = powermod(g, keya, prime)
    (keyA, keya)
end

function get_salt()::Vector{UInt8}
    buf::Vector{UInt8} = []
    for _ in 1:SRP_SALT_SIZE
        push!(buf, rand(0:255))
    end
    buf
end

function get_verifier(user::AbstractString, password::AbstractString, salt::Vector{UInt8})::BigInt
    prime, g, _ = get_prime()
    x = get_user_hash(salt, user, password)
    powermod(g, x, prime)
end

function get_server_seed(v::BigInt)::Tuple{BigInt, BigInt}
    prime, g, k = get_prime()
    keyb = rand(big"1":big"340282366920938463463374607431768211456") # 1 << 128
    gb = powermod(g, keyb, prime)
    kv = (k * v) % prime
    keyB = (kv + gb) % prime
    keyB, keyb
end

function get_client_session(user::AbstractString, password::AbstractString, salt::Vector{UInt8}, keyA::BigInt, keyB::BigInt, keya::BigInt)::Vector{UInt8}
    prime, g, k = get_prime()
    u = get_scramble(keyA, keyB)
    x = get_user_hash(salt, user, password)
    gx = powermod(g, x, prime)
    kgx = (k * gx) % prime
    diff = (keyB - kgx) % prime
    ux = (u * x) % prime
    aux = (keya + ux) % prime
    session_secret = powermod(diff, aux, prime)
    bigint_to_sha1(session_secret)
end

function get_server_session(user::AbstractString, password::AbstractString, salt::Vector{UInt8}, keyA::BigInt, keyB::BigInt, keyb::BigInt)::Vector{UInt8}
    prime, _, _ = get_prime()
    u = get_scramble(keyA, keyB)
    v = get_verifier(user, password, salt)
    vu = powermod(v, u, prime)
    avu = (keyA * vu) % prime
    session_secret = powermod(avu, keyb, prime)
    bigint_to_sha1(session_secret)
end

function get_client_proof(user::AbstractString, password::AbstractString, salt::Vector{UInt8}, keyA::BigInt, keyB::BigInt, keya::BigInt, plugin_name::AbstractString)::Tuple{Vector{UInt8}, Vector{UInt8}}
    prime, g, _ = get_prime()
    keyK = get_client_session(user, password, salt, keyA, keyB, keya)

    n1 = bytes_to_bigint(bigint_to_sha1(prime))
    n2 = bytes_to_bigint(bigint_to_sha1(g))
    n3 = powermod(n1, n2, prime)
    n4 = get_string_hash(user)
    buf = vcat(
        bigint_to_bytes(n3),
        bigint_to_bytes(n4),
        salt,
        bigint_to_bytes(keyA),
        bigint_to_bytes(keyB),
        keyK
    )

    if plugin_name == "Srp"
        keyM = sha1(buf)
    elseif plugin_name == "Srp256"
        keyM = sha1(buf)
    else
        throw(DomainError(plugin_name, "unknown plugin"))
    end

    keyM, keyK
end
