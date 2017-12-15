using SIMD

@generated function _ker(::Type{Val{MV}}, ::Type{Val{N}}, len, A::Ptr{T}, B::Ptr{T}, C::Ptr{T}) where {MV,N,T}
    # AVX256
    VL = (256÷8)÷sizeof(T)
    VT = Vec{VL, T}
    M = MV÷VL
    ex = Expr(:block)
    # initialize Mi... which will be later stored in the C matrix
    for i in 0:M*N-1
        push!( ex.args, :($(Symbol(:M, i)) = zero($VT)) )
    end

    # main loop
    push!( ex.args, Expr(:for, :(i = 1:len), Expr(:block)) )
    mainloop = ex.args[end].args[2].args
    push!( mainloop, :(prefetch_r( Val{$(sizeof(VT)*M)}, Val{1}, Val{8}, Val{prefetchshift}, Ptr{Void}(A), 0 )) )
    # load Ai...
    for i in 0:M-1
        push!( mainloop, :($(Symbol(:A, i)) = vload($VT, A+$(i*sizeof(VT)))) )
    end

    for u in 0:(N÷2+N%2-1)
        um = 2u:(2u+2>N ? 2u : 2u+1)
        for n in um
            push!( mainloop, :($(Symbol(:B, n)) = $VT(unsafe_load(B, $n*len + 1))) )
        end
        for n in um
            for m in 0:M-1
                push!( mainloop, :($(Symbol(:M, m + n*M)) = muladd($(Symbol(:A, m)), $(Symbol(:B, n)), $(Symbol(:M, m + n*M)))) )
            end
        end
    end
    push!(mainloop, :(A += $(sizeof(VT)*M)), :(B += $(sizeof(T))))

    # store Mi... into C
    for i in 0:M*N-1
        push!( ex.args, :(vstore($(Symbol(:M, i)), C + $(sizeof(VT) * i))) )
    end
    ex
end
