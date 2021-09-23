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
module Firebird
using Dates, TimeZones, DBInterface, Tables, Parsers, DecFP

export DBInterface

include("consts.jl")
include("errmsgs.jl")
include("tz_map.jl")
include("xsqlvar.jl")
include("utils.jl")
include("srp.jl")
include("arc4.jl")
include("decfloat.jl")
include("wireprotocol.jl")
include("transaction.jl")
include("connection.jl")
include("statement.jl")
include("cursor.jl")
include("execute.jl")

Base.close(conn::Connection) = DBInterface.close!(conn)
Base.isopen(conn::Connection) = Firebird.isopen(conn)

end # module
