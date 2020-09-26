using AutoGrad: AutoGrad, @primitive1

using CUDA.CUDNN:
    #cudnnSoftmaxForward,
    cudnnSoftmaxBackward,
    cudnnSoftmaxAlgorithm_t,
        CUDNN_SOFTMAX_FAST,     # 0, /* straightforward implementation */
        CUDNN_SOFTMAX_ACCURATE, # 1, /* subtract max from every point to avoid overflow */
        CUDNN_SOFTMAX_LOG,      # 2
    cudnnSoftmaxMode_t,
        CUDNN_SOFTMAX_MODE_INSTANCE, # 0, /* compute the softmax over all C, H, W for each N */
        CUDNN_SOFTMAX_MODE_CHANNEL,  # 1  /* compute the softmax over all C for each H, W, N */
    handle


function cudnnSoftmaxForward(
    x, y = similar(x);
    algo::cudnnSoftmaxAlgorithm_t = CUDNN_SOFTMAX_FAST,
    mode::cudnnSoftmaxMode_t = CUDNN_SOFTMAX_MODE_INSTANCE,
    alpha::Real = 1,
    xDesc::cudnnTensorDescriptor = TD(x),
    beta::Real = 0,
    yDesc::cudnnTensorDescriptor = xDesc
)
    alpha, beta = scalr(alpha,x), scalr(beta,x)
    _cudnnSoftmaxForward(x; algo, mode, alpha, xDesc, beta, yDesc, y)
end


function _cudnnSoftmaxForward(x; algo, mode, alpha, xDesc, beta, yDesc, y)
    CUDA.CUDNN.cudnnSoftmaxForward(handle(), algo, mode, alpha, xDesc, x, beta, yDesc, y)
    return y
end


@primitive1((_cudnnSoftmaxForward(x; algo, mode, alpha, xDesc, beta, yDesc, y),
             _dy,_y),
            ((x,y,dy,dx) = (value(x),value(_y),value(_dy),similar(x));
             cudnnSoftmaxBackward(handle(), algo, mode, alpha, yDesc, y, yDesc, dy, beta, xDesc, dx);
             dx))