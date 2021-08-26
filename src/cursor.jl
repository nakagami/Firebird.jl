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

mutable struct Cursor <: DBInterface.Cursor
    stmt::Statement

    names::Vector{Symbol}
    types::Vector{Type}
    lookup::Dict{Symbol, Int}

    rows::Vector{Vector{Any}}
    current_rownumber::Int
end

struct Row <: Tables.AbstractRow
    cursor::Cursor
    rownumber::Int
end

getcursor(r::Row) = getfield(r, :cursor)
getrownumber(r::Row) = getfield(r, :rownumber)

Tables.columnnames(r::Row) = getcursor(r).names

function Tables.getcolumn(r::Row, i::Int)
    return getcursor(r).rows[getrownumber(r)][i]
end
Tables.getcolumn(r::Row, nm::Symbol) = Tables.getcolumn(r, getcursor(r).lookup[nm])

Tables.isrowtable(::Type{<:Cursor}) = true
Tables.schema(c::Cursor) = Tables.Schema(c.names, c.types)

Base.eltype(c::Cursor) = Row
Base.length(c::Cursor) = length(c.rows)

function Base.iterate(cursor::Cursor, i=1)
    cursor.current_rownumber = i
    return Row(cursor, i), i + 1
end

"""
    DBInterface.close!(cursor)

Close a cursor.
"""
function DBInterface.close!(cur::Cursor)
    close!(cur.stmt)
end

