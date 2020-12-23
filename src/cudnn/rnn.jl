import CUDA.CUDNN: cudnnRNNForwardAD
import AutoGrad: forw
using AutoGrad: AutoGrad, @primitive1, value, forwargs, recording, Result, @zerograd
using CUDA.CUDNN: 
    cudnnRNNBackwardWeights_v8,
    cudnnRNNBackwardData_v8,
    cudnnRNNTempSpaceSizes,
    cudnnTempSpace,
    CUDNN_FWD_MODE_TRAINING,
    CUDNN_WGRAD_MODE_ADD,
    CUDNN_FWD_MODE_INFERENCE,
    CUDNN_FWD_MODE_TRAINING,
    handle


# Define gradients for the AD method

@primitive1((cudnnRNNForwardAD(w, x, hx, cx; rnnDesc, fwdMode, devSeqLengths, xDesc, yDesc, y, hDesc, hy, cDesc, cy, workspace, reserveSpace, dw, dx, dhx, dcx, dready), dout, out),
            (dready[] || cudnnRNNBackward(dout, out, w, x, hx, cx; rnnDesc, fwdMode, devSeqLengths, xDesc, yDesc, y, hDesc, hy, cDesc, cy, workspace, reserveSpace, dw, dx, dhx, dcx, dready); dw[]),
            (dready[] || cudnnRNNBackward(dout, out, w, x, hx, cx; rnnDesc, fwdMode, devSeqLengths, xDesc, yDesc, y, hDesc, hy, cDesc, cy, workspace, reserveSpace, dw, dx, dhx, dcx, dready); dx[]),
            (dready[] || cudnnRNNBackward(dout, out, w, x, hx, cx; rnnDesc, fwdMode, devSeqLengths, xDesc, yDesc, y, hDesc, hy, cDesc, cy, workspace, reserveSpace, dw, dx, dhx, dcx, dready); dhx[]),
            (dready[] || cudnnRNNBackward(dout, out, w, x, hx, cx; rnnDesc, fwdMode, devSeqLengths, xDesc, yDesc, y, hDesc, hy, cDesc, cy, workspace, reserveSpace, dw, dx, dhx, dcx, dready); dcx[]))


function cudnnRNNBackward(dout, out, w, x, hx, cx; rnnDesc, fwdMode, devSeqLengths, xDesc, yDesc, y, hDesc, hy, cDesc, cy, workspace, reserveSpace, dw, dx, dhx, dcx, dready)
    # Make sure backward gets called only once
    dready[] && return
    dready[] = true
    # Read all relevant inputs
    (_y,_hy,_cy) = value.(out)
    (dy,dhy,dcy) = value.(dout)
    (w,x,hx,cx) = value.((w,x,hx,cx))
    # Allocate gradient buffers if necessary
    if dw[] === nothing; dw[] = similar(w); end; @assert issimilar(w, dw[])
    if dx[] === nothing; dx[] = similar(x); end; @assert issimilar(x, dx[])
    if hx !== nothing && dhx[] === nothing; dhx[] = similar(hx); end; @assert issimilar(hx, dhx[])
    if cx !== nothing && dcx[] === nothing; dcx[] = similar(cx); end; @assert issimilar(cx, dcx[])
    # Currently, the cudnnRNNBackwardWeights_v8() function supports the CUDNN_WGRAD_MODE_ADD mode only so the dweightSpace buffer should be zeroed by the user before invoking the routine for the first time. 
    addGrad = CUDNN_WGRAD_MODE_ADD 
    dw[] .= 0
    # The cudnnRNNBackwardData_v8() function must be called after cudnnRNNForward().
    # The cudnnRNNBackwardWeights_v8() function should be invoked after cudnnRNNBackwardData().
    cudnnRNNBackwardData_v8(handle(), rnnDesc, devSeqLengths, yDesc, _y, dy, xDesc, dx[], hDesc, something(hx, CU_NULL), something(dhy, CU_NULL), something(dhx[], CU_NULL), cDesc, something(cx, CU_NULL), something(dcy, CU_NULL), something(dcx[], CU_NULL), sizeof(w), w, sizeof(workspace), something(workspace, CU_NULL), sizeof(reserveSpace), something(reserveSpace, CU_NULL))
    cudnnRNNBackwardWeights_v8(handle(), rnnDesc, addGrad, devSeqLengths, xDesc, x, hDesc, something(hx, CU_NULL), yDesc, _y, sizeof(w), dw[], sizeof(workspace), something(workspace, CU_NULL), sizeof(reserveSpace), something(reserveSpace, CU_NULL))
end


# cudnnRNNForwardWithDefaults does not have access to AutoGrad state so may not set fwdMode correctly
# When one of the inputs to cudnnRNNForwardAD (w, x, hx, cx) is a Value, AutoGrad.forw is called
# If we are computing gradients we need to fix the setup:
# - Set fwdMode to TRAINING
# - Check if workspace and reserveSpace needs to be resized for TRAINING
# - Alloc gradient buffers if not allocated (this is done in backward)

function forw(f::typeof(cudnnRNNForwardAD), w, x, hx, cx; rnnDesc, fwdMode, devSeqLengths, xDesc, yDesc, y, hDesc, hy, cDesc, cy, workspace, reserveSpace, dw, dx, dhx, dcx, dready)
    args = (w, x, hx, cx)
    (f, nobcast, novalue) = forwargs(f, args)
    @assert nobcast === args    # we shouldn't need to handle broadcasting with rnns
    @assert novalue !== args    # there should be some tracked args for forw to be called
    fwdMode = recording() ? CUDNN_FWD_MODE_TRAINING : CUDNN_FWD_MODE_INFERENCE # we could be here during inference because w is a Param
    (workspaceSize, reserveSpaceSize) = cudnnRNNTempSpaceSizes(rnnDesc, fwdMode, xDesc)
    if reserveSpaceSize > 0 && reserveSpace === nothing; reserveSpace = cudnnTempSpace(reserveSpaceSize); end
    @assert sizeof(reserveSpace) >= reserveSpaceSize  "reserveSpace should be at least $reserveSpaceSize bytes"
    # Cannot use @workspace here because it is shared between forw and back calls
    if workspaceSize > 0 && workspace === nothing; workspace = cudnnTempSpace(workspaceSize); end
    @assert sizeof(workspace) >= workspaceSize  "workspace should be at least $workspaceSize bytes"
    v = f(novalue...; rnnDesc, fwdMode, devSeqLengths, xDesc, yDesc, y, hDesc, hy, cDesc, cy, workspace, reserveSpace, dw, dx, dhx, dcx, dready)
    if recording()
        v = Result(v, f, nobcast, (; rnnDesc, fwdMode, devSeqLengths, xDesc, yDesc, y, hDesc, hy, cDesc, cy, workspace, reserveSpace, dw, dx, dhx, dcx, dready))
    end
    return v
end

#import Base: sizeof
#@zerograd sizeof(x) # TODO: move this to AutoGrad
