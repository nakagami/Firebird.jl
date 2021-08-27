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

using Sockets

const PLUGIN_LIST = "Srp256,Srp"
const BUFFER_LEN = 1024
const MAX_CHAR_LENGTH = 32767
const BLOB_SEGMENT_SIZE = 32000

function DEBUG_OUTPUT(s)
    # println(s)
end

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
    socket::Union{TCPSocket, Nothing}
    arc4in::Union{Arc4, Nothing}
    arc4out::Union{Arc4, Nothing}
    function WireChannel(host::String, port::UInt16)
        socket = Sockets.connect(host, port)
        new(socket, nothing, nothing)
    end
end

function set_arc4_key(chan::WireChannel, key::Vector{UInt8})
    chan.arc4in = Arc4(key)
    chan.arc4out = Arc4(key)
end

function recv(chan::WireChannel, nbytes::Int)::Vector{UInt8}
    data::Vector{UInt8} = zeros(UInt8, nbytes)
    read!(chan.socket, data)
    if chan.arc4in != nothing
        data = translate(chan.arc4in, data)
    end
    data
end

function send(chan::WireChannel, data::Vector{UInt8})
    if chan.arc4out != nothing
        data = translate(chan.arc4out, data)
    end
    write(chan.socket, data)
end

function close!(chan::WireChannel)
    if chan.socket != nothing
        close(chan.socket)
        chan.socket = nothing
    end
end

function isopen(chan::WireChannel)::Bool
    chan.socket != nothing
end

mutable struct WireProtocol
    buf::Vector{UInt8}

    chan::WireChannel
    host::String
    port::UInt16
    username::String
    password::String

    db_handle::Int32
    trans_handle::Int32

    protocol_version::Int32
    accept_architecture::Int32
    accept_type::Int32
    lazy_response_count::Int

    accept_plugin_name::String
    auth_data::Vector{UInt8}

    timezone::String

    function WireProtocol(host::AbstractString, user::AbstractString, password::AbstractString, port::UInt16)
        chan = WireChannel(host, port)
        new([], chan, host, port, user, password, -1, -1, -1, -1, -1, 0, "", [], "")
    end
end

function pack_uint32(wp::WireProtocol, i::Int)
    wp.buf = vcat(wp.buf, UInt8[UInt8(i >> 24 & 0xFF), UInt8(i >> 16 & 0xFF), UInt8(i >> 8 & 0xFF), UInt8(i & 0xFF)])
end

function pack_uint32(wp::WireProtocol, i::Int32)
    wp.buf = vcat(wp.buf, UInt8[UInt8(i >> 24 & 0xFF), UInt8(i >> 16 & 0xFF), UInt8(i >> 8 & 0xFF), UInt8(i & 0xFF)])
end

function pack_uint32(wp::WireProtocol, i::UInt32)
    # pack big endian uint32
    wp.buf = vcat(wp.buf, UInt8[UInt8(i >> 24 & 0xFF), UInt8(i >> 16 & 0xFF), UInt8(i >> 8 & 0xFF), UInt8(i & 0xFF)])
end

function pack_bytes(wp::WireProtocol, b::Vector{UInt8})::Vector{UInt8}
    wp.buf = vcat(wp.buf, xdr_bytes(b))
end

function pack_string(wp::WireProtocol, s::String)
    wp.buf = vcat(wp.buf, xdr_bytes(Vector{UInt8}(s)))
end

function append_bytes(wp::WireProtocol, b::Vector{UInt8})
    wp.buf = vcat(wp.buf, b)
end

function get_srp_client_public_bytes(client_public::BigInt)::Vector{UInt8}
    b::Vector{UInt8} = Vector{UInt8}(bytes2hex(bigint_to_bytes(client_public)))
    if length(b) > 254
        vcat(
            UInt8[CNCT_specific_data, 255, 0],
            b[1:254],
            UInt8[CNCT_specific_data, length(b) - 254 + 1, 1],
            b[255:length(b)]
        )
    else
        vcat(
            UInt8[CNCT_specific_data, length(b) + 1, 0],
            b[1:length(b) + 1],
            UInt8[CNCT_specific_data, length(b) - 254 + 1, 1],
            b
        )
    end
end

