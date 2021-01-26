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


struct XSQLVAR
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
