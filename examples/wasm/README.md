# metal0 WASM Examples

Compile Python to WebAssembly for browser and Node.js.

## Quick Start

```bash
# Compile to WASM
cd examples/wasm
../../zig-out/bin/metal0 build --target wasm-browser math.py

# Test in Node.js
node node_test.mjs

# Test in browser
python3 -m http.server 8080
# Open http://localhost:8080/browser.html
```

## Files

- `math.py` - Example Python module with math functions
- `browser.html` - Browser test page with Immer-style runtime
- `node_test.mjs` - Node.js test script

## Generated Files

After compilation:
- `math.wasm` - WebAssembly binary (functions exported)
- `math.d.ts` - TypeScript definitions

## Immer-Style Runtime

The runtime is only 773 bytes (minified) and uses a Proxy pattern:

```javascript
const E = new TextEncoder();
let w, m, p, M = 1 << 20;
const g = () => new Uint8Array(m.buffer, p, M);
const x = a => {
    if (typeof a !== 'string') return [typeof a === 'number' ? BigInt(a) : a];
    const b = E.encode(a);
    const u = g();
    u.set(b);
    return [p, b.length];
};

async function load(s) {
    const b = typeof s === 'string' ? await fetch(s).then(r => r.arrayBuffer()) : s;
    w = (await WebAssembly.instantiate(await WebAssembly.compile(b), {})).exports;
    m = w.memory;
    if (w.alloc) { p = w.alloc(M); }
    return new Proxy({}, {
        get: (_, n) => typeof w[n] === 'function' ? (...a) => w[n](...a.flatMap(x)) : w[n]
    });
}

// Usage
const mod = await load('./math.wasm');
mod.add(3, 4);  // Returns 7n (BigInt)
```

## Notes

- Python `int` compiles to `i64`, which maps to JavaScript `BigInt`
- Use `Number(result)` to convert BigInt to regular number if needed
- String arguments are automatically marshalled to WASM memory
