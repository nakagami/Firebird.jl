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

function dpb_bit_to_int64(dpd::UInt64, mask::UInt64)::UInt64
    (dpd & mask) != 0 ? Int64(1) : Int64(0)
end

function dpd_to_int64(dpd::UInt)::UInt64
    # Convert DPD encodined value to int (0-999)
    # dpd: DPD encoded value. 10bit unsigned int

    b = zeros(UInt64, 10)
    b[9] = dpdBitToInt(dpd, 0x0200)
    b[8] = dpdBitToInt(dpd, 0x0100)
    b[7] = dpdBitToInt(dpd, 0x0080)
    b[6] = dpdBitToInt(dpd, 0x0040)
    b[5] = dpdBitToInt(dpd, 0x0020)
    b[4] = dpdBitToInt(dpd, 0x0010)
    b[3] = dpdBitToInt(dpd, 0x0008)
    b[2] = dpdBitToInt(dpd, 0x0004)
    b[1] = dpdBitToInt(dpd, 0x0002)
    b[0] = dpdBitToInt(dpd, 0x0001)

    b = zeros(UInt64, 3)
    if b[3] == 0
        d[2] = b[9]*4 + b[8]*2 + b[7]
        d[1] = b[6]*4 + b[5]*2 + b[4]
        d[0] = b[2]*4 + b[1]*2 + b[0]
    elseif b[3] == 1 && b[2] == 0 && b[1] == 0
        d[2] = b[9]*4 + b[8]*2 + b[7]
        d[1] = b[6]*4 + b[5]*2 + b[4]
        d[0] = 8 + b[0]
    elseif b[3] == 1 && b[2] == 0 && b[1] == 1
        d[2] = b[9]*4 + b[8]*2 + b[7]
        d[1] = 8 + b[4]
        d[0] = b[6]*4 + b[5]*2 + b[0]
    elseif b[3] == 1 && b[2] == 1 && b[1] == 0
        d[2] = 8 + b[7]
        d[1] = b[6]*4 + b[5]*2 + b[4]
        d[0] = b[9]*4 + b[8]*2 + b[0]
    elseif b[6] == 0 && b[5] == 0 && b[3] == 1 && b[2] == 1 && b[1] == 1
        d[2] = 8 + b[7]
        d[1] = 8 + b[4]
        d[0] = b[9]*4 + b[8]*2 + b[0]
    elseif b[6] == 0 && b[5] == 1 && b[3] == 1 && b[2] == 1 && b[1] == 1
        d[2] = 8 + b[7]
        d[1] = b[9]*4 + b[8]*2 + b[4]
        d[0] = 8 + b[0]
    elseif b[6] == 1 && b[5] == 0 && b[3] == 1 && b[2] == 1 && b[1] == 1
        d[2] = b[9]*4 + b[8]*2 + b[7]
        d[1] = 8 + b[4]
        d[0] = 8 + b[0]
    elseif b[6] == 1 && b[5] == 1 && b[3] == 1 && b[2] == 1 && b[1] == 1
        d[2] = 8 + b[7]
        d[1] = 8 + b[4]
        d[0] = 8 + b[0]
    else
        throw(DomainError(plugin_name, "Invalid DPD encoding"))
    end

    return int64(d[2])*100 + int64(d[1])*10 + int64(d[0])
end
