################################################################################
# MIT License
#
# Copyright (c) 2021 Hajime Nakagami<nakagami@gmail.com>
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

sigma = b"expand 32-byte k"

mutable struct ChaCha20
    block::Vector{UInt32}
    pos::UInt32
    xor_table::Vector{UInt8}
    xor_table_pos::Int

    function ChaCha20(key::Vector{UInt8}, nonce::Vector{UInt8}, pos::Int)
        block_bytes::Vector{UInt8} = vcat(sigma, key, int64_to_bytes(pos), nonce)
        @assert length(block_bytes) == 64

        block::Vector{UInt32} = []
        for i in range(1, length(block_bytes), step=4)
            append!(block, bytes_to_uint32(block_bytes[i:i+3]))
        end
        xor_table = chacha20_round_bytes(block)

        new(block, UInt32(pos), xor_table, 1)
    end
end


function rotate(x::UInt32, n::Int)::UInt32
    (x << n) | (x >> (32 - n))
end


function quaterround(a::UInt32, b::UInt32, c::UInt32, d::UInt32)
    a += b
    d = xor(d, a)
    d = rotate(d, 16)

    c += d
    b = xor(b, c)
    b = rotate(b, 12)

    a += b
    d = xor(d, a)
    d = rotate(d, 8)

    c += d
    b = xor(b, c)
    b = rotate(b, 7)

    a, b, c, d
end


function chacha20_round_bytes(block::Vector{UInt32})::Vector{UInt8}
    x = copy(block)

    for _ in range(1, length=10)
        # column rounds
        x[1], x[5], x[9], x[13] = quaterround(x[1], x[5], x[9], x[13])
        x[2], x[6], x[10], x[14] = quaterround(x[2], x[6], x[10], x[14])
        x[3], x[7], x[11], x[15] = quaterround(x[3], x[7], x[11], x[15])
        x[4], x[8], x[12], x[16] = quaterround(x[4], x[8], x[12], x[16])
        # diagonal rounds
        x[1], x[6], x[11], x[16] = quaterround(x[1], x[6], x[11], x[16])
        x[2], x[7], x[12], x[13] = quaterround(x[2], x[7], x[12], x[13])
        x[3], x[8], x[9], x[14] = quaterround(x[3], x[8], x[9], x[14])
        x[4], x[5], x[10], x[15] = quaterround(x[4], x[5], x[10], x[15])
    end

    for i in range(1, length=16)
        x[i] += block[i]
    end

    r::Vector{UInt8} = []
    for i in x
        r = vcat(r, uint32_to_bytes(i))
    end
    r
end


function translate(chacha20::ChaCha20, plain::Vector{UInt8})
    enc::Vector{UInt8} = []

    for i in range(1, length=length(plain))
        append!(enc, xor(plain[i], chacha20.xor_table[chacha20.xor_table_pos]))
        chacha20.xor_table_pos += 1
        if chacha20.xor_table_pos > length(chacha20.xor_table)
            chacha20.block[13] += 1
            chacha20.xor_table = chacha20_round_bytes(chacha20.block)
            chacha20.xor_table_pos = 1
        end
    end

    enc
end
