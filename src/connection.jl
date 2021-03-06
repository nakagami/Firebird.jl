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


mutable struct Connection <: DBInterface.Connection
    wp::Firebird.WireProtocol

    function Connection(host::String, username::String, password::String, db_name::String, opts::Dict)
        username = uppercase(username)
        port = UInt16(haskey(opts, "port") ? opts["port"] : 3050)
        wire_crypt = Bool(haskey(opts, "wire_crypt") ? opts["wire_crypt"] : true)
        create_new = Bool(haskey(opts, "create_new") ? opts["create_new"] : false)

        wp = WireProtocol(host, username, password, port)
        client_public, client_secret = get_client_seed()
        _op_connect(wp, db_name, username, password, wire_crypt, client_public)
        parse_connect_response(wp, username, password, wire_crypt, client_public, client_secret)

        # TODO

        new(wp)
    end

end

function close!(conn::Connection)
    close!(conn.wp.chan)
end

function isopen(conn::Connection)::Bool
    isopen(conn.wp.chan)
end
