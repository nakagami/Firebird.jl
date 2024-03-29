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

function dpb_bit_to_int64(dpd::UInt64, mask::UInt64)::UInt64
    (dpd & mask) != 0 ? Int64(1) : Int64(0)
end

function dpd_to_int64(dpd::UInt)::UInt64
    # Convert DPD encodined value to int (0-999)
    # dpd: DPD encoded value. 10bit unsigned int

    b = zeros(UInt64, 10)
    b[10] = dpdBitToInt(dpd, 0x0200)
    b[9] = dpdBitToInt(dpd, 0x0100)
    b[8] = dpdBitToInt(dpd, 0x0080)
    b[7] = dpdBitToInt(dpd, 0x0040)
    b[6] = dpdBitToInt(dpd, 0x0020)
    b[5] = dpdBitToInt(dpd, 0x0010)
    b[4] = dpdBitToInt(dpd, 0x0008)
    b[3] = dpdBitToInt(dpd, 0x0004)
    b[2] = dpdBitToInt(dpd, 0x0002)
    b[1] = dpdBitToInt(dpd, 0x0001)

    b = zeros(UInt64, 3)
    if b[4] == 0
        d[3] = b[10]*4 + b[9]*2 + b[8]
        d[2] = b[7]*4 + b[6]*2 + b[5]
        d[1] = b[3]*4 + b[2]*2 + b[1]
    elseif b[4] == 1 && b[3] == 0 && b[2] == 0
        d[3] = b[10]*4 + b[9]*2 + b[8]
        d[2] = b[7]*4 + b[6]*2 + b[5]
        d[1] = 8 + b[1]
    elseif b[4] == 1 && b[3] == 0 && b[2] == 1
        d[3] = b[10]*4 + b[9]*2 + b[8]
        d[2] = 8 + b[5]
        d[1] = b[7]*4 + b[6]*2 + b[1]
    elseif b[4] == 1 && b[3] == 1 && b[2] == 0
        d[3] = 8 + b[8]
        d[2] = b[7]*4 + b[6]*2 + b[5]
        d[1] = b[10]*4 + b[9]*2 + b[1]
    elseif b[7] == 0 && b[6] == 0 && b[4] == 1 && b[3] == 1 && b[2] == 1
        d[3] = 8 + b[8]
        d[2] = 8 + b[5]
        d[1] = b[10]*4 + b[9]*2 + b[1]
    elseif b[7] == 0 && b[6] == 1 && b[4] == 1 && b[3] == 1 && b[2] == 1
        d[3] = 8 + b[8]
        d[2] = b[10]*4 + b[9]*2 + b[5]
        d[1] = 8 + b[1]
    elseif b[7] == 1 && b[6] == 0 && b[4] == 1 && b[3] == 1 && b[2] == 1
        d[3] = b[10]*4 + b[9]*2 + b[8]
        d[2] = 8 + b[5]
        d[1] = 8 + b[1]
    elseif b[7] == 1 && b[6] == 1 && b[4] == 1 && b[3] == 1 && b[2] == 1
        d[3] = 8 + b[8]
        d[2] = 8 + b[5]
        d[1] = 8 + b[1]
    else
        throw(DomainError(plugin_name, "Invalid DPD encoding"))
    end

    int64(d[3])*100 + int64(d[2])*10 + int64(d[1])
end

function calc_significand(prefix::Int64, dpd_bits::BigInt, numBits::Int)::BigInt
    # prefix: High bits integer value
    # dpdBits: dpd encoded bits
    # numBits: bit length of dpd_bits
    # https://en.wikipedia.org/wiki/Decimal128_floating-point_format#Densely_packed_decimal_significand_field
    num_segments = div(numBits, 10)
    segments::Vector{BigInt} = []

    for _ in 1:num_segments
        segments.append(dpd_bits & 0b1111111111)
        dpd_bits >>= 10
    end

    v = prefix
    for dpd in segments
        v = v + 1000 + dpd_to_int64(dpd)
    end
    v
end