function uid(username::String, password::String, auth_plugin_name::String, wire_crypt::Bool, client_public::BigInt)::Vector{UInt8}
    sys_user = if haskey(ENV, "USER")
            ENV["USER"]
        elseif haskey(ENV, "USERNAME")
            ENV["USERNAME"]
        else
            ""
        end
    sys_user_bytes = Vector{UInt8}(sys_user)
    hostname_bytes = Vector{UInt8}(gethostname())
    plugin_list_name_bytes = Vector{UInt8}(PLUGIN_LIST)
    plugin_name_bytes = Vector{UInt8}(auth_plugin_name)
    username_bytes = Vector{UInt8}(username)
    specific_data = get_srp_client_public_bytes(client_public)
    vcat(
        UInt8[CNCT_login, length(username_bytes)], username_bytes,
        UInt8[CNCT_plugin_name, length(plugin_name_bytes)], plugin_name_bytes,
        UInt8[CNCT_plugin_list, length(plugin_list_name_bytes)], plugin_list_name_bytes,
        specific_data,
        UInt8[CNCT_client_crypt, 4, wire_crypt ? 1 : 0, 0, 0, 0],
        UInt8[CNCT_user, length(sys_user_bytes)], sys_user_bytes,
        UInt8[CNCT_host, length(hostname_bytes)], hostname_bytes,
        UInt8[CNCT_user_verification, 0]
    )
end

function send_packets(wp::WireProtocol)
    send(wp.chan, wp.buf)
    wp.buf = []
end

function suspend_buffer(wp::WireProtocol)::Vector{UInt8}
    deepcopy(wp.buf)
end

function resume_buffer(wp::WireProtocol, buf::Vector{UInt8})
    append!(wp.buf, buf)
end

function recv_packets(wp::WireProtocol, n::Int)::Vector{UInt8}
    recv(wp.chan, n)
end

function recv_packets(wp::WireProtocol, n::UInt32)::Vector{UInt8}
    recv_packets(wp, Int(n))
end

function recv_packets_alignment(wp::WireProtocol, n::UInt32)::Vector{UInt8}
    padding = n % 4
    if padding > 0
        padding = 4 - padding
    end
    buf = recv_packets(wp, UInt32(n + padding))
    buf[1:n]
end

function recv_packets_alignment(wp::WireProtocol, n::Int32)::Vector{UInt8}
    recv_packets_alignment(wp, UInt32(n))
end

function recv_packets_alignment(wp::WireProtocol, n::Int64)::Vector{UInt8}
    recv_packets_alignment(wp, UInt32(n))
end

function parse_status_vector(wp::WireProtocol)::Tuple{Vector{UInt32}, Int, String}
    sql_code::Int = 0
    gds_code = 0
    gds_codes::Vector{UInt32} = []
    num_arg = 0
    message::String = ""

    errmsgs = get_errmsgs()

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
            message = replace.(message, [string("@", num_arg)=>num])[1]
        elseif n == isc_arg_string
            nbytes = bytes_to_buint32(recv_packets(wp, 4))
            s = String(recv_packets_alignment(wp, nbytes))
            num_arg += 1
            message = replace.(message, [string("@", num_arg)=>s])[1]
        elseif n == isc_arg_iterpreted
            nbytes = bytes_to_buint32(recv_packets(wp, 4))
            message *= String(recv_packets_alignment(wp, nbytes))
        elseif n == isc_arg_sql_state
            nbytes = bytes_to_buint32(recv_packets(wp, 4))
            recv_packets_alignment(wp, nbytes)  # skip status code
        end
        n = bytes_to_buint32(recv_packets(wp, 4))
    end

    (gds_codes, sql_code, message)
end

function parse_op_response(wp::WireProtocol)::Tuple{Int32, Vector{UInt8}, Vector{UInt8}}
    h = bytes_to_bint32(recv_packets(wp, 4))            # Object handle
    oid = recv_packets(wp, 8)                           # Object ID
    buf_len = Int(bytes_to_bint32(recv_packets(wp, 4))) # buffer length
    buf = recv_packets_alignment(wp, buf_len)

    gds_codes, sql_code, message = parse_status_vector(wp)
    if length(gds_codes) != 0
        throw(DomainError("response error", message))
    end
    (h, oid, buf)
end

