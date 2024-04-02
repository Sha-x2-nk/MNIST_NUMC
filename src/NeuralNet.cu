#include <layers/affineLayer.cuh>
#include <layers/reluLayer.cuh>
#include <layers/dropoutLayer.cuh>

#include <lossFunctions/softmax.cuh>

#include <optimisers/adam.cuh>

#include <neuralNet.cuh>

#include <numC/npGPUArray.cuh>

#include <cuda_runtime.h>

#include <iostream>
#include <string>
#include <vector>

NeuralNet::NeuralNet(float reg, float p_keep)
{
    this->reg = 0.0;
    this->relu_layers.push_back(ReLULayer());
    this->dropout_layers.push_back(DropoutLayer(p_keep));

    this->affine_layers.push_back(AffineLayer(784, 2048));
    this->affine_layers.push_back(AffineLayer(2048, 10));

    this->adam_configs.push_back(AdamOptimiser(0.001f, 0.9f, 0.999f, 1e-6f));
    this->adam_configs.push_back(AdamOptimiser(0.001f, 0.9f, 0.999f, 1e-6f));

    this->adam_configs.push_back(AdamOptimiser(0.001f, 0.9f, 0.999f, 1e-6f));
    this->adam_configs.push_back(AdamOptimiser(0.001f, 0.9f, 0.999f, 1e-6f));

    this->mode = std::string("test");
}

NeuralNet::NeuralNet(const NeuralNet &N)
{
    this->affine_layers = N.affine_layers;
    this->reg = N.reg;
    this->relu_layers = N.relu_layers;
    this->dropout_layers = N.dropout_layers;
    this->affine_layers = N.affine_layers;
    this->mode = N.mode;
}

NeuralNet NeuralNet::operator=(const NeuralNet &N)
{
    NeuralNet N_new;
    N_new.affine_layers = N.affine_layers;
    N_new.reg = N.reg;
    N_new.relu_layers = N.relu_layers;
    N_new.dropout_layers = N.dropout_layers;
    N_new.affine_layers = N.affine_layers;
    N_new.mode = N.mode;

    return N_new;
}

void NeuralNet::train()
{
    this->mode = std::string("train");
}
void NeuralNet::test()
{
    this->mode = std::string("eval");
}

np::ArrayGPU<float> NeuralNet::forward(const np::ArrayGPU<float> &X)
{
    if (this->mode == "train")
    {
        std::cerr << "\nMode train but y not given";
        exit(1);
    }
    auto out = X;

    // except last_layer, all layers have activation functions and dropout
    for (int i = 0; i < this->affine_layers.size() - 1; ++i)
    {
        out = this->affine_layers[i](out, this->mode);
        out = dropout_layers[i](out);
        out = relu_layers[i](out);
    }

    // last layer no activations or dropouts
    out = affine_layers.back()(out);

    return out;
}
std::vector<np::ArrayGPU<float>> NeuralNet::forward(const np::ArrayGPU<float> &X, const np::ArrayGPU<int> &y)
{
    if (this->mode == "eval")
    {
        std::cerr << "\nMode eval but y given";
        exit(1);
    }

    auto out = X;

    // except last_layer, all layers have activation functions and dropout
    for (int i = 0; i < this->affine_layers.size() - 1; ++i)
    {
        out = this->affine_layers[i](out, this->mode);

        out = dropout_layers[i](out);

        out = relu_layers[i](out);

    }

    // last layer no activations or dropouts
    out = affine_layers.back()(out);


    // vector of loss, dout
    auto lossNgrad = softmax.computeLossAndGrad(out, y);

    if (this->reg > 0)
        for (auto &al : affine_layers)
            lossNgrad[0] = lossNgrad[0] + (al.W * al.W).sum() * 0.5 * this->reg;

    this->backward(lossNgrad[1]);

    if (this->reg > 0)
        for (auto &al : affine_layers)
            al.dW = al.dW + al.W * this->reg;

    // output vector = out, loss
    return {out, lossNgrad[0]};
}

np::ArrayGPU<float> NeuralNet::operator()(const np::ArrayGPU<float> &X)
{
    return this->forward(X);
}
std::vector<np::ArrayGPU<float>> NeuralNet::operator()(const np::ArrayGPU<float> &X, const np::ArrayGPU<int> &y)
{
    return this->forward(X, y);
}

np::ArrayGPU<float> NeuralNet::backward(np::ArrayGPU<float> &dout)
{
    // last layer backward. no relu or dropouts.
    dout = this->affine_layers.back().backward(dout);

    // relu backward -> dropout backward -> affinelayer backward
    for (int i = this->affine_layers.size() - 2; i >= 0; --i)
    {
        dout = relu_layers[i].backward(dout);
        dout = dropout_layers[i].backward(dout);

        dout = this->affine_layers[i].backward(dout);
    }

    return dout;
}

void NeuralNet::adamStep()
{
    for (int layerIdx = 0; layerIdx < this->affine_layers.size(); ++layerIdx)
    {
        // for every layer, there are 2 adam configs.
        adam_configs[layerIdx*2].step(affine_layers[layerIdx].W, affine_layers[layerIdx].dW);
        adam_configs[layerIdx*2 + 1].step(affine_layers[layerIdx].b, affine_layers[layerIdx].db);
    }
}
