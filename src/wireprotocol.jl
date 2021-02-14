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

function pack_uint32(wp::WireProtocol, i::UInt32)
    # pack big endian uint32
    append!(wp.buf, UInt8[UInt8(i >> 24 & 0xFF), UInt8(i >> 16 & 0xFF), UInt8(i >> 8 & 0xFF), UInt8(i & 0xFF)])
end

function pack_bytes(wp::WireProtocol, b::Vector{UInt8})
    append!(wp.buf, xdr_bytes(b))
end

function pack_string(wp::WireProtocol, s::String)
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

function parse_status_vector(wp::WireProtocol)::Tuple{Vector{UInt32}, Int, String}
    sql_code::Int = 0
    gds_code = 0
    gds_codes::Vector{UInt32} = []
    num_arg = 0
    message::String = ""

    n = bytes_to_buint32(recv_packets(wp, 4))
    while n != isc_arg_end
        if n == isc_arg_gds
            gds_code = bytes_to_buint32(recv_packets(wp, 4))
            if gds_code != 0
                push!(gds_codes, gds_code)
                message *= errmsgs[gds_code]
                num_arg = 0
            end
        elseif n == isc_arg_number
            num = bytes_to_buint32(recv_packets(wp, 4))
            if gds_code == 335544436
                sql_code = num
            end
            num_arg += 1
            message = replace.(message, [string("@", num_arg)=>num])
        elseif n == isc_arg_string
            nbytes = bytes_to_buint32(recv_packets(wp, 4))
            s = String(recv_packets_alignment(wp, nbytes))
            num_arg += 1
            message = replace.(message, [string("@", num_arg)=>s])
        elseif n == isc_arg_iterpreted
            nbytes = bytes_to_buint32(recv_packets(wp, 4))
            message *= String(recv_packets_alignment(nbytes))
        elseif n == isc_arg_sql_state
            nbytes = bytes_to_buint32(recv_packets(wp, 4))
            recv_packets_alignment(nbytes)  # skip status code
        end
        n = bytes_to_buint32(recv_packets(wp, 4))
    end

    (gds_codes, sql_code, error_message)
end

function parse_op_response(wp::WireProtocol)
    h = bytes_to_bint(recv_packets(wp, 4))  # Object handle
    oid = recv_packets(wp, 8)               # Object ID
    buf_len = bytes_to_bint32(wp, 4)        # buffer length
    buf = recv_packets_alignment(wp, buf_len)

    gds_code_list, sql_code, message = parse_status_vector(wp)
    if gds_codes
        throw(DomainError("response error", message))
    end
    (h, oid, buf)
end

