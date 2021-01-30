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

using Sockets

function INFO_SQL_SELECT_DESCRIBE_VARS()::Vector{UInt8}
    [
        isc_info_sql_select,
        isc_info_sql_describe_vars,
        isc_info_sql_sqlda_seq,
        isc_info_sql_type,
        isc_info_sql_sub_type,
        isc_info_sql_scale,
        isc_info_sql_length,
        isc_info_sql_null_ind,
        isc_info_sql_field,
        isc_info_sql_relation,
        isc_info_sql_owner,
        isc_info_sql_alias,
        isc_info_sql_describe_end
    ]
end

mutable struct WireChannel
    socket::TCPSocket
    arc4in::Union{Arc4, Nothing}
    arc4out::Union{Arc4, Nothing}
    function WireChannel(socket::TCPSocket)
        new(socket, nothing, nothing)
    end
end

function set_arc4_key(chan::WireChannel, key::Vector{UInt8})
    chan.arc4in = Arc4(key)
    chan.arc4out = Arc4(key)
end

function read(chan::WireChannel, t::DataType)
    bytes::Vector{UInt8} = read(chan.socket, sizeof(t))
    if chan.arc4in != nothing
        bytes = translate(chan.arc4in)
    end
    reinterpret(t, bytes)
end

function write(chan::WireChannel, data::Vector{UInt8})
    if chan.arc4out != nothing
        data = translate(chan.arc4out)
    end
    write(chan.socket, data)
end


struct WireProtocol
    conn::WireChannel
end

function read(wp::WireProtocol, t::DataType)
    read(wp.conn, t)
end

function write(wp::WireProtocol, v)
    write(wp.conn, v)
end