function parse_connect_response(wp::WireProtocol, username::String, password::String, wire_crypt::Bool, client_public::BigInt, client_secret::BigInt)
    DEBUG_OUTPUT("parse_connect_response")
    op_code = bytes_to_bint32(recv_packets(wp, 4))
    while op_code == op_dummy
        op_code = bytes_to_bint32(recv_packets(wp, 4))
    end
    if op_code == op_reject
        throw(DomainError("op_reject"))
    end
    if op_code == op_response
        parse_op_response(wp)
        # NOT REACH HERE?
        throw(DomainError("op_response"))
    end

    wp.protocol_version = bytes_to_int32(recv_packets(wp, 4))
    wp.accept_architecture = bytes_to_bint32(recv_packets(wp, 4))
    wp.accept_type = bytes_to_bint32(recv_packets(wp, 4))

    @assert op_code == op_cond_accept || op_code == op_accept_data

    ln = bytes_to_buint32(recv_packets(wp, 4))
    data = recv_packets_alignment(wp, ln)

    ln = bytes_to_buint32(recv_packets(wp, 4))
    wp.accept_plugin_name = String(recv_packets_alignment(wp, ln))

    # is_authenticated == 0
    @assert bytes_to_buint32(recv_packets(wp, 4)) == 0

    # skip keys
    ln = bytes_to_buint32(recv_packets(wp, 4))
    recv_packets_alignment(wp, ln)

    @assert wp.accept_plugin_name == "Srp" || wp.accept_plugin_name == "Srp256"

    if length(data) == 0
        _op_cont_auth(wp, bigint_to_bytes(client_public), wp.accept_plugin_name, "")
        @assert bytes_to_bint32(recv_packets(wp, 4)) == op_cont_auth

        ln = bytes_to_buint32(recv_packets(wp, 4))
        data = recv_packets_alignment(wp, ln)

        # skip plugin name
        ln = bytes_to_buint32(recv_packets(wp, 4))
        recv_packets_alignment(wp, ln)

        # skip plugin name list
        ln = bytes_to_buint32(recv_packets(wp, 4))
        recv_packets_alignment(wp, ln)

        # skip keys
        ln = bytes_to_buint32(recv_packets(wp, 4))
        recv_packets_alignment(wp, ln)
    end
    ln = bytes_to_uint16(data[1:2])
    server_salt = data[3:ln+2]
    server_public_string = data[5+ln:length(data)]
    if length(server_public_string) % 2 != 0
        server_public_string = vcat(Vector{UInt8}([0x30]), server_public_string)
    end
    server_public = bytes_to_bigint(hex2bytes(server_public_string))

    auth_data, session_key = get_client_proof(
        uppercase(username),
        password,
        server_salt,
        client_public,
        server_public,
        client_secret,
        wp.accept_plugin_name,
    )
    if op_code == op_cond_accept
        _op_cont_auth(wp, auth_data, wp.accept_plugin_name, "")
        _op_response(wp)
    end

    if wire_crypt && session_key != nothing
        _op_crypt(wp)
        set_arc4_key(wp.chan, session_key)
        _op_response(wp)
    else
        wp.auth_data = auth_data
    end

end

function parse_select_items(wp::WireProtocol, buf::Vector{UInt8}, xsqlda::Vector{XSQLVAR})::Int
    ln = 0
    index = 0
    i = 1

    item = buf[i]
    while i <= length(buf) && buf[i] != isc_info_end
        item = buf[i]
        i += 1
        if item ==  isc_info_sql_sqlda_seq
            ln = bytes_to_int16(buf[i:i+1])
            i += 2
            index = bytes_to_int32(buf[i:i+ln-1])
            i += ln
        elseif item == isc_info_sql_type
            ln = bytes_to_int16(buf[i:i+1])
            i += 2
            sqltype = bytes_to_int32(buf[i:i+ln-1])
            if sqltype % 2 != 0
                    sqltype -= 1
            end
            xsqlda[index].sqltype = sqltype
            i += ln
        elseif item == isc_info_sql_sub_type
            ln = bytes_to_int16(buf[i:i+1])
            i += 2
            xsqlda[index].sqlsubtype = bytes_to_int32(buf[i:i+ln-1])
            i += ln
        elseif item == isc_info_sql_scale
            ln = bytes_to_int16(buf[i:i+1])
            i += 2
            xsqlda[index].sqlscale = bytes_to_int32(buf[i:i+ln-1])
            i += ln
        elseif item == isc_info_sql_length
            ln = bytes_to_int16(buf[i:i+1])
            i += 2
            xsqlda[index].sqllen = bytes_to_int32(buf[i:i+ln-1])
            i += ln
        elseif item == isc_info_sql_null_ind
            ln = bytes_to_int16(buf[i:i+1])
            i += 2
            xsqlda[index].null_ok = bytes_to_int32(buf[i:i+ln-1]) != 0
            i += ln
        elseif item == isc_info_sql_field
            ln = bytes_to_int16(buf[i:i+1])
            i += 2
            xsqlda[index].fieldname = bytes_to_str(buf[i:i+ln-1])
            i += ln
        elseif item == isc_info_sql_relation
            ln = bytes_to_int16(buf[i:i+1])
            i += 2
            xsqlda[index].relname = bytes_to_str(buf[i:i+ln-1])
            i += ln
        elseif item == isc_info_sql_owner
            ln = bytes_to_int16(buf[i : i+1])
            i += 2
            xsqlda[index].ownname = bytes_to_str(buf[i:i+ln-1])
            i += ln
        elseif item == isc_info_sql_alias
            ln = bytes_to_int16(buf[i : i+1])
            i += 2
            xsqlda[index].aliasname = bytes_to_str(buf[i:i+ln-1])
            i += ln
        elseif item == isc_info_truncated
            return index        # return next index
        elseif item == isc_info_sql_describe_end
            # NOTHING
        else
            throw(DomainError("Invalid item", "$i:$(buf[i])"))
        end
    end

    -1  # no more info
