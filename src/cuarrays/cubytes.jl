export cuarrays, cubytes
using CUDA: CuArray

# Recursively search for CuArrays based on deepcopy_internal

cuarrays(x, c=CuArray[], d=IdDict{Any,Bool}()) = (_cuarrays(x,c,d); c)

_cuarrays(x::CuArray, c::Vector{CuArray}, d::IdDict{Any,Bool}) =
    if !haskey(d,x); d[x] = true; push!(c,x); if hasfield(typeof(x),:parent) && x.parent !== nothing; _cuarrays(x.parent,c,d); end; end

_cuarrays(x::Union{Module,String,Symbol,Core.MethodInstance,Method,GlobalRef,DataType,Union,UnionAll,Task,Regex},
          c::Vector{CuArray}, d::IdDict{Any,Bool}) = return

_cuarrays(x::Tuple, c::Vector{CuArray}, d::IdDict{Any,Bool}) =
    for xi in x; _cuarrays(xi, c, d); end

_cuarrays(x::Core.SimpleVector, c::Vector{CuArray}, d::IdDict{Any,Bool}) =
    if !haskey(d,x); d[x] = true; for xi in x; _cuarrays(xi, c, d); end; end

_cuarrays(x::Union{Dict,IdDict}, c::Vector{CuArray}, d::IdDict{Any,Bool}) =
    if !haskey(d,x); d[x] = true; for (k,v) in x; _cuarrays(k, c, d); _cuarrays(v, c, d); end; end

function _cuarrays(x::Array{T}, c::Vector{CuArray}, d::IdDict{Any,Bool}) where T
    if !isbitstype(T) && !haskey(d,x)
        d[x] = true
        for i = 1:(length(x)::Int)
            if ccall(:jl_array_isassigned, Cint, (Any, Csize_t), x, i-1) != 0
                xi = ccall(:jl_arrayref, Any, (Any, Csize_t), x, i-1)
                if !isbits(xi)
                    _cuarrays(xi, c, d)
                end
            end
        end
    end
end

function _cuarrays(@nospecialize(x), c::Vector{CuArray}, d::IdDict{Any,Bool})
    T = typeof(x)::DataType
    nf = nfields(x)
    (isbitstype(T) || nf == 0) && return
    if haskey(d, x)
        return
    end
    if ismutable(x)
        d[x] = true
    end
    for i in 1:nf
        if isdefined(x,i)
            _cuarrays(getfield(x,i), c, d)
        end
    end
end

cubytes(x)=sum(sizeof(a) for a in cuarrays(x))
