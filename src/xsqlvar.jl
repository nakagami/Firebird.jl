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

const SQL_TYPE_TEXT = 452
const SQL_TYPE_VARYING = 448
const SQL_TYPE_SHORT = 500
const SQL_TYPE_LONG = 496
const SQL_TYPE_FLOAT = 482
const SQL_TYPE_DOUBLE = 480
const SQL_TYPE_D_FLOAT = 530
const SQL_TYPE_TIMESTAMP = 510
const SQL_TYPE_BLOB = 520
const SQL_TYPE_ARRAY = 540
const SQL_TYPE_QUAD = 550
const SQL_TYPE_TIME = 560
const SQL_TYPE_DATE = 570
const SQL_TYPE_INT64 = 580
const SQL_TYPE_INT128 = 32752
const SQL_TYPE_TIMESTAMP_TZ = 32754
const SQL_TYPE_TIME_TZ = 32756
const SQL_TYPE_DEC_FIXED = 32758
const SQL_TYPE_DEC64 = 32760
const SQL_TYPE_DEC128 = 32762
const SQL_TYPE_BOOLEAN = 32764
const SQL_TYPE_NULL = 32766

xsqlvar_type_length = Dict(
    SQL_TYPE_TEXT=>-1,
    SQL_TYPE_VARYING=>-1,
    SQL_TYPE_SHORT=>4,
    SQL_TYPE_LONG=>4,
    SQL_TYPE_FLOAT=>4,
    SQL_TYPE_TIME=>4,
    SQL_TYPE_DATE=>4,
    SQL_TYPE_DOUBLE=>8,
    SQL_TYPE_TIMESTAMP=>8,
    SQL_TYPE_BLOB=>8,
    SQL_TYPE_ARRAY=>8,
    SQL_TYPE_QUAD=>8,
    SQL_TYPE_INT64=>8,
    SQL_TYPE_INT128=>16,
    SQL_TYPE_TIMESTAMP_TZ=>10,
    SQL_TYPE_TIME_TZ=>6,
    SQL_TYPE_DEC64=>8,
    SQL_TYPE_DEC128=>16,
    SQL_TYPE_DEC_FIXED=>16,
    SQL_TYPE_BOOLEAN=>1,
)


mutable struct XSQLVAR
    sqltype::Int
    sqlscale::Int
    sqlsubtype::Int
    sqllen::Int
    null_ok::Bool
    fieldname::String
    relname::String
    ownname::String
    aliasname::String
end


function io_length(x::XSQLVAR)::Int
    x.sqltype == SQL_TYPE_TEXT ? x.sqllen : xsqlvar_type_length[x.sqltype]
end

function has_precision_scale(x::XSQLVAR)::Bool
    (x.sqltype == SQL_TYPE_SHORT ||
        x.sqltype == SQL_TYPE_LONG ||
        x.sqltype == SQL_TYPE_QUAD ||
        x.sqltype == SQL_TYPE_INT64 ||
        x.sqltype == SQL_TYPE_INT128 ||
        x.sqltype == SQL_TYPE_DEC64 ||
        x.sqltype == SQL_TYPE_DEC128 ||
        x.sqltype == SQL_TYPE_DEC_FIXED) && x.sqlscale != 0
end

function _parse_date(raw_value::Vector{UInt8})::Tuple{Int, Int, Int}
    nday = bytes_to_buint32(raw_value) + 678882

    century = div(4 * nday - 1,  146097)
    nday = 4 * nday - 1 - 146097 * century
    day = nday / 4

    nday = div(4 * day + 3, 1461)
    day = 4 * day + 3 - 1461 * nday
    day = div(day + 4, 4)

    month = div(5 * day - 3, 153)
    day = 5 * day - 3 - 153 * month
    day = div(day + 5,  5)
    year = 100 * century + nday
    if month < 10
        month += 3
    else
        month -= 9
        year += 1
    end

    (year, month, day)
end

function _parse_time(raw_value::Vector{UInt8})
    n = bytes_to_buint32(raw_value)
    s = div(n, 10000)
    m = div(s, 60)
    h = div(m, 60)
    m = m % 60
    s = s % 60

    (h, m, s, (n % 10000) * 100000)
end

function parse_date(raw_value::Vector{UInt8})::Date
    year, month, day = _parse_date(raw_value)
    Date(year, month, day)
end

function parse_time(raw_value::Vector{UInt8})::Time
    h, m, s, n = _parse_time(raw_value)
    Time(h, m, s, n)
end

function parse_timestamp(raw_value::Vector{UInt8})::DateTime
    year, month, day = _parse_date(raw_value[1:4])
    h, m, s, n = _parse_time(raw_value[5:8])
    DateTime(year, month, day, h, m, s, n)