end

function parse_xsqlda(wp::WireProtocol, buf::Vector{UInt8}, stmt_handle::Int32)::Tuple{Int, Vector{XSQLVAR}}
    stmt_type::Int = 0
    xsqlda::Vector{XSQLVAR} = []
    i = 1

    while i <= length(buf)
        if buf[i] == UInt8(isc_info_sql_stmt_type) && buf[i+1] == UInt8(0x04) && buf[i+2] == UInt8(0x00)
            i += 1
            ln = bytes_to_int16(buf[i : i+1])
            i += 2
            stmt_type = bytes_to_int32(buf[i : i+ln-1])
            i += ln
        elseif buf[i] == UInt8(isc_info_sql_select) && buf[i+1] == UInt8(isc_info_sql_describe_vars)
            i += 2
            ln = bytes_to_int16(buf[i : i+1])
            i += 2
            col_len = bytes_to_int32(buf[i:i+ln-1])
            if col_len != 0
                for _ in range(1, length=col_len)
                    xsqlvar = XSQLVAR(0, 0, 0, 0, false, "", "", "", "")
                    push!(xsqlda, xsqlvar)
                end
                next_index = parse_select_items(wp, buf[i+ln:length(buf)-1], xsqlda)
                while next_index > 0    # more describe vars
                    _op_info_sql(stmt_handle,
                        vcat(
                            Vector{UInt8}([isc_info_sql_sqlda_start, 2]),
                            int16_to_bytes(int16(next_index)),
                            INFO_SQL_SELECT_DESCRIBE_VARS(),
                        )
                    )
                    _, _, buf = op_response(wp)
                    # buf[1:2] == [0x04,0x07]
                    ln = bytes_to_int16(buf[3:4])
                    # bytes_to_int(buf[5:5+ln]) == col_len
                    next_index = p._parse_select_items(buf[5+ln:length(buf)-1], xsqlda)
                end
            end
        else
            break
        end
    end

    stmt_type, xsqlda
end

function get_blob_segments(wp::WireProtocol, blob_id::Vector{UInt8}, trans_handle::Int32)::Vector{UInt8}
    suspend_buf = suspend_buffer(wp)
    blob::Vector{UInt8} = []
    _op_open_blob(wp, blob_id, trans_handle)
    blob_handle, _, _ = _op_response(wp)

    more_data = 1
    while more_data != 2
        _op_get_segment(wp, blob_handle)
        more_data, _, buf = _op_response(wp)
        while length(buf) > 0
            ln = bytes_to_int16(buf[1:2])
            blob = vcat(blob, buf[3:ln+2])
            buf = buf[ln+3:length(buf)]
        end
    end

    _op_close_blob(wp, blob_handle)
    if wp.accept_type == ptype_lazy_send
        wp.lazy_response_count += 1
    else
        _op_response(wp)
    end

    resume_buffer(wp, suspend_buf)
    blob
end

function _op_connect(wp::WireProtocol, db_name::String, username::String, password::String, wire_crypt::Bool, client_public::BigInt)
    DEBUG_OUTPUT("_op_connect")
    # PROTOCOL_VERSION, Arch type (Generic=1), min, max, weight = 13, 1, 0, 5, 8
    protocols = hex2bytes("ffff800d00000001000000000000000500000008")
    protocols_len = div(length(protocols), 20)

    pack_uint32(wp, op_connect)
    pack_uint32(wp, op_attach)
    pack_uint32(wp, 3)  # CONNECT_VERSION3
    pack_uint32(wp, 1)  # Arc type(GENERIC)
    pack_string(wp, db_name)
    pack_uint32(wp, protocols_len)  # number of protocols
    pack_bytes(wp, uid(username, password, "Srp256", wire_crypt, client_public))
    append_bytes(wp, protocols)
    send_packets(wp)
