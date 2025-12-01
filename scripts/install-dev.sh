#!/bin/bash
set -e

# metal0 Development Installation Script

echo "🔧 Setting up metal0 development environment..."

# Check prerequisites
command -v zig >/dev/null 2>&1 || { echo "❌ Error: zig not installed. Install from https://ziglang.org/"; exit 1; }

# Build metal0
echo "⚙️  Building metal0 compiler..."
zig build

# Create virtual environment if needed
if [ ! -d ".venv" ]; then
    echo "📁 Creating virtual environment..."
    python3 -m venv .venv
fi

# Add venv bin to PATH
VENV_BIN="$(pwd)/.venv/bin"
export PATH="$VENV_BIN:$PATH"

# Install development dependencies using metal0
echo "📦 Installing development packages..."
./zig-out/bin/metal0 install pytest flask requests httpx

echo ""
echo "✅ Development environment ready!"
echo ""
echo "To use metal0 command, add to your shell:"
echo ""
echo "  export PATH=\"$(pwd)/zig-out/bin:\$PATH\""
echo ""
echo "Or run directly:"
echo "  ./zig-out/bin/metal0 examples/fibonacci.py --run"
echo ""
