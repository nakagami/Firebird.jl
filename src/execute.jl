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

function fetch_records(conn::Connection, stmt::Statement)::Vector{Vector{Any}}
    more_data = true
    results::Vector{Vector{Any}} = [[]]

    while more_data
        _op_fetch(conn.wp, stmt.handle, calc_blr(stmt.xsqlda))
        rows_segments, more_data = _op_fetch_response(conn.wp, stmt.handle, stmt.xsqlda)
        results = vcat(results, rows_segments)
    end

    # TODO: Convert BLOB handle to data
    println(results)
    results
end

function DBInterface.execute(conn::Connection, stmt::Statement, params=[])::Cursor
    _op_execute(conn.wp, stmt.handle, conn.transaction.handle, params)
    _op_response(conn.wp)
    rows = fetch_records(conn, stmt)

    Cursor(conn, stmt, rows)
end

function DBInterface.execute(conn::Connection, sql::AbstractString, params=[])::Cursor
    stmt = DBInterface.prepare(conn, sql)
    DBInterface.execute(conn, stmt, params)
end