end

function _op_create(wp::WireProtocol, db_name::String, username::String, password::String, page_size::Int32)
    DEBUG_OUTPUT("_op_create")
    encode = b"UTF8"

    username_bytes = Vector{UInt8}(username)
    password_bytes = Vector{UInt8}(password)
    dpb::Vector{UInt8} = []

    dpb = vcat(
        [isc_dpb_version1],
        [isc_dpb_set_db_charset, UInt8(length(encode))], encode,
        [isc_dpb_lc_ctype, UInt8(length(encode))], encode,
        [isc_dpb_user_name, UInt8(length(username_bytes))], username_bytes,
        [isc_dpb_password, UInt8(length(password_bytes))], password_bytes,
        [isc_dpb_sql_dialect, 4], int32_to_bytes(Int32(3)),
        [isc_dpb_force_write, 4], int32_to_bytes(Int32(1)),
        [isc_dpb_overwrite, 4], int32_to_bytes(Int32(1)),
        [isc_dpb_page_size, 4], int32_to_bytes(page_size),
    )

    if length(wp.auth_data) != 0
        specific_auth_data = Vector{UInt8}(bytes2hex(wp.auth_data))
        dpb = vcat(dpb, [isc_dpb_specific_auth_data, length(specific_auth_data)], specific_auth_data)
    end

    if wp.timezone != ""
        tzname_bytes = Vector{UInt8}(wp.timezone)
        dpb = vcat(dpb, [isc_dpb_session_time_zone, length(tzname_bytes)], tzname_bytes)
    end

    pack_uint32(wp, op_create)
    pack_uint32(wp, 0)
    pack_string(wp, db_name)
    pack_bytes(wp, dpb)
    send_packets(wp)
end

function _op_attach(wp::WireProtocol, db_name::String, username::String, password::String)
    DEBUG_OUTPUT("_op_attach")
    encode = b"UTF8"

    username_bytes = Vector{UInt8}(username)
    password_bytes = Vector{UInt8}(password)

    dpb::Vector{UInt8} = vcat(
        [UInt8(isc_dpb_version1)],
        [UInt8(isc_dpb_set_db_charset), UInt8(length(encode))], encode,
        [UInt8(isc_dpb_lc_ctype), UInt8(length(encode))], encode,
        [UInt8(isc_dpb_user_name), UInt8(length(username_bytes))], username_bytes,
        [UInt8(isc_dpb_password), UInt8(length(password_bytes))], password_bytes,
        [UInt8(isc_dpb_sql_dialect), UInt8(4)], int32_to_bytes(Int32(3)),
    )


    if length(wp.auth_data) != 0
        specific_auth_data = Vector{UInt8}(bytes2hex(wp.auth_data))
        dpb = vcat(dpb, [UInt8(isc_dpb_specific_auth_data), UInt8(length(specific_auth_data))], specific_auth_data)
    end

    if wp.timezone != ""
        tzname_bytes = Vector{UInt8}(wp.timezone)
        dpb = vcat(dpb, [isc_dpb_session_time_zone, length(tzname_bytes)], tzname_bytes)
    end

    pack_uint32(wp, op_attach)
    pack_uint32(wp, 0)
    pack_string(wp, db_name)
    pack_bytes(wp, dpb)
    send_packets(wp)
end

function _op_cont_auth(wp::WireProtocol, auth_data::Vector{UInt8}, auth_plugin_name::String, keys::String)
    DEBUG_OUTPUT("_op_cont_auth")
    pack_uint32(wp, op_cont_auth)
    pack_string(wp, bytes2hex(auth_data))
    pack_string(wp, auth_plugin_name)
    pack_string(wp, "Srp256,Srp")
    pack_string(wp, keys)
    send_packets(wp)
end

function _op_crypt(wp::WireProtocol)
    DEBUG_OUTPUT("_op_crypt")
    pack_uint32(wp, op_crypt)
    pack_string(wp, "Arc4")
    pack_string(wp, "Symmetric")
    send_packets(wp)
end

function _op_drop_database(wp::WireProtocol)
    DEBUG_OUTPUT("_op_drop_database")
    pack_uint32(wp, op_drop_database)
    pack_uint32(wp, wp.db_handle)
    send_packets(wp)
end

function _op_transaction(wp::WireProtocol, tpb::Vector{UInt8})
    DEBUG_OUTPUT("_op_transaction")
    pack_uint32(wp, op_transaction)
    pack_uint32(wp, wp.db_handle)
    pack_bytes(wp, tpb)
    send_packets(wp)
