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


mutable struct Statement <: DBInterface.Statement
    conn::Connection
    sql::String
    stmt_handle::Int32

    function Statement(conn::Connection, sql::String)
        _op_allocate_statement(conn.wp)
        op_code = bytes_to_bint32(recv_packets(conn.wp, 4))
        while op_code == op_response && conn.wp.lazy_response_count > 0
            conn.wp.lazy_response_count -= 1
            op_code = bytes_to_bint32(recv_packets(conn.wp, 4))
        end
        stmt_handle, _, _ = parse_op_response(conn.wp)

        _op_prepare_statement(conn.wp, stmt_handle, sql)
        op_code = bytes_to_bint32(recv_packets(conn.wp, 4))
        while op_code == op_response && conn.wp.lazy_response_count > 0
            conn.wp.lazy_response_count -= 1
            op_code = bytes_to_bint32(recv_packets(conn.wp, 4))
        end
        _, _, buf = parse_op_response(conn.wp)
        # TODO: parse_sqlda and get stmt_type

        new(conn, sql, stmt_handle)
    end

end

function DBInterface.prepare(conn::Connection, sql::AbstractString)
    Statement(conn, sql)
end

function DBInterface.close!(stmt::Statement)
    wp = stmt.conn.wp
    _op_free_statement(wp, stmt.stmt_handle, DSQL_drop)
    op_code = bytes_to_bint32(recv_packets(wp, 4))
    while op_code == op_response && wp.lazy_response_count > 0
        wp.lazy_response_count -= 1
        op_code = bytes_to_bint32(recv_packets(wp, 4))
    end
end
