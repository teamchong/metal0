#!/bin/bash
set -e

# Build script for metal0-lanceql native library
# This script builds the Zig native library and copies it to the Python package

cd "$(dirname "$0")/.."
echo "Building native library..."
zig build lib -Doptimize=ReleaseFast

echo "Copying library to Python package..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    cp zig-out/lib/liblanceql.dylib python/metal0/lanceql/
    echo "✓ Copied liblanceql.dylib"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    # Windows
    cp zig-out/lib/lanceql.dll python/metal0/lanceql/
    echo "✓ Copied lanceql.dll"
else
    # Linux
    cp zig-out/lib/liblanceql.so python/metal0/lanceql/
    echo "✓ Copied liblanceql.so"
fi

echo ""
echo "✓ Build complete! Library at python/metal0/lanceql/"
echo ""
echo "To install the package:"
echo "  cd python"
echo "  pip install -e ."