end

function _op_commit(wp::WireProtocol, trans_handle::Int32)
    DEBUG_OUTPUT("_op_commit")
    pack_uint32(wp, op_commit)
    pack_uint32(wp, trans_handle)
    send_packets(wp)
end

function _op_commit_retainning(wp::WireProtocol, trans_handle::Int32)
    DEBUG_OUTPUT("_op_commit_retainning")
    pack_uint32(wp, op_commit_retaining)
    pack_uint32(wp, trans_handle)
    send_packets(wp)
end

function _op_rollback(wp::WireProtocol, trans_handle::Int32)
    DEBUG_OUTPUT("_op_rollback")
    pack_uint32(wp, op_rollback)
    pack_uint32(wp, trans_handle)
    send_packets(wp)
end

function _op_rollback_retaining(wp::WireProtocol)
    DEBUG_OUTPUT("_op_rollback_retaining")
    pack_uint32(wp, op_rollback_retaining)
    pack_uint32(wp, trans_handle)
    send_packets(wp)
end

function _op_allocate_statement(wp::WireProtocol)
    DEBUG_OUTPUT("_op_allocate_statement")
    pack_uint32(wp, op_allocate_statement)
    pack_uint32(wp, wp.db_handle)
    send_packets(wp)
end

function _op_info_transaction(wp::WireProtocol, trans_handle::Int32, b::Vector{UInt8})
    DEBUG_OUTPUT("_op_info_transaction")
    pack_uint32(wp, op_info_transaction)
    pack_uint32(wp, trans_handle)
    pack_uint32(wp, 0)
    pack_bytes(wp, b)
    pack_uint32(wp, BUFFER_LEN)
    send_packets(wp)
end

function _op_info_database(wp::WireProtocol, b::Vector{UInt8})
    DEBUG_OUTPUT("_op_info_database")
    pack_uint32(wp, op_info_database)
    pack_uint32(wp, wp.db_handle)
    pack_uint32(wp, 0)
    pack_bytes(wp, b)
    pack_uint32(wp, BUFFER_LEN)
    send_packets(wp)
end

function _op_free_statement(wp::WireProtocol, stmt_handle::Int32, mode::Int)
    DEBUG_OUTPUT("_op_free_statement")
    pack_uint32(wp, op_free_statement)
    pack_uint32(wp, stmt_handle)
    pack_uint32(wp, mode)
    send_packets(wp)
end

function _op_prepare_statement(wp::WireProtocol, trans_handle::Int32, stmt_handle::Int32, query::String)
    DEBUG_OUTPUT("_op_prepare_statement")
    bs::Vector{UInt8} = vcat([isc_info_sql_stmt_type], INFO_SQL_SELECT_DESCRIBE_VARS())
    pack_uint32(wp, op_prepare_statement)
    pack_uint32(wp, trans_handle)
    pack_uint32(wp, stmt_handle)
    pack_uint32(wp, 3)  # dialect = 3
    pack_string(wp, query)
    pack_bytes(wp, bs)
    pack_uint32(wp, BUFFER_LEN)
    send_packets(wp)
end

function _op_info_sql(wp::WireProtocol, stmt_handle::Int32, vars::Vector{UInt8})
    DEBUG_OUTPUT("_op_info_sql")
    pack_uint32(wp, op_info_sql)
    pack_uint32(wp, stmt_handle)
    pack_uint32(wp, 0)
    pack_bytes(wp, vars)
    pack_uint32(wp, BUFFER_LEN)
    send_packets(wp)
end

function _op_execute(wp::WireProtocol, stmt_handle::Int32, trans_handle::Int32, params::Vector{Any})
    DEBUG_OUTPUT("_op_execute")
    pack_uint32(wp, op_execute)
    pack_uint32(wp, stmt_handle)
    pack_uint32(wp, trans_handle)

    if length(params) == 0
        pack_uint32(wp, 0)  # pack_bytes(wp, [])
        pack_uint32(wp, 0)
        pack_uint32(wp, 0)
    else
        blr, values = params_to_blr(wp, trans_handle, params, wp.protocol_version)
        pack_bytes(wp, blr)
        pack_uint32(wp, 0)
        pack_uint32(wp, 1)
        append_bytes(values)
    end
    send_packets(wp)
end

