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

function int32_to_bytes(i32::Int32)::Vector{UInt8}
    vcat(
        UInt8(i32 & 0xFF),
        UInt8(i32 >> 8 & 0xFF),
        UInt8(i32 >> 16 & 0xFF),
        UInt8(i32 >> 24 & 0xFF),
    )
end

function bint64_to_bytes(i64::Int64)::Vector{UInt8}
    vcat(
        UInt8(i64 >> 56 & 0xFF),
        UInt8(i64 >> 48 & 0xFF),
        UInt8(i64 >> 40 & 0xFF),
        UInt8(i64 >> 32 & 0xFF),
        UInt8(i64 >> 24 & 0xFF),
        UInt8(i64 >> 16 & 0xFF),
        UInt8(i64 >> 8 & 0xFF),
        UInt8(i64 & 0xFF),
    )
end

function bint32_to_bytes(i32::Int32)::Vector{UInt8}
    vcat(
        UInt8(i32 >> 24 & 0xFF),
        UInt8(i32 >> 16 & 0xFF),
        UInt8(i32 >> 8 & 0xFF),
        UInt8(i32 & 0xFF),
    )
end

function bint16_to_bytes(i16::Int16)::Vector{UInt8}
    vcat(
        UInt8(i16 >> 24 & 0xFF),
        UInt8(i16 >> 16 & 0xFF),
        UInt8(i16 >> 8 & 0xFF),
        UInt8(i16 & 0xFF),
    )
end

function bytes_to_uint128(b::Vector{UInt8})::UInt128
    reinterpret(UInt128, b)
end

function bytes_to_int64(b::Vector{UInt8})::Int64
    reinterpret(Int64, b)
end

function bytes_to_uint32(b::Vector{UInt8})::UInt32
    reinterpret(UInt32, b)
end

function bytes_to_int32(b::Vector{UInt8})::Int32
    reinterpret(Int32, b)
end

function bytes_to_int16(b::Vector{UInt8})::Int16
    reinterpret(Int16, b)
end


function bytes_to_buint128(b::Vector{UInt8})::UInt128
    reinterpret(UInt128, reverse(b))
end

function bytes_to_buint64(b::Vector{UInt8})::UInt64
    reinterpret(UInt64, reverse(b))
end

function bytes_to_buint32(b::Vector{UInt8})::UInt32
    reinterpret(UInt32, reverse(b))
end

function bytes_to_bint128(b::Vector{UInt8})::Int128
    reinterpret(Int128, reverse(b))
end

function bytes_to_bint64(b::Vector{UInt8})::Int64
    reinterpret(Int64, reverse(b))
end

function bytes_to_bint32(b::Vector{UInt8})::Int32
    reinterpret(Int32, reverse(b))
end

function bytes_to_bint16(b::Vector{UInt8})::Int16
    reinterpret(Int16, reverse(b))
end

function xdr_bytes(bs::Vector{UInt8})::Vector{UInt8}
    # XDR encoding bytes
    n = length(bs)
    padding = 0
    if n % 4 != 0
        padding = 4 - n % 4
    end
    buf = zeros(UInt8, 4 + n + padding)
    buf[1] = UInt8(n >> 24 & 0xFF)
    buf[2] = UInt8(n >> 16 & 0xFF)
    buf[3] = UInt8(n >> 8 & 0xFF)
    buf[4] = UInt8(n & 0xFF)
    for i in 1:length(bs)
        buf[4 + i] = bs[i]
    end
    buf
end

function to_blr(i64::Int64)::Tuple{Vector{UInt8}, Vector{UInt8}}
    bint64_to_bytes(i64), UInt8[16, 0]
end

function to_blr(i32::Int32)::Tuple{Vector{UInt8}, Vector{UInt8}}
    bint32_to_bytes(i32), UInt8[8, 0]
end

function to_blr(f64::Float64)::Tuple{Vector{UInt8}, Vector{UInt8}}
    buf = IOBuffer()
    write(buf, f64)
    seek(buf, 0)
    v = read(buf)
    v, UInt8[27]
end

function to_blr(bytes::Vector{UInt8})::Tuple{Vector{UInt8}, Vector{UInt8}}
    nbytes = length(bytes)
    pad_length = ((4 - nbytes) & 3)
    padding = Vector{UInt8}[0, 0, 0]
    v = vcat(bytes, padding[1:pad_length])

    v, UInt8[14, UInt8(nbytes & 255), UInt8(nbytes >> 8)]
end

function _convert_date(year::Int, month::Int, day::Int)::Vector{UInt8}
    i = month + 9
    jy = year + div(i, 12) - 1
    jm = mod(i, 12)
    c = div(jy, 100)
    jy -= 100 * c
    j = (146097*c)/4 + (1461*jy)/4 + (153*jm+2)/5 + day - 678882

    bint32_to_bytes(Int32(j))
end

