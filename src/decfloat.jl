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
using Decimals

function dpd_to_int(dpd::UInt)::UInt64
    # Convert DPD encoded value to int (0-999)
    # dpd: DPD encoded value. 10bit unsigned int

    b = zeros(UInt64, 10)
    b[10] = (dpd & 0b1000000000) != 0 ? 1 : 0
    b[9] = (dpd & 0b0100000000) != 0 ? 1 : 0
    b[8] = (dpd & 0b0010000000) != 0 ? 1 : 0
    b[7] = (dpd & 0b0001000000) != 0 ? 1 : 0
    b[6] = (dpd & 0b0000100000) != 0 ? 1 : 0
    b[5] = (dpd & 0b0000010000) != 0 ? 1 : 0
    b[4] = (dpd & 0b0000001000) != 0 ? 1 : 0
    b[3] = (dpd & 0b0000000100) != 0 ? 1 : 0
    b[2] = (dpd & 0b0000000010) != 0 ? 1 : 0
    b[1] = (dpd & 0b0000000001) != 0 ? 1 : 0

    d = zeros(UInt64, 3)
    if b[4] == 0
        d[3] = b[10] * 4 + b[9] * 2 + b[8]
        d[2] = b[7] * 4 + b[6] * 2 + b[5]
        d[1] = b[3] * 4 + b[2] * 2 + b[1]
    elseif b[4] == 1 && b[3] == 0 && b[2] == 0
        d[3] = b[10] * 4 + b[9] * 2 + b[8]
        d[2] = b[7] * 4 + b[6] * 2 + b[5]
        d[1] = 8 + b[1]
    elseif b[4] == 1 && b[3] == 0 && b[2] == 1
        d[3] = b[10] * 4 + b[9] * 2 + b[8]
        d[2] = 8 + b[5]
        d[1] = b[7] * 4 + b[6] * 2 + b[1]
    elseif b[4] == 1 && b[3] == 1 && b[2] == 0
        d[3] = 8 + b[8]
        d[2] = b[7] * 4 + b[6] * 2 + b[5]
        d[1] = b[10] * 4 + b[9] * 2 + b[1]
    elseif b[7] == 0 && b[6] == 0 && b[4] == 1 && b[3] == 1 && b[2] == 1
        d[3] = 8 + b[8]
        d[2] = 8 + b[5]
        d[1] = b[10] * 4 + b[9] * 2 + b[1]
    elseif b[7] == 0 && b[6] == 1 && b[4] == 1 && b[3] == 1 && b[2] == 1
        d[3] = 8 + b[8]
        d[2] = b[10] * 4 + b[9] * 2 + b[5]
        d[1] = 8 + b[1]
    elseif b[7] == 1 && b[6] == 0 && b[4] == 1 && b[3] == 1 && b[2] == 1
        d[3] = b[10] * 4 + b[9] * 2 + b[8]
        d[2] = 8 + b[5]
        d[1] = 8 + b[1]
    elseif b[7] == 1 && b[6] == 1 && b[4] == 1 && b[3] == 1 && b[2] == 1
        d[3] = 8 + b[8]
        d[2] = 8 + b[5]
        d[1] = 8 + b[1]
    else
        throw(DomainError(dpd, "Invalid DPD encoding"))
    end

    d[3] * 100 + d[2] * 10 + d[1]
end

function calc_significand(prefix::Int64, dpd_bits::BigInt, num_bits::Int)::BigInt
    # prefix: High bits integer value
    # dpd_bits: dpd encoded bits
    # num_bits: bit length of dpd_bits
    # https://en.wikipedia.org/wiki/Decimal128_floating-point_format#Densely_packed_decimal_significand_field
    num_segments = div(num_bits, 10)
    segments = BigInt[]

    for _ = 1:num_segments
        push!(segments, dpd_bits & 0b1111111111)
        dpd_bits >>= 10
    end
    reverse!(segments)

    v = BigInt(prefix)
    for dpd in segments
        v = v * 1000 + dpd_to_int(UInt(dpd))
    end
    v
end

