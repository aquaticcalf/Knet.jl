using Test, SpecialFunctions
using Knet.Ops20: reluback, sigmback, eluback, seluback, relu, sigm, elu, selu, invx
using Knet.Ops20_gpu: tanhback
using Knet.Ops21: gelu, geluback, tanh_, hardsigmoid, hardswish, swish
using Knet.LibKnet8: unary_ops
using Knet.KnetArrays: KnetArray
using AutoGrad: gradcheck, grad, @gcheck, Param
using CUDA: CUDA, functional

@testset "unary" begin

    function frand(f,t,d...)
        r = rand(t,d...) .* t(0.5) .+ t(0.25)
        if in(f,(acosh,asec))
            return 1 ./ r
        else
            return r
        end
    end

    bcast(f)=(x->broadcast(f,x))

    unary_fns = Any[]
    for f in unary_ops
        if isa(f,Tuple); f=f[2]; end
        if f ∈ ("tanh_","gelu","hardsigmoid","hardswish","swish"); continue; end # these specifically do not support broadcasting
        push!(unary_fns, eval(Meta.parse(f)))
    end

    # Add unary ops with int degree
    push!(unary_fns, (x->besselj.(2,x)))
    push!(unary_fns, (x->bessely.(2,x)))

    skip_grads = [trigamma,lgamma]
    for f in unary_fns
        f in skip_grads && continue
        #@show f
        bf = bcast(f)
        for t in (Float32, Float64)
            #@show f,t
            sx = frand(f,t)
            @test isa(f(sx),t)
            @test gradcheck(f, sx)
            for n in (1,(1,1),2,(2,1),(1,2),(2,2))
                f == abs2 || n == (2,2) || continue # not all fns need to be tested with all dims
                #@show f,t,n
                ax = frand(f,t,n)
                @test gradcheck(bf, ax)
                if CUDA.functional()
                    gx = KnetArray(ax)
                    cy = bf(ax)
                    gy = bf(gx)
                    @test isapprox(cy,Array(gy))
                    @test gradcheck(bf, gx)
                end
            end
        end
    end

    # Issue #456: 2nd derivative for MLP
    for trygpu in (false, true)
        trygpu && !CUDA.functional() && continue
        (x,y,dy) = randn.((10,10,10))
        if trygpu; (x,y,dy) = KnetArray.((x,y,dy)); end
        (x,y,dy) = Param.((x,y,dy))
        for f in (relu,sigm,tanh,selu,elu)
            f1(x) = f.(x); @test @gcheck f1(x)
            f1i(x,i) = f1(x)[i]; @test @gcheck f1i(x,1)
            g1i(x,i) = grad(f1i)(x,i); @test @gcheck g1i(x,1)
            g1ij(x,i,j) = g1i(x,i)[j]; @test @gcheck g1ij(x,1,1)
            h1ij(x,i,j) = grad(g1ij)(x,i,j); if h1ij(x,1,1) != nothing; @test @gcheck h1ij(x,1,1); end
        end
        @test @gcheck reluback.(dy,y)
        @test @gcheck sigmback.(dy,y)
        @test @gcheck tanhback.(dy,y)
        @test @gcheck seluback.(dy,y)
        @test @gcheck  eluback.(dy,y)
        #@test @gcheck geluback.(dy,y)
    end
end

nothing