function _convert_time(hour::Int, minute::Int, second::Int, microsecond::Int, nanosecond::Int)::Vector{UInt8}
    v = (hour*3600+mintes*60+second)*10000 + div(microsecond, 100) + div(nanosecond, 100000)

    bint32_to_bytes(Int32(v))
end

function to_blr(d::Date)::Tuple{Vector{UInt8}, Vector{Uint8}}
    v = _convert_date(Dates.year(d), Dates.month(d), Dates.day(d))

    v, UInt8[12]
end

function to_blr(t::Time)::Tuple{Vector{UInt8}, Vector{UInt8}}
    v = _convert_time(Time.hour(t), Time.minute(t), Time.second(t), Time.microsecond(t), Time.nanosecond(t))

    v, UInt8[13]
end

function to_blr(dt::DateTime)::Tuple{Vector{UInt8}, Vector{UInt8}}
    v = vcat(
        _convet_date(DateTime.year(dt), DateTime.month(dt), DateTime.day(dt)),
        _convet_time(DateTime.hour(dt), DateTime.minute(dt), DateTime.second(dt), DateTime.microsecond(dt), DateTime.nanosecond(dt))
    )
    v, UInt8[35]
end

function to_blr(b::Bool)::Tuple{Vector{UInt8}, Vector{UInt8}}
    if b
        UInt8[1, 0, 0, 0], UInt8[23]
    else
        UInt8[0, 0, 0, 0], UInt8[23]
    end
end

function to_blr(Nothing)::Tuple{Vector{UINt8}, Vector{UInt8}}
    [], UInt8[14, 0, 0]
end

function calc_blr(xsqlda::Vector{XSQLVAR})::Vector{UInt8}
    # Calculate  BLR from XSQLVAR array.
    ln = length(xsqlda) * 2
    blr::Vector{UInt8} = UInt8[5, 2, 4, 0, UInt8(ln & 255), UInt8(ln >> 8)]

    for x in xsqlda
        sqlscale = x.sqlscale
        if sqlscale < 0
            sqlscale += 256
        end
        if x.sqltype == SQL_TYPE_VARYING
            append!(blr, UInt8(37))
            append!(blr, UInt8(x.sqllen & 255))
            append!(blr, UInt8(x.sqllen >> 8))
        elseif x.sqltime == SQL_TYPE_TEXT
            append!(blr, UInt8(14))
            append!(blr, UInt8(x.sqllen & 255))
            append!(blr, UInt8(x.sqllen >> 8))
        elseif x.sqltime == SQL_TYPE_LONG
            append!(blr, UInt8(8))
            append!(blr, UInt8(sqlscale))
        elseif x.sqltime == SQL_TYPE_SHORT
            append!(blr, UInt8(7))
            append!(blr, UInt8(sqlscale))
        elseif x.sqltime == SQL_TYPE_INT64
            append!(blr, UInt8(16))
            append!(blr, UInt8(sqlscale))
        elseif x.sqltime == SQL_TYPE_INT128
            append!(blr, UInt8(26))
            append!(blr, UInt8(sqlscale))
        elseif x.sqltime == SQL_TYPE_QUAD
            append!(blr, UInt8(9))
            append!(blr, UInt8(sqlscale))
        elseif x.sqltime == SQL_TYPE_DEC_FIXED  # OBSOLATED
            append!(blr, UInt8(26))
            append!(blr, UInt8(sqlscale))
        elseif x.sqltime == SQL_TYPE_DOUBLE
            append!(blr, UInt8(27))
        elseif x.sqltime == SQL_TYPE_FLOAT
            append!(blr, UInt8(10))
        elseif x.sqltime == SQL_TYPE_D_FLOAT
            append!(blr, UInt8(11))
        elseif x.sqltime == SQL_TYPE_DATE
            append!(blr, UInt8(12))
        elseif x.sqltime == SQL_TYPE_TIME
            append!(blr, UInt8(13))
        elseif x.sqltime == SQL_TYPE_TIMESTAMP
            append!(blr, UInt8(35))
        elseif x.sqltime == SQL_TYPE_BLOB
            append!(blr, UInt8(9))
            append!(blr, UInt8(0))
        elseif x.sqltime == SQL_TYPE_ARRAY
            append!(blr, UInt8(9))
            append!(blr, UInt8(0))
        elseif x.sqltime == SQL_TYPE_BOOLEAN
            append!(blr, UInt8(23))
        elseif x.sqltime == SQL_TYPE_DEC64
            append!(blr, UInt8(24))
        elseif x.sqltime == SQL_TYPE_DEC128
            append!(blr, UInt8(25))
        elseif x.sqltime == SQL_TYPE_TIME_TZ
            append!(blr, UInt8(28))
        elseif x.sqltime == SQL_TYPE_TIMESTAMP_TZ
            append!(blr, UInt8(29))
        end

        # [blr_short, 0]
        append!(blr, UInt8(7))
        append!(blr, UInt8(0))
    end

    # [blr_end, blr_eoc]
    append!(blr, UInt8(255))
    append!(blr, UInt8(76))

    blr
end