function _op_execute2(wp::WireProtocol, stmt_handle::Int32, trans_handle::Int32, params::Vector{Any}, output_blr::Vector{UInt8})
    DEBUG_OUTPUT("_op_execute2")
    pack_uint32(wp, op_execute2)
    pack_uint32(wp, stmt_handle)
    pack_uint32(wp, trans_handle)

    if length(params) == 0
        pack_uint32(wp, 0)  # pack_bytes(wp, [])
        pack_uint32(wp, 0)
        pack_uint32(wp, 0)
    else
        blr, values = params_to_blr(wp, trans_handle, params, wp.protocol_version)
        pack_bytes(wp, blr)
        pack_uint32(wp, 0)
        pack_uint32(wp, 1)
        append_bytes(values)
    end

    pack_bytes(wp, output_blr)
    pack_uint32(wp, 0)
    send_packets(wp)
end

function _op_exec_immediate(wp::WireProtocol, trans_handle::Int32, query::String)
    DEBUG_OUTPUT("_op_exec_immediate")
    pack_uint32(wp, op_exec_immediate)
    pack_uint32(wp, trans_handle)
    pack_uint32(wp, wp.db_handle)
    pack_uint32(wp, 3)      # dialect = 3
    pack_string(wp, query)
    pack_uint32(wp, 0)      # pack_bytes(wp, [])
    pack_uint32(wp, BUFFER_LEN)
    send_packets(wp)
end

function _op_fetch(wp::WireProtocol, stmt_handle::Int32, blr::Vector{UInt8})
    DEBUG_OUTPUT("_op_fetch")
    pack_uint32(wp, op_fetch)
    pack_uint32(wp, stmt_handle)
    pack_bytes(wp, blr)
    pack_uint32(wp, 0)
    pack_uint32(wp, 400)
    send_packets(wp)
end

function _op_fetch_response(wp::WireProtocol, stmt_handle::Int32, xsqlda::Vector{XSQLVAR})::Tuple{Vector{Vector{Any}}, Bool}
    DEBUG_OUTPUT("_op_fetch_response")
    op_code = bytes_to_bint32(recv_packets(wp, 4))
    while op_code == op_dummy
        op_code = bytes_to_bint32(recv_packets(wp, 4))
    end
    while op_code == op_response && wp.lazy_response_count > 0
        wp.lazy_response_count -= 1
        op_code = bytes_to_bint32(recv_packets(wp, 4))
    end

    if op_code != op_fetch_response
        if op_code == op_response
            parse_op_response(wp)
        end
        throw(DomainError("op_fetch_resonse:op_code=$(op_code)"))
    end

    status = bytes_to_bint32(recv_packets(wp, 4))
    count = bytes_to_bint32(recv_packets(wp, 4))
    rows::Vector{Vector{Any}} = []

    while count > 0
        n = div(length(xsqlda), 8)
        if length(xsqlda) % 8 != 0
            n += 1
        end
        null_indicator::BigInt = 0
        for b in reverse(recv_packets_alignment(wp, n))
            null_indicator <<= 8
            null_indicator += b
        end
        r = Vector{Any}(missing, length(xsqlda))
        for i in 1:length(xsqlda)
            x = xsqlda[i]
            if (null_indicator & (1 << (i-1))) == 0 # not null
                ln = io_length(x)
                if ln < 0
                    ln = bytes_to_bint32(recv_packets(wp, 4))
                end
                raw_value = recv_packets_alignment(wp, ln)
                r[i] = value(x, raw_value)
            end
        end
        rows = vcat(rows, [r])
        op_code = bytes_to_bint32(recv_packets(wp, 4))
        status = bytes_to_bint32(recv_packets(wp, 4))
        count = bytes_to_bint32(recv_packets(wp, 4))
    end

    rows, status != 100
end

function _op_detatch(wp::WireProtocol)
    DEBUG_OUTPUT("_op_detatch")
    pack_uint32(wp, op_detatch)
    pack_uint32(wp, wp.db_handle)
    send_packets(wp)
end

function _op_open_blob(wp::WireProtocol, blob_id::Vector{UInt8}, trans_handle::Int32)
    DEBUG_OUTPUT("_op_open_blob")
    pack_uint32(wp, op_open_blob)
    pack_uint32(wp, trans_handle)
    append_bytes(wp, blob_id)
    send_packets(wp)
end

function _op_create_blob2(wp::WireProtocol, trans_handle::Int32)
    DEBUG_OUTPUT("_op_create_blob2")
    pack_uint32(wp, op_create_blob2)
    pack_uint32(wp, 0)
    pack_uint32(wp, trans_handle)
    pack_uint32(wp, 0)
    pack_uint32(wp, 0)
    send_packets(wp)
