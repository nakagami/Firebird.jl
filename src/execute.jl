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

function DBInterface.execute(conn::Connection, stmt::Statement, params=[])::Cursor
    _op_execute(conn.wp, stmt.handle, conn.transaction.handle, params)
    _op_response(conn.wp)

    Cursor(conn, stmt)
end

function DBInterface.execute(conn::Connection, sql::AbstractString, params=[])
    if params == []
        _op_exec_immediate(conn.wp, conn.transaction.handle, sql)
        _op_response(conn.wp)
    else
        stmt = DBInterface.prepare(conn, sql)
        DBInterface.execute(conn, stmt, params)
        clear!(stmt)
    end
    _op_commit(conn.wp, conn.transaction.handle)
end
