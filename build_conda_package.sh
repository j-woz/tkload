#!/bin/bash

set -e

echo "=== Building tkload Conda Package ==="
echo ""

# Check if conda-build is installed
if ! conda list | grep -q "^conda-build"; then
    echo "Installing conda-build..."
    conda install -y conda-build
fi

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build the package
echo "Building package..."
conda build conda-recipe/

echo ""
echo "=== Build Complete ==="
echo ""
echo "To upload to Anaconda Cloud:"
echo "  1. Install anaconda-client if not already installed:"
echo "     conda install -y anaconda-client"
echo ""
echo "  2. Log in to your Anaconda account:"
echo "     anaconda login"
echo ""
echo "  3. Find the built package (check conda build output above for path)"
echo "     and upload it:"
echo "     anaconda upload /path/to/tkload-1.0.0-0.tar.bz2"
echo ""
echo "  Or upload all packages from your local conda-bld directory:"
echo "     anaconda upload ~/anaconda3/conda-bld/noarch/tkload-*.tar.bz2"
