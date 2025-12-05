// metal0 WASM Runtime - Generic Immer-style loader with dynamic imports
// Works with ANY metal0-compiled WASM module
// Supports @wasm_import declarations via user-provided handlers

const E = new TextEncoder();
const D = new TextDecoder();
let w, m, p, M = 1 << 20;

const g = () => new Uint8Array(m.buffer, p, M);

// Marshal JS value to WASM args
const x = a => {
  if (typeof a !== 'string') return [a];
  const b = E.encode(a);
  if (b.length > M) { M = b.length + 1024; p = w.alloc(M) }
  g().set(b);
  return [p, b.length];
};

// Read string from WASM memory
const readStr = (ptr, len) => D.decode(new Uint8Array(m.buffer, ptr, len));

// Write string to WASM memory, return {ptr, len}
const writeStr = s => {
  const b = E.encode(s);
  const ptr = w.alloc(b.length);
  new Uint8Array(m.buffer, ptr, b.length).set(b);
  return { ptr, len: b.length };
};

// Default handlers registry - user can add custom handlers
const handlers = {
  js: {
    // Console
    consoleLog: (ptr, len) => console.log(readStr(ptr, len)),
    consoleError: (ptr, len) => console.error(readStr(ptr, len)),

    // Timing
    now: () => Date.now(),
    setTimeout: (cbId, ms) => setTimeout(() => w._callback(cbId), ms),

    // Fetch (async - requires Promise handling)
    fetch: async (urlPtr, urlLen) => {
      const url = readStr(urlPtr, urlLen);
      const res = await fetch(url);
      const text = await res.text();
      return writeStr(text);
    },
  },

  env: {
    // Memory (fallback if not exported by WASM)
    memory: null, // Set during load
  }
};

/**
 * Load WASM module with dynamic imports
 * @param {string|ArrayBuffer} source - URL or ArrayBuffer of WASM
 * @param {Object} customHandlers - User-provided handlers for @wasm_import
 * @returns {Promise<Proxy>} Proxy-wrapped module with all exports
 *
 * Usage:
 *   const mod = await load('./my_module.wasm', {
 *     js: {
 *       myCustomFetch: (ptr, len) => { ... }
 *     }
 *   });
 */
export async function load(source, customHandlers = {}) {
  const binary = typeof source === 'string'
    ? await fetch(source).then(r => r.arrayBuffer())
    : source;

  // Merge custom handlers with defaults
  const imports = {};
  for (const ns of Object.keys(handlers)) {
    imports[ns] = { ...handlers[ns] };
  }
  for (const ns of Object.keys(customHandlers)) {
    imports[ns] = { ...imports[ns], ...customHandlers[ns] };
  }

  // Create import proxy for each namespace that handles unknown functions
  const proxyImports = {};
  for (const ns of Object.keys(imports)) {
    proxyImports[ns] = new Proxy(imports[ns], {
      get(target, prop) {
        if (prop in target) return target[prop];
        // Unknown import - return stub that warns
        return (...args) => {
          console.warn(`[metal0] Unimplemented import: ${ns}.${String(prop)}(${args.length} args)`);
          return 0;
        };
      }
    });
  }

  // Add memory to env if needed
  if (!proxyImports.env.memory) {
    proxyImports.env.memory = new WebAssembly.Memory({ initial: 256 });
  }

  // Compile and instantiate
  const compiled = await WebAssembly.compile(binary);
  const instance = await WebAssembly.instantiate(compiled, proxyImports);

  w = instance.exports;
  m = w.memory || proxyImports.env.memory;
  if (w.alloc) { p = w.alloc(M) }

  // Return Proxy that auto-marshals arguments
  return new Proxy({}, {
    get(_, n) {
      if (n === 'batch') return batch;
      if (n === 'memory') return m;
      if (n === '_raw') return w; // Access raw exports
      if (typeof w[n] === 'function') {
        return (...a) => w[n](...a.flatMap(x));
      }
      return w[n];
    }
  });
}

/**
 * Batch process multiple inputs
 * @param {any[]} inputs - Array of inputs
 * @param {string} funcName - Name of function to call
 * @returns {any[]} Array of results
 */
export const batch = (inputs, funcName) => inputs.map(a => w[funcName](...[a].flatMap(x)));

/**
 * Register custom import handlers
 * Call before load() to add handlers for @wasm_import functions
 *
 * @param {string} namespace - Import namespace (e.g., "js", "wasi")
 * @param {Object} funcs - Object of handler functions
 *
 * Usage:
 *   registerHandlers('js', {
 *     fetch: async (urlPtr, urlLen) => { ... },
 *     localStorage_get: (keyPtr, keyLen) => { ... }
 *   });
 */
export function registerHandlers(namespace, funcs) {
  if (!handlers[namespace]) handlers[namespace] = {};
  Object.assign(handlers[namespace], funcs);
}

// Helper exports for custom handlers
export const utils = {
  readStr,
  writeStr,
  encoder: E,
  decoder: D,
  getMemory: () => m,
};

export default { load, batch, registerHandlers, utils };