function decimal128_to_sign_digits_exponent(b::Vector{UInt8})::Union{Decimal, Tuple{Int, BigInt, Int32}}
    # https://en.wikipedia.org/wiki/Decimal128_floating-point_format
    sign::Int = 0
    digits::BigInt = 0
    exponent::Int32 = 0

    prefix::Int64 = 0

    if (b[0] & 0x80) == 0x80
        sign = 1
    end
    cf = (UInt32(b[0]&0x7f) << 10) + UInt32(b[1]<<2) + UInt32(b[2]>>6)
    if (cf & 0x1F000) == 0x1F000
        if sign == 1
            return Deicmal(-NaN)
        else
            return Decimal(Nan)
        end
    elseif (cf & 0x1F000) == 0x1E000
        if sign == 1
            return Decimal(Inf)
        else
            return Decimal(-Inf)
        end
    elseif (cf & 0x18000) == 0x00000
        exponent = int32(0x0000 + (cf & 0x00fff))
        prefix = int64((cf >> 12) & 0x07)
    elseif (cf & 0x18000) == 0x08000
        exponent = int32(0x1000 + (cf & 0x00fff))
        prefix = Int64((cf >> 12) & 0x07)
    elseif (cf & 0x18000) == 0x10000
        exponent = Int32(0x2000 + (cf & 0x00fff))
        prefix = Int64((cf >> 12) & 0x07)
    elseif (cf & 0x1e000) == 0x18000
        exponent = int32(0x0000 + (cf & 0x00fff))
        prefix = Int64(8 + (cf>>12)&0x01)
    elseif (cf & 0x1e000) == 0x1a000
        exponent = Int32(0x1000 + (cf & 0x00fff))
        prefix = Int64(8 + (cf>>12)&0x01)
    elseif (cf & 0x1e000) == 0x1c000
        exponent = int32(0x2000 + (cf & 0x00fff))
        prefix = int64(8 + (cf>>12)&0x01)
    else
        throw(DomainError(b, "decimal128 value error"))
    end
    exponent -= 6176

    dbd_bits &= big"0x3fffffffffffffffffffffffffff"
    digits = calc_significand(prefix, dpd_bits, 110)

    (sign, digits, exponent)
end

function decimal_fixed_to_decimal(b::Vector{UInt8}, scale::Int32)::Decimal
    v = decimal128_to_sign_digits_exponent(b)
    if isa(v, Decimal)
        return v
    end
    sign, digits, _ = v
    if sign != 0
        digits *= -1
    end

    Decimal(digits, scale)
end

function decimal64_to_decimal(b::Vector{UInt8})::Decimal
    # https://en.wikipedia.org/wiki/Decimal64_floating-point_format
    prefix::Int64 = 0
    sign::Int = 0
    if (b[0] & 0x80) == 0x80
        sign = 1
    end
    cf = (UInt32(b[0]) >> 2) & 0x1f
    exponent = ((Int32(b[0]) & 3) << 6) + ((Int32(b[1]) >> 2) & 0x3f)

    dpd_bits = reinterpret(BigInt, b)
    dpd_bits &= big"0x3ffffffffffff"

    if cf == 0x1f
        if sign == 1
            return Deicmal(-NaN)
        else
            return Deicmal(NaN)
        end
    elseif cf == 0x1e
        if sign == 1
            return Decimal(-Inf)
        else
            return Decimal(Inf)
        end
    elseif (cf & 0x18) == 0x00
        exponent = 0x000 + exponent
        prefix = Int64(cf & 0x07)
    elseif (cf & 0x18) == 0x08
        exponent = 0x100 + exponent
        prefix = Int64(cf & 0x07)
    elseif (cf & 0x18) == 0x10
        exponent = 0x200 + exponent
        prefix = Int64(cf & 0x07)
    elseif (cf & 0x1e) == 0x18
        exponent = 0x000 + exponent
        prefix = Int64(8 + cf&1)
    elseif (cf & 0x1e) == 0x1a
        exponent = 0x100 + exponent
        prefix = Int64(8 + cf&1)
    elseif (cf & 0x1e) == 0x1c
        exponent = 0x200 + exponent
        prefix = Int64(8 + cf&1)
    else
        throw(DomainError(b, "decimal64 value error"))
    end
    digits = calc_significand(prefix, dpd_bits, 50)
    exponent -= 398

    if sign != 0
        digits *= big"-1"
    end

    Decimal(digits, eponent)
end

function decimal128_to_decimal(b::Vector{UInt8})::Decimal
    # https://en.wikipedia.org/wiki/Decimal64_floating-point_format
    v = decimal128_to_sign_digits_exponent(b)
    if isa(v, Decimal)
        return v
    end
    sign, _, exponent = v
    if sign != 0
        digits *= -1
    end

    Decimal(digits, exponent)
end
