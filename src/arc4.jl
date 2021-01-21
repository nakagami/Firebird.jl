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

mutable struct Arc4
    state::Vector{UInt8}
    x::UInt64
    y::UInt64

    function Arc4(key::Vector{UInt8})
        state::Vector{UInt8} = []
        for i in 0:255
            push!(state, i)
        end
        @assert length(state) == 256

        index1::UInt64 = 0
        index2::UInt64 = 0

        for i in 0:255
            index2 = (key[index1+1] + state[i+1] + index2) % 256
            (state[i+1], state[index2+1]) = (state[index2+1], state[i+1])
            indx1 = (index1 + 1) % length(key)
        end

        new(state, 0, 0)
    end
end

