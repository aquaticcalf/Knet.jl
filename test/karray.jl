using Test, Random
using CUDA: CUDA, functional
using AutoGrad: gradcheck
using Knet.KnetArrays: KnetArray

# http://docs.julialang.org/en/latest/manual/arrays.html#man-supported-index-types-1

# Test KnetArray operations: cat, convert, copy, display, eachindex,
# eltype, endof, fill!, first, getindex, hcat, isempty, length,
# linearindexing, ndims, ones, pointer, rand!, reshape, setindex!,
# similar, size, stride, strides, summary, vcat, vec, zeros

if CUDA.functional()
    @testset "karray" begin
        a = rand(3,4)
        k = KnetArray(a)

        # getindex, setindex!
        # Index types: Integer, CartesianIndex, Vector{Int}, Array{Int}, EmptyArray, a:c, a:b:c, Colon, Bool
        # See http://docs.julialang.org/en/latest/manual/arrays.html#man-supported-index-types-1
        # check out http://docs.julialang.org/en/latest/manual/arrays.html#Cartesian-indices-1
        @testset "indexing" begin
            @test a == k                     		# Supported index types:
            for i in ((:,), (:,:),                      # Colon, Tuple{Colon}
                      (3,), (2,3),              	# Int, Tuple{Int}
                      (3:5,), (1:2,3:4),                # UnitRange, Tuple{UnitRange}
                      (2,:), (:,2),                     # Int, Colon
                      (1:2,:), (:,1:2),                 # UnitRange,Colon
                      (1:2,2), (2,1:2),                 # Int, UnitRange
                      (1:2:3,),                         # StepRange
                      (1:2:3,:), (:,1:2:3),             # StepRange,Colon
                      ([1,3],), ([2,2],),               # Vector{Int}
                      ([1,3],:), (:,[1,3]),             # Vector{Int},Colon
                      ([2,2],:), (:,[2,2]),             # Repeated index
                      # ([],),                          # Empty Array: fails with CuArray
                      (trues(size(a)),),                # BitArray: may fail when using (a.>0.5) as index if all false.
                      ([1 3; 2 4],),                    # Array{Int}
                      (CartesianIndex(3,),), (CartesianIndex(2,3),), # CartesianIndex
                      (:,trues(size(a[1,:]))),(trues(size(a[:,1])),:),  # BitArray2 # FAIL for julia4
                      ([CartesianIndex(2,2), CartesianIndex(2,1)],), # Array{CartesianIndex} # FAIL for julia4
                      )
                #@show i
                k = KnetArray(a)
                @test a[i...] == k[i...]
                ai = a[i...]
                if isa(ai, Number)
                    a[i...] = 0
                    k[i...] = 0
                    @test a == k
                    a[i...] = ai
                    k[i...] = ai
                else
                    a[i...] .= 0
                    k[i...] .= 0
                    @test a == k
                    a[i...] .= ai
                    k[i...] .= KnetArray(ai)
                end
                @test a == k
                @test gradcheck(getindex, a, i...; args=1)
                @test gradcheck(getindex, k, i...; args=1)
            end
            # make sure end works
            @test a[2:end] == k[2:end]
            @test a[2:end,2:end] == k[2:end,2:end]
            # k.>0.5 returns KnetArray{T}, no Knet BitArrays yet
            #TODO: @test a[a.>0.5] == k[k.>0.5]
        end

        # Unsupported indexing etc.:
        # @test_broken a[1:2:3,1:3:4] == Array(k[1:2:3,1:3:4]) # MethodError: no method matching getindex(::Knet.KnetArray{Float64,2}, ::StepRange{Int64,Int64}, ::StepRange{Int64,Int64})
        # @test_broken a[[3,1],[4,2]] == Array(k[[3,1],[4,2]]) # MethodError: no method matching getindex(::Knet.KnetArray{Float64,2}, ::Array{Int64,1}, ::Array{Int64,1})
        # @test_broken cat((1,2),a,a) == Array(cat((1,2),k,k)) # cat only impl for i=1,2

        a = rand(3,4)
        k = KnetArray(a)

        # AbstractArray interface
        @testset "abstractarray" begin

            for f in (copy, lastindex, first, isempty, length, ndims, vec, zero, 
                      a->(eachindex(a);0), a->(eltype(a);0), # a->(Base.linearindexing(a);0),
                      a->collect(Float64,size(a)), a->collect(Float64,strides(a)), 
                      a->cat(a,a;dims=1), a->cat(a,a;dims=2), a->hcat(a,a), a->vcat(a,a), 
                      a->reshape(a,2,6), a->reshape(a,(2,6)), 
                      a->size(a,1), a->size(a,2),
                      a->stride(a,1), a->stride(a,2), )

                #@show f
                @test f(a) == f(k)
                @test gradcheck(f, a)
                @test gradcheck(f, k)
            end

            @test convert(Array{Float32},a) == convert(KnetArray{Float32},k)
            @test fill!(similar(a),pi) == fill!(similar(k),pi)
            @test fill!(similar(a,(2,6)),pi) == fill!(similar(k,(2,6)),pi)
            @test fill!(similar(a,2,6),pi) == fill!(similar(k,2,6),pi)
            @test isa(pointer(k), Ptr{Float64})
            @test isa(pointer(k,3), Ptr{Float64})
            @test isempty(KnetArray{Float32}(undef,0))
            @test rand!(copy(a)) != rand!(copy(k))
            @test k == k
            @test a == k
            @test k == a
            @test isapprox(k,k)
            @test isapprox(a,k)
            @test isapprox(k,a)
            @test a == copyto!(similar(a),k)
            @test k == copyto!(similar(k),a)
            @test k == copyto!(similar(k),k)
            @test k == copy(k)
            @test pointer(k) != pointer(copy(k))
            @test k == deepcopy(k)
            @test pointer(k) != pointer(deepcopy(k))
        end

        a = rand(3,4)
        k = KnetArray(a)

        @testset "cpu2gpu" begin
            # cpu/gpu xfer with grad support
            @test gradcheck(x->Array(sin.(KnetArray(x))),a)
            @test gradcheck(x->KnetArray(sin.(Array(x))),k)
        end

        a = rand(3,4)
        k = KnetArray(a)

        @testset "reshape" begin
            a = KnetArray{Float32}(undef, 2, 2, 2)
            
            @test size(reshape(a, 4, :)) == size(reshape(a, (4, :))) == (4, 2)
            @test size(reshape(a, :, 4)) == size(reshape(a, (:, 4))) == (2, 4)
            @test size(reshape(a, :, 1, 4)) == (2, 1,  4)
        end

        a = rand(3,4,5)
        k = KnetArray(a)
        @testset "3D" begin
            for i in ((:,), (:,:,:),                    # Colon
                      (3,), (2,3,4),              	# Int, Tuple{Int}
                      (3:5,),                           # UnitRange
                      (:,:,2),                          # Colon, Colon, Int
                      (:,:,1:2),                        # Colon, Colon, UnitRange
                      # ([],),                          # Empty Array fails with CuArray
                      (trues(size(a)),),                # BitArray
                      )
                #@show i
                k = KnetArray(a)
                @test a[i...] == k[i...]
                ai = a[i...]
                if isa(ai, Number)
                    a[i...] = 0
                    k[i...] = 0
                    @test a == k
                    a[i...] = ai
                    k[i...] = ai
                else
                    a[i...] .= 0
                    k[i...] .= 0
                    @test a == k
                    a[i...] .= ai
                    k[i...] .= KnetArray(ai)
                end
                @test a == k
                @test gradcheck(getindex, a, i...; args=1)
                @test gradcheck(getindex, k, i...; args=1)
            end
            # make sure end works
            @test a[2:end] == k[2:end]
            @test a[:,:,2:end] == k[:,:,2:end]
            # k.>0.5 returns KnetArray{T}, no Knet BitArrays yet
            #TODO: @test a[a.>0.5] == k[k.>0.5]

        end # 3D

        @testset "broadcast" begin # Fixing #342
            zelu(x) = tanh(x) + (exp(min(0,x)) - 1)
            @test isa(zelu.(KnetArray(randn(Float32,5,5))), KnetArray)
        end

        @testset "inplace" begin
            a0 = rand();    k0 = a0
            a1 = rand(1);   k1 = KnetArray(a1)
            a2 = rand(2);   k2 = KnetArray(a2)
            a3 = rand(2,2); k3 = KnetArray(a3)
            a4 = rand(2,2); k4 = KnetArray(a4)

            @test (a4 .+= a3) == (k4 .+= k3); @test a4 == k4 # copyto!(::KnetArray{Float64,2}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64},Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,2}}})
            @test (a4 .+= a2) == (k4 .+= k2); @test a4 == k4 # copyto!(::KnetArray{Float64,2}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64},Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,2}}})
            @test (a4 .+= a1) == (k4 .+= k1); @test a4 == k4 # copyto!(::KnetArray{Float64,2}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64},Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,2}}})
            @test (a4 .+= a0) == (k4 .+= k0); @test a4 == k4 # copyto!(::KnetArray{Float64,2}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64},Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,2}}})

            @test (a4 .= a3) == (k4 .= k3); @test a4 == k4   # copyto!(::KnetArray{Float64,2}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64},Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,2}}})
            @test (a4 .= a2) == (k4 .= k2); @test a4 == k4   # copyto!(::KnetArray{Float64,2}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64},Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,1}}})
            @test (a4 .= a1) == (k4 .= k1); @test a4 == k4   # copyto!(::KnetArray{Float64,2}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64},Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,1}}})
            @test (a4 .= a0) == (k4 .= k0); @test a4 == k4   # copyto!(::KnetArray{Float64,2}, ::Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{0},Tuple{Base.OneTo{Int64},Base.OneTo{Int64}},typeof(identity),Tuple{Float64}})

            @test (a4[:] = a3) == (k4[:] = k3); 	@test a4 == k4 # pass: setindex!(k4,k3,:); return k3
            #TODO @test (a4[:] .= a1) == (k4[:] .= k1); 	@test a4 == k4 # copyto!(::SubArray{Float64,1,KnetArray{Float64,1},Tuple{Base.Slice{Base.OneTo{Int64}}},true}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,1}}}) at /home/gridsan/dyuret/.julia/dev/Knet/src/karray.jl:1200
            @test (a4[:] .= a3[:]) == (k4[:] .= k3[:]); @test a4 == k4 # copyto!(::SubArray{Float64,1,KnetArray{Float64,1},Tuple{Base.Slice{Base.OneTo{Int64}}},true}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,1}}}) at /home/gridsan/dyuret/.julia/dev/Knet/src/karray.jl:1200
            @test (a4[:] .= a0) == (k4[:] .= k0); 	@test a4 == k4 # setindex!(k4,k0,:); return k0; fail: [0.428676, 0.428676, 0.428676, 0.428676] == nothing

            @test (a4[:,:] = a3) == (k4[:,:] = k3);   @test a4 == k4 # setindex!(k4,k3,:,:); return k3
            #TODO @test (a4[:,:] .= a2) == (k4[:,:] .= k2); @test a4 == k4 # copyto!(::SubArray{Float64,2,KnetArray{Float64,2},Tuple{Base.Slice{Base.OneTo{Int64}},Base.Slice{Base.OneTo{Int64}}},true}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64},Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,1}}}) at /home/gridsan/dyuret/.julia/dev/Knet/src/karray.jl:1200
            @test (a4[:,:] .= a3) == (k4[:,:] .= k3); @test a4 == k4 # copyto!(::SubArray{Float64,2,KnetArray{Float64,2},Tuple{Base.Slice{Base.OneTo{Int64}},Base.Slice{Base.OneTo{Int64}}},true}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64},Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,2}}}) at /home/gridsan/dyuret/.julia/dev/Knet/src/karray.jl:1200
            #TODO @test (a4[:,:] .= a1) == (k4[:,:] .= k1); @test a4 == k4 # copyto!(::SubArray{Float64,2,KnetArray{Float64,2},Tuple{Base.Slice{Base.OneTo{Int64}},Base.Slice{Base.OneTo{Int64}}},true}, ::Base.Broadcast.Broadcasted{Base.Broadcast.Style{KnetArray},Tuple{Base.OneTo{Int64},Base.OneTo{Int64}},typeof(identity),Tuple{KnetArray{Float64,1}}}) at /home/gridsan/dyuret/.julia/dev/Knet/src/karray.jl:1200
            @test (a4[:,:] .= a0) == (k4[:,:] .= k0); @test a4 == k4 # setindex!(k4,k0,:,:); return k0
        end

        @testset "vcat" begin
            for (a,b) in ((rand(3), rand(4)),
                          (rand(3,2), rand(4,2)),
                          (rand(3,2,2), rand(4,2,2)),
                          (rand(3,2,2,2), rand(4,2,2,2)))
                c, d = KnetArray(a), KnetArray(b)
                @test vcat(a, b) == vcat(c, d)
                @test gradcheck(vcat, a, b)
                @test gradcheck(vcat, c, d)
            end
        end

    end # karray
end # CUDA.functional() >= 0

nothing