end

function value(x::XSQLVAR, raw_value::Vector{UInt8})
    if x.sqltype == SQL_TYPE_TEXT
        if x.sqlsubtype == 1
            raw_value
        else
            String(raw_value)
        end
    elseif x.sqltype == SQL_TYPE_VARYING
        if x.sqlsubtype == 1
            raw_value
        else
            String(raw_value)
        end
    elseif x.sqltype == SQL_TYPE_SHORT
        i16::Int16 = Int16(bytes_to_int32(raw_value))
        if x.sqlscale > 0
            Int64(i16) * Int64(10^x.scale)
        elseif x.sqlscale < 0
            if i16 < 0
                Decimal(1, i16*-1, x.sqlscale)
            else
                Decimal(0, i16, x.sqlscale)
            end
        else
            i16
        end
    elseif x.sqltype == SQL_TYPE_LONG
        i32::Int32 = Int32(bytes_to_int32(raw_value))
        if x.sqlscale > 0
            Int64(i32) * Int64(10^x.scale)
        elseif x.sqlscale < 0
            if i32 < 0
                Decimal(1, i32*-1, x.sqlscale)
            else
                Decimal(0, i32, x.sqlscale)
            end
        else
            i32
        end
    elseif x.sqltype == SQL_TYPE_FLOAT
        reinterpret(Float32, raw_value)
    elseif x.sqltype == SQL_TYPE_DOUBLE
        reinterpret(Float64, raw_value)
    elseif x.sqltype == SQL_TYPE_TIMESTAMP
        parse_timestamp(raw_value)
    elseif x.sqltype == SQL_TYPE_BLOB
        raw_value
    elseif x.sqltype == SQL_TYPE_TIME
        parse_time(raw_value)
    elseif x.sqltype == SQL_TYPE_DATE
        parse_date(raw_value)
    elseif x.sqltype == SQL_TYPE_INT64
        bytes_to_bint64(raw_value)
    elseif x.sqltype == SQL_TYPE_INT128
        bytes_to_bint64(raw_value)
    elseif x.sqltype == SQL_TYPE_TIMESTAMP_TZ
        # TODO:
        nothing
    elseif x.sqltype == SQL_TYPE_TIME_TZ
        # TODO:
        nothing
    elseif x.sqltype == SQL_TYPE_DEC_FIXED
        decimal_fiexed_to_decimal(value_value)
    elseif x.sqltype == SQL_TYPE_DEC64
        decimal64_to_decimal(value_value)
    elseif x.sqltype == SQL_TYPE_DEC128
        decimal128_to_decimal(value_value)
    elseif x.sqltype == SQL_TYPE_BOOLEAN
        raw_value[0] != 0
    elseif x.sqltype == SQL_TYPE_NULL
        nothing
    end
end

function juliatype(x::XSQLVAR)
    if x.sqltype == SQL_TYPE_TEXT
        if x.sqlsubtype == 1
            T = Vector{UInt8}
        else
            T = String
        end
    elseif x.sqltype == SQL_TYPE_VARYING
        if x.sqlsubtype == 1
            T = Vector{UInt8}
        else
            T = String
        end
    elseif x.sqltype == SQL_TYPE_SHORT
        T = Int16
    elseif x.sqltype == SQL_TYPE_LONG
        T = Int64
    elseif x.sqltype == SQL_TYPE_FLOAT
        T = Float32
    elseif x.sqltype == SQL_TYPE_DOUBLE
        T = Float64
    elseif x.sqltype == SQL_TYPE_TIMESTAMP
        T = DateTime
    elseif x.sqltype == SQL_TYPE_BLOB
        T = Vector{UInt8}
    elseif x.sqltype == SQL_TYPE_TIME
        T = Time
    elseif x.sqltype == SQL_TYPE_DATE
        T = Date
    elseif x.sqltype == SQL_TYPE_INT64
        T = Int64
    elseif x.sqltype == SQL_TYPE_INT128
        T = Int64
    elseif x.sqltype == SQL_TYPE_TIMESTAMP_TZ
        # TODO:
        T = nothing
    elseif x.sqltype == SQL_TYPE_TIME_TZ
        # TODO:
        T = nothing
    elseif x.sqltype == SQL_TYPE_DEC_FIXED
        T = Decimal
    elseif x.sqltype == SQL_TYPE_DEC64
        T = Decimal
    elseif x.sqltype == SQL_TYPE_DEC128
        T = Decimal
    elseif x.sqltype == SQL_TYPE_BOOLEAN
        T = Bool
    elseif x.sqltype == SQL_TYPE_NULL
        T = nothing
    end

    x.null_ok ? T : Union{Missing, T}
end
