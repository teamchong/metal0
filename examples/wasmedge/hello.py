# Example Python module for WasmEdge (WASI)
# Compile with: metal0 build --target wasm-edge hello.py

def main():
    """Main entry point - runs on _start."""
    print("Hello from metal0 + WasmEdge!")
    print("This is Python compiled to WASM.")

    # Show some computation
    result = 2 + 2
    print(f"2 + 2 = {result}")

if __name__ == "__main__":
    main()