function decimal128_to_sign_digits_exponent(
    b::Vector{UInt8},
)::Tuple{Int,BigInt,Int32}
    # https://en.wikipedia.org/wiki/Decimal128_floating-point_format
    sign::Int = (b[1] & 0x80) != 0 ? 1 : 0
    cf::UInt32 =
        (UInt32(b[1] & 0x7f) << 10) + (UInt32(b[2]) << 2) + UInt32(b[3] >> 6)
    exponent::Int32 = 0
    prefix::Int64 = 0

    if (cf & 0x1F000) == 0x1F000
        throw(DomainError(b, "decimal128 NaN is not supported by Decimals.jl"))
    elseif (cf & 0x1F000) == 0x1E000
        throw(DomainError(b, "decimal128 Infinity is not supported by Decimals.jl"))
    elseif (cf & 0x18000) == 0x00000
        exponent = Int32(0x0000 + (cf & 0x00fff))
        prefix = Int64((cf >> 12) & 0x07)
    elseif (cf & 0x18000) == 0x08000
        exponent = Int32(0x1000 + (cf & 0x00fff))
        prefix = Int64((cf >> 12) & 0x07)
    elseif (cf & 0x18000) == 0x10000
        exponent = Int32(0x2000 + (cf & 0x00fff))
        prefix = Int64((cf >> 12) & 0x07)
    elseif (cf & 0x1E000) == 0x18000
        exponent = Int32(0x0000 + (cf & 0x00fff))
        prefix = Int64(8 + ((cf >> 12) & 0x01))
    elseif (cf & 0x1E000) == 0x1A000
        exponent = Int32(0x1000 + (cf & 0x00fff))
        prefix = Int64(8 + ((cf >> 12) & 0x01))
    elseif (cf & 0x1E000) == 0x1C000
        exponent = Int32(0x2000 + (cf & 0x00fff))
        prefix = Int64(8 + ((cf >> 12) & 0x01))
    else
        throw(DomainError(b, "decimal128 value error"))
    end
    exponent -= 6176

    dpd_bits = bytes_to_bigint(b) & big"0x3fffffffffffffffffffffffffff"
    digits = calc_significand(prefix, dpd_bits, 110)

    (sign, digits, exponent)
end

function decimal_fixed_to_decimal(b::Vector{UInt8}, scale::Int)::Decimal
    sign, digits, _ = decimal128_to_sign_digits_exponent(b)
    Decimal(sign, digits, scale)
end

function decimal64_to_decimal(b::Vector{UInt8})::Decimal
    # https://en.wikipedia.org/wiki/Decimal64_floating-point_format
    sign::Int = (b[1] & 0x80) != 0 ? 1 : 0
    cf::UInt32 = (UInt32(b[1]) >> 2) & 0x1f
    exponent::Int32 = ((Int32(b[1]) & 3) << 6) + ((Int32(b[2]) >> 2) & 0x3f)
    prefix::Int64 = 0

    dpd_bits = bytes_to_bigint(b) & big"0x3ffffffffffff"

    if cf == 0x1f
        throw(DomainError(b, "decimal64 NaN is not supported by Decimals.jl"))
    elseif cf == 0x1e
        throw(DomainError(b, "decimal64 Infinity is not supported by Decimals.jl"))
    elseif (cf & 0x18) == 0x00
        exponent = Int32(0x000 + exponent)
        prefix = Int64(cf & 0x07)
    elseif (cf & 0x18) == 0x08
        exponent = Int32(0x100 + exponent)
        prefix = Int64(cf & 0x07)
    elseif (cf & 0x18) == 0x10
        exponent = Int32(0x200 + exponent)
        prefix = Int64(cf & 0x07)
    elseif (cf & 0x1e) == 0x18
        exponent = Int32(0x000 + exponent)
        prefix = Int64(8 + (cf & 1))
    elseif (cf & 0x1e) == 0x1a
        exponent = Int32(0x100 + exponent)
        prefix = Int64(8 + (cf & 1))
    elseif (cf & 0x1e) == 0x1c
        exponent = Int32(0x200 + exponent)
        prefix = Int64(8 + (cf & 1))
    else
        throw(DomainError(b, "decimal64 value error"))
    end
    digits = calc_significand(prefix, dpd_bits, 50)
    exponent -= 398

    Decimal(sign, digits, exponent)
end

function decimal128_to_decimal(b::Vector{UInt8})::Decimal
    sign, digits, exponent = decimal128_to_sign_digits_exponent(b)
    Decimal(sign, digits, exponent)
end
