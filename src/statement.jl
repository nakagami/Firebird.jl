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


mutable struct Statement <: DBInterface.Statement
    conn::Connection
    sql::String
    handle::Int32
    stmt_type::Int32
    xsqlda::Vector{XSQLVAR}

    function Statement(conn::Connection, sql::String)
        _op_allocate_statement(conn.wp)

        stmt_handle::Int32 = -1
        if (conn.wp.accept_type & ptype_MASK) == ptype_lazy_send
            conn.wp.lazy_response_count += 1
            stmt_handle = -1
        else
            stmt_handle, _, _ = _op_response(wp)
        end

        _op_prepare_statement(conn.wp, conn.transaction.handle, stmt_handle, sql)

        if (conn.wp.accept_type & ptype_MASK) == ptype_lazy_send && conn.wp.lazy_response_count > 0
            conn.wp.lazy_response_count -= 1
            stmt_handle, _, _ = _op_response(conn.wp)
        end

        _, _, buf = _op_response(conn.wp)
        stmt_type, xsqlda = parse_xsqlda(conn.wp, buf, stmt_handle)

        new(conn, sql, stmt_handle, stmt_type, xsqlda)
    end

end

"""
    DBInterface.prepare(conn::Firebird.Connection, sql) => Firebird.Statement

Send a `sql` SQL string to the database to be prepared, returning a `Firebird.Statement` object

"""
function DBInterface.prepare(conn::Connection, sql::AbstractString)::Statement
    Statement(conn, sql)
end

"""
    DBInterface.close!(stmt)

Close a prepared statement.
"""
function DBInterface.close!(stmt::Statement)
    if stmt.handle != -1
        wp = stmt.conn.wp
        _op_free_statement(wp, stmt.handle, DSQL_drop)
        if (wp.accept_type & ptype_MASK) == ptype_lazy_send
            wp.lazy_response_count += 1
        else
            _op_response(wp)
        end
    end
    stmt.handle = -1
end
