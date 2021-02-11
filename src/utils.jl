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


function xdr_bytes(bs::Vector{UInt8})::Vector{UInt8}
    # XDR encoding bytes
    n = length(bs)
    padding = 0
    if n % 4 != 0
        padding = 4 - n % 4
    end
    buf = zeros(UInt8, 4 + n + padding)
    buf[0] = UInt8(n >> 24 & 0xFF)
    buf[1] = UInt8(n >> 16 & 0xFF)
    buf[2] = UInt8(n >> 8 & 0xFF)
    buf[3] = UInt8(n & 0xFF)
    for i in 1:length(bs)
        buf[4 + i] = bs[i]
    end
    buf
end

function bytes_to_bint32(b::Vector{UInt8})::UInt32
    reinterpret(UInt32, reverse(b))
end

