#!/bin/bash
# Installation script for pointnet2_ops with automatic CUDA environment setup
# This handles the CUDA compilation environment variables automatically

set -e  # Exit on any error

echo "🔧 Setting up CUDA environment variables for pointnet2_ops compilation..."

# Set CUDA compilation environment variables
export CC=/usr/bin/g++
export CXX=/usr/bin/g++
export CUDAHOSTCXX=/usr/bin/g++
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-7.5;8.0;8.6;9.0;10.0;12.0}"

echo "✅ CUDA environment configured"
echo "📦 Installing pointnet2_ops..."

# Navigate to pointnet2_ops directory and install
cd pointnet2_ops && uv pip install --no-build-isolation .

echo "🎉 pointnet2_ops installation completed successfully!"