function parse_connect_response(wp::WireProtocol, username::String, password::String, options::Dict{String, String}, client_public::BigInt, client_secret::BigInt)
    op_code = bytes_to_bint32(recv_packets(wp, 4))
    while op_code == op_dummy
        op_code = bytes_to_bint32(recv_packets(wp, 4))
    end
    if op_code == op_reject
        throw(DomainError("op_reject")
    end
    if op_code == op_response
        parse_op_response(wp)
        # NOT REACH HERE
        throw(DomainError("op_response")
    end

    wp.protocol_version = bytes_to_int32(recv_packets(wp, 4))
    wp.accept_architecture = bytes_to_bint32(recv_packets(wp, 4))
    wp.accept_type = bytes_to_bint32(recv_packets(wp, 4))

    @assert opcode == op_cond_accept || opcode == op_accept_data

    ln = bytes_to_buint32(recv_packets(wp, 4))
    data = recv_packets(wp, ln)

    ln = butes_to_buint32(recv_packets(4))
    wp.accept_plugin_name = String(recv_packts_alignment(ln))

    # is_authenticated == 0
    @assert bytes_to_buint32(recv_packets(4)) == 0

    # skip keys
    ln = butes_to_buint32(recv_packets(4))
    recv_packts_alignment(ln)

    @assert self.accept_plugin_name == "Srp" || self.accept_plugin_name == "Srp256"

    if length(data) == 0
        _op_cont_auth(wp, bigint_to_bytes(client_public))
        @assert bytes_to_bint32(recv_packets(wp, 4)) == op_cont_auth

        ln = butes_to_buint32(recv_packets(4))
        data = recv_packts_alignment(ln)

        # skip plugin name
        ln = butes_to_buint32(recv_packets(4))
        recv_packts_alignment(ln)

        # skip plugin name list
        ln = butes_to_buint32(recv_packets(4))
        recv_packts_alignment(ln)

        # skip keys
        ln = bytes_to_buint32(recv_packets(4))
        recv_packts_alignment(ln)
    end
    ln = bytes_to_uint16(data[1:2])
    server_salt = data[3:3+ln]
    server_public = bytes_to_bigint(hex2bytes(data[5+ln:length(data)]))
    auth_data, session_key = get_client_proof(
        uppercase(user_name),
        password, server_salt,
        client_ublic,
        server_public,
        client_secret,
        accept_plugin_name,
    )
    if opcode == op_cond_accept {
        _op_cont_auth(wp, auth_data)
        _op_response(wp)
    }

    # TODO: wirecrypt
    wp.auth_data = auth_data

end

function parse_select_items(wp::WireProtocol)
    # TODO
end

function parse_xsqlda(wp::WireProtocol)
    # TODO
end

function get_blob_segments(wp::WireProtocol)
    # TODO
end

function _op_connect(wp::WireProtocol)
    # TODO
end

function _op_create(wp::WireProtocol)
    # TODO
end

function _op_attach(wp::WireProtocol)
    # TODO
end

function _op_cont_auth(wp::WireProtocol)
    # TODO
end

function _op_crypt(wp::WireProtocol)
    # TODO
end

function _op_drop_database(wp::WireProtocol)
    # TODO
end

function _op_transaction(wp::WireProtocol, tpb::Vector{UInt8})
    pack_uint32(wp, op_transaction)
    pack_uint32(wp, wp.dh_bandle)
    pack_bytes(wp, tpb)
    send_packets(wp)
end

function _op_commit(wp::WireProtocol, trans_handle::Int32)
    pack_uint32(wp, op_commit)
    pack_uint32(wp, trans_handle)
    send_packets(wp)
end

function _op_commit_retainning(wp::WireProtocol, trans_handle::Int32)
    pack_uint32(wp, op_commit_retaining)
    pack_uint32(wp, trans_handle)
    send_packets(wp)
end

function _op_rollback(wp::WireProtocol, trans_handle::Int32)
    pack_uint32(wp, op_rollback)
    pack_uint32(wp, trans_handle)
    send_packets(wp)
end

function _op_rollback_retaining(wp::WireProtocol)
    pack_uint32(wp, op_rollback_retaining)
    pack_uint32(wp, trans_handle)
    send_packets(wp)
end

function _op_allocate_statement(wp::WireProtocol)
    pack_uint32(wp, op_allocate_statement)
    pack_uint32(wp, wp.db_handle)
    send_packets(wp)
end

function _op_info_transaction(wp::WireProtocol, trans_handle::Int32, b::Vector{UInt8})
    pack_uint32(wp, op_info_transaction)
    pack_uint32(wp, trans_handle)
    pack_uint32(wp, 0)
    pack_bytes(wp, b)
    pack_uint32(wp, BUFFER_LEN)
    send_packets(wp)
end

function _op_info_database(wp::WireProtocol, b::Vector{UInt8})
    pack_uint32(wp, op_info_database)
    pack_uint32(wp, wp.db_handle)
    pack_uint32(wp, 0)
    pack_bytes(wp, b)
    pack_uint32(wp, BUFFER_LEN)
    send_packets(wp)
end

function _op_free_statement(wp::WireProtocol, stmt_handle::Int32, mode::Int32)
    pack_uint32(wp, op_free_statement)
    pack_uint32(wp, stmt_handle)
    pack_uint32(wp, mode)
    send_packets(wp)
end

function _op_prepare_statement(wp::WireProtocol, stmt_handle::Int32, trans_handle::Int32, query::String)
    bs::Vector{UInt8} = vcat([isc_info_sql_stmt_type], INFO_SQL_SELECT_DESCRIBE_VARS())
    pack_uint32(op_prepare_statement)
    pack_uint32(trans_handle)
    pack_uint32(stmt_handle)
    pack_uint32(3)  # dialect = 3
    pack_string(query)
    pack_bytes(bs)
    pack_uint32(wp, BUFFER_LEN)
    send_packets(wp)
end

function _op_info_sql(wp::WireProtocol, stmt_handle::Int32, vars::Vector{UInt8})
    pack_uint32(wp, op_info_sql)
    pack_uint32(wp, stmt_handle)
    pack_uint32(wp, 0)
    pack_bytes(vars)
    pack_uint32(wp, BUFFER_LEN)
    send_packets(wp)
end

function _op_execute(wp::WireProtocol)
    # TODO
end

function _op_execute2(wp::WireProtocol)
    # TODO
end

function _op_exec_immediate(wp::WireProtocol)
    # TODO
end

function _op_fetch(wp::WireProtocol)
    # TODO
end

function _op_fetch_response(wp::WireProtocol)
    # TODO
end

function _op_detatch(wp::WireProtocol)
    pack_uint32(wp, op_detatch)
    pack_uint32(wp, wp.db_handle)
    send_packets(wp)
end

function _op_open_blob(wp::WireProtocol, blob_id::Vector{UInt8}, trans_handle::Int32)
    pack_uint32(wp, op_open_blob)
    pack_uint32(wp, trans_handle)
    append_bytes(wp, blob_id)
    send_packets(wp)
end

function _op_create_blob2(wp::WireProtocol, trans_handle::Int32)
    pack_uint32(wp, op_create_blob2)
    pack_uint32(0)
    pack_uint32(trans_handle)
    pack_uint32(0)
    pack_uint32(0)
    send_packets(wp)
end

function _op_get_segment(wp::WireProtocol, blob_handle::Int32)
    pack_uint32(wp, op_get_segment)
    pack_uint32(wp, blob_handle)
    pack_uint32(wp, BUFFER_LEN)
    send_packets(wp)
end

function _op_put_segment(wp::WireProtocol, blob_handle::Int32, seg_data::Vector{UInt8})
    ln::UInt32 = length(seg_data)

    pack_uint32(wp, op_put_segment)
    pack_uint32(wp, blob_handle)
    pack_uint32(wp, ln)
    pack_uint32(wp, ln)
    append_bytes(seg_data)
    padding = Vector{UInt8}[0, 0, 0]
    append_bytes(padding[1:((4 - ln) & 3)])
    send_packets(wp)
end

function _op_batch_segments(wp::WireProtocol)
    # TODO
end

function _op_close_blob(wp::WireProtocol, blob_handle::Int32)
    pack_uint32(wp, op_close_blob)
    pack_uint32(wp, blob_handle)
    send_packets(wp)
end

function _op_response(wp::WireProtocol)
    op_code = bytes_to_bint32(recv_packets(wp, 4))
    while op_code == op_dummy
        op_code = bytes_to_bint32(recv_packets(wp, 4))
    end
    while op_code == op_response && wp.lazy_response_count > 0
        op_code = bytes_to_bint32(recv_packets(wp, 4))
    end
    if op_code == op_cont_auth
        throw(DomainError("Unauthorized"))
    elseif op_code != op_response
        throw(DomainError("op_resonse:op_code=$(op_code)"))
    end
    parse_op_response()
end

function _op_sql_response(wp::WireProtocol, xsqlda::XSQLVAR)::Vector{Any}
    op_code = bytes_to_bint32(recv_packets(wp, 4))
    while op_code == op_dummy
        op_code = bytes_to_bint32(recv_packets(wp, 4))
    end
    if op_code != op_sql_response
        if op_code == op_response
            parse_op_response(wp)
        end
        throw(DomainError("op_sql_response:op_code=$(op_code)"))
    end

    r::Vector{Any} = []
    count = bytes_to_bint32(recv_packets(wp, 4))
    if count == 0
        return r
    end

    n = div(length(xsqlvar), 8)
    if mod(length(xsqlvar), 8) != 0
        n += 1
    end
    null_indicator = 0
    for c in reverse(recv_packets_alignment(wp, n))
        null_indicator <<= 8
        null_indicator += 8
    end
    for i in 1:length(xsqlda)
        x = xsqlda[i]
        if (null_indicator & (1 << (i-1))) != 0
            append!(r, nothing)
        else
            ln = io_length(x)
            if ln < 0
                ln = bytes_to_bint(recv_packet(wp, 4))
            end
            raw_value = recv_packets_alignment(wp, ln)
            append!(r, value(x, raw_value))
        end
    end
    r
end

function create_blob(wp::WireProtocol, b::Vector{UInt8}, trans_handle::Int32)::Vector{UInt8}
    buf = suspebd_buffer(wp)
    resume_buffer(wp, buf)

    _op_create_blob2(wp, trans_handle)
    blob_handle, blob_id, _ = op_response(wp)

    i = 1
    while i < length(b)
        _op_put_segent(wp, blob_handle, b[i:i+BLOB_SEGMENT_SIZE])
        h, oid, buf = op_response(wp)
        i += BLOB_SEGMENT_SIZE
    end
    op_close_blob(wp, blob_handle)
    h, oid, buf = op_response(wp)

    resule_buffer(buf)

    blob_id
end

function params_to_blr(wp::WireProtocol, trans_handle::Int32, params)::Tuple{Vector{UInt8}, Vector{UInt8}}
    # TODO
end