end

function _op_get_segment(wp::WireProtocol, blob_handle::Int32)
    DEBUG_OUTPUT("_op_get_segment")
    pack_uint32(wp, op_get_segment)
    pack_uint32(wp, blob_handle)
    pack_uint32(wp, BUFFER_LEN)
    pack_uint32(wp, 0)
    send_packets(wp)
end

function _op_put_segment(wp::WireProtocol, blob_handle::Int32, seg_data::Vector{UInt8})
    DEBUG_OUTPUT("_op_put_segment")
    ln::UInt32 = length(seg_data)

    pack_uint32(wp, op_put_segment)
    pack_uint32(wp, blob_handle)
    pack_uint32(wp, ln)
    pack_uint32(wp, ln)
    append_bytes(seg_data)
    padding = Vector{UInt8}([0, 0, 0])
    append_bytes(padding[1:((4 - ln) & 3)])
    send_packets(wp)
end

function _op_batch_segments(wp::WireProtocol, blob_handle::Int32, seg_data::Vector{UInt8})
    DEBUG_OUTPUT("_op_batch_segment")
    ln = length(sqg_data)
    pack_uint(wp, op_batch_segments)
    pack_uint32(wp, blob_handle)
    pack_uint32(wp, ln+2)
    pack_uint32(wp, ln+2)
    pad_length = ((4-(ln+2)) & 3)
    padding = Vector{UInt8}([0, 0, 0])
    pack_bytes(wp, Vector{UInt8}([UInt8(ln & 255), UInt8(ln >> 8)]))  # little endian int 16
    pack_bytes(wp, seg_data)
    append_bytes(wp, padding[1:((4 - ln) & 3)])
    send_packets(wp)
end

function _op_close_blob(wp::WireProtocol, blob_handle::Int32)
    DEBUG_OUTPUT("_op_close_blob")
    pack_uint32(wp, op_close_blob)
    pack_uint32(wp, blob_handle)
    send_packets(wp)
end

function _op_response(wp::WireProtocol)::Tuple{Int32, Vector{UInt8}, Vector{UInt8}}
    DEBUG_OUTPUT("_op_response")
    op_code = bytes_to_bint32(recv_packets(wp, 4))
    while op_code == op_dummy
        op_code = bytes_to_bint32(recv_packets(wp, 4))
    end
    while op_code == op_response && wp.lazy_response_count > 0
        wp.lazy_response_count -= 1
        parse_op_response(wp)
        op_code = bytes_to_bint32(recv_packets(wp, 4))
    end
    if op_code == op_cont_auth
        throw(DomainError("Unauthorized"))
    elseif op_code != op_response
        throw(DomainError("op_resonse:op_code=$(op_code)"))
    end
    parse_op_response(wp)
end

function _op_sql_response(wp::WireProtocol, xsqlda::XSQLVAR)::Vector{Any}
    DEBUG_OUTPUT("_op_sql_response")
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
    if length(xsqlvar) % 8 != 0
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
                ln = bytes_to_bint32(recv_packets(wp, 4))
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

function params_to_blr(wp::WireProtocol, trans_handle::Int32, params::Vector{Any})::Tuple{Vector{UInt8}, Vector{UInt8}}
    ln = length(params) * 2
    blr_list::Vector{UInt8} = Vector{UInt8}([5, 2, 4, 0, UInt8(ln & 255), UInt8(ln >> 8)])
    values::Vector{UInt8} = []

    # NULL indicator
    null_indicator = 0
    for i in 1:length(params)
        if params[i] == nothing
            null_indicator |= (1 << i)
        end
    end
    n = div(length(params), 8)
    if length(params) % 8 != 0
        n += 1
    end
    if n % 4    # padding
        n += (4 - n) % 4
    end
    for i in 1:n
        append!(values, null_indicator & 255)
        null_indicator >>= 8
    end

    for i in 1:length(params)
        p = if typeof(p) == String
            p = Vector{UInt8}(params[i])
        else
            p = params[i]
        end
        v, blr = if typeof(p) == Vector{UInt8}
            if length(p) < MAX_CHAR_LENGTH
                bytes_to_blr(p)
            else
                create_blob(wp, p, trans_handle), UInt8[9, 0]
            end
        else
            to_blr(p)
        end
        append!(values, v)
        append!(blr_list, blr)
        append!(blr_list, 7)
        append!(blr_list, 0)
    end

    blr_list = vcat(blr_list, Vector{UInt8}([255, 76]))     # [blr_end, blr_eoc]
    blr_list, values
end
