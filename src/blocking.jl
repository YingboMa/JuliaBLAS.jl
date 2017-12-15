import Base: getindex

struct BlockInfo{T}
    mc::LinAlg.BlasInt
    kc::LinAlg.BlasInt
    A::BLASVec{T}
    B::BLASVec{T}
    prefetch::BLASVec{T}
end

function getindex(b::BlockInfo{T}, s::Symbol) where T
    if s == :A
        return b.A
    elseif s == :B
        return b.B
    elseif s == :P
        return b.prefetch
    end
end

deallocate(a::BlockInfo) = deallocate(a.A.ptr)

struct blocking{T}; end

@fastmath function (::Type{blocking{T}})(m::LinAlg.BlasInt, n::LinAlg.BlasInt, k::LinAlg.BlasInt) where T
    P = T<:Complex ? 2 : 1
    SIZE = sizeof(T)
    s = n * P
    l2 = c2 * 3÷5 # half cache
    kc = unsafe_div((l2 - m*main_nr*SIZE), (m*SIZE + main_nr*SIZE))
    mc = m
    minKc = 320 ÷ P
    a = 2 * (main_nr*main_mr*SIZE + main_nr * line) + 512
    if (kc < minKc || kc * (main_mr*SIZE + main_nr*SIZE) + a  > c1)
        kc = (c1 - a) ÷ (main_mr*SIZE + main_nr*SIZE)
        kc = normalize_chunk_size{main_nr}(kc, k)
        df = SIZE*main_nr + SIZE * kc
        mc = unsafe_div((l2 - kc * main_nr * SIZE), df)
        mc = normalize_chunk_size{main_nr}(mc, m)
    else
        kc = normalize_chunk_size{main_mr}(kc, k)
    end
    a_length = kc * mc * SIZE
    b_length = kc * SIZE * n
    mem = allocate(a_length + b_length + prefetchShift)
    A = BLASVec(reinterpret(Ptr{T}, mem), unsafe_div(a_length,SIZE))
    B = BLASVec(reinterpret(Ptr{T}, mem + a_length), unsafe_div(b_length,SIZE))
    prefetch = BLASVec(reinterpret(Ptr{T}, mem + a_length + b_length), unsafe_div(prefetchShift,SIZE))
    return BlockInfo{T}(mc, kc, A, B, prefetch)
end

struct normalize_chunk_size{subChunk}; end

@fastmath function (::Type{normalize_chunk_size{subChunk}})(chunk::LinAlg.BlasInt, length::LinAlg.BlasInt) where subChunk
    if chunk >= length
        return length
    end
    c1, c2 = unsafe_divrem(length, chunk)
    # count = length ÷ chunk + (length % chunk != 0)
    count = c1 + ifelse(c2!=0, 1, 0)
    c1, c2 = unsafe_divrem(length, count)
    # new_ch = length ÷ count + (length % count != 0)
    new_ch = c1 + ifelse(c2!=0, 1, 0)
    r = unsafe_rem(new_ch, subChunk)
    if r != 0
        new_new_ch = new_ch + subChunk - r
        if new_new_ch <= chunk
            return new_new_ch
        end
    end
    return new_ch
end

#unsafe_div(a::Int64,b::Int64) = Base.llvmcall("""%3 = sdiv i64 %0, %1
#                                              ret i64 %3""", Int64, Tuple{Int64, Int64}, a, b)
#unsafe_div(a::Int32,b::Int32) = Base.llvmcall("""%3 = sdiv i32 %0, %1
#                                              ret i32 %3""", Int32, Tuple{Int32, Int32}, a, b)
#unsafe_rem(a::Int64,b::Int64) = Base.llvmcall("""%3 = srem i64 %0, %1
#                                              ret i64 %3""", Int64, Tuple{Int64, Int64}, a, b)
#unsafe_rem(a::Int32,b::Int32) = Base.llvmcall("""%3 = srem i32 %0, %1
#                                              ret i32 %3""", Int32, Tuple{Int32, Int32}, a, b)
#
#unsafe_divrem(a, b) = (unsafe_div(a,b), unsafe_rem(a,b))