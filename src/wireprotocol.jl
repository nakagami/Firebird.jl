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

const PLUGIN_LIST = "Srp256,Srp"
const BUFFER_LEN = 1024
const MAX_CHAR_LENGTH = 32767
const BLOB_SEGMENT_SIZE = 32000

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
    sock::TCPSocket
    arc4in::Union{Arc4, Nothing}
    arc4out::Union{Arc4, Nothing}
    function WireChannel(host::String, port::Int)
        sock = Sockets.connect(host, port)
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


mutable struct WireProtocol
    write_buf::Vector{UInt8}

    channel::WireChannel
    host::String
    port::Int
    username::String
    password::String

    db_handle::Int32

    protocol_version::Int32
    accept_architecture::Int32
    accept_type::Int32
    lazy_response_count::Int

    accept_plugin_name::String
    auth_data::Vector{UInt8}

    timezone::String

    function WireProtocol(host::AbstractString, port::Integer)
        channel = WireChannel(host, port)
        new([], channel, host, port, "", "", -1, -1, -1, -1, 0, "", [], "")
    end
end

function pack_u32(wp::WireProtocol, i::UInt32)
    # pack big endian uint32
    append!(wp.buf, UInt8[UInt8(i >> 24 & 0xFF), UInt8(i >> 16 & 0xFF), UInt8(i >> 8 & 0xFF), UInt8(i & 0xFF)])
end

function pack_bytes(wp::WireProtocol, b::Vector{UInt8})
    append!(wp.buf, xdr_bytes(b))
end

function pack_str(wp::WireProtocol, s::String)
    append!(wp.buf, xdr_bytes(Vector{UInt8}(s)))
end

function append_bytes(wp::WireProtocol, b::Vector{UInt8})
    append!(wp.buf, b)
end

function get_srp_client_public_bytes(client_public::BigInt)::Vector{UInt8}
    b::Vec{UInt8} = bytes2hex(bigint_to_bytes(client_public))
    if length(b) > 254
        vcat(
            UInt8[CNCT_SPECIFIC_DATA, 255, 0],
            b[1:254],
            UInt8[CNCT_SPECIFIC_DATA, length(b) - 254 + 1, 1],
            b[255:length(b)]
        )
    else
        vcat(
            UInt8[CNCT_SPECIFIC_DATA, length(b) + 1, 0],
            b[1:length(b) + 1],
            UInt8[CNCT_SPECIFIC_DATA, length(b) - 254 + 1, 1],
            b
        )
    end
end

function uid(user::String, password::String, auth_plugin_name::String, wire_crypt::Bool, client_public::BigInt)::Vec{UInt8}
    sys_user = if haskey(ENV, "USER")
            ENV["USER"]
        elseif haskey(ENV, "USERNAME")
            ENV["USERNAME"]
        else
            ""
        end
    sys_user_bytes = Vec{UInt8}(sys_user)
    hostname_bytes = Vec{UInt8}(gethostname)
    plugin_list_name_bytes = Vec{UInt8}(PLUGIN_LIST)
    plugin_name_bytes = Vec{UInt8}(auth_plugin_name)
    user_bytes = Vec{UInt8}(user)
    specific_data = get_srp_client_public_bytes(client_public)
    vcat(
        UInt8[CNCT_login, length(user_bytes)], user_bytes,
        UInt8[CNCT_plugin_name, length(plugin_name_bytes)], plugin_name_bytes,
        UInt8[CNCT_plugin_list, length(plugin_list_name_bytes)], plugin_list_name_bytes,
        specific_data,
        UInt8[CNCT_client_crypt, 4, wire_crypt ? 1 : 0, 0, 0],
        UInt8[CNCT_user, length(sys_user_bytes)], sys_user_bytes,
        UInt8[CNCT_host, length(hostname_bytes)], hostname_bytes,
        UINt8[CNCT_user_verification, 0]
    )
end

function send_packets(wp::WireProtocol)
    wp.channel.write(wp.write_buf)
    wp.write_buf = []
end

function suspend_buffer(wp::WireProtocol)::Vector{UInt8}
    deepcopy(wp.write_buf)
end

function resume_buffer(wp::WireProtocol, buf::Vector{UInt8})
    append!(wp.write_buf, buf)
end

function recv_packets(wp::WireProtocol, n::Int)::Vector{UInt8}
    buf = zeros(UInt8, n)
    read(wp.conn, buf)
    buf
end

function recv_packets_alignment(wp::WireProtocol, n::Int)::Vector{UInt8}
    padding = n % 4
    if padding > 0
        padding = 4 - padding
    end
    buf = recv_packets(n + padding)
    buf[1:n]
end

function parse_status_vector(wp::WireProtocol)::Tuple{Vec{UInt32}, Int, String}
    # TODO
    sql_code::Int = 0
    gds_codes::Vec{UInt32} = []
    error_message::String = ""      # TODO: fill error message

    (gds_codes, sql_code, error_message)
end

function _op_connect(wp::WireProtocol)
end
