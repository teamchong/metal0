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

// Eval worker state for bytecode execution
const workers = new Map();
let nextWorkerId = 0;
let wasmModule = null; // Cached compiled module for viral spawning

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

    // Eval worker functions (for bytecode VM in browser)
    spawnEvalWorker: (bytecodePtr, bytecodeLen, constantsPtr, constantsLen) => {
      const id = nextWorkerId++;
      const bytecode = new Uint8Array(m.buffer, bytecodePtr, bytecodeLen).slice();

      // Create worker with same WASM module (viral spawning)
      const workerCode = `
        let wasmInstance;
        self.onmessage = async (e) => {
          const { module, bytecode } = e.data;
          wasmInstance = await WebAssembly.instantiate(module, {
            env: { memory: new WebAssembly.Memory({ initial: 256 }) }
          });
          const result = wasmInstance.exports.worker_execute_bytecode(
            bytecode.byteOffset, bytecode.length
          );
          self.postMessage({ id: ${id}, result });
        };
      `;
      const blob = new Blob([workerCode], { type: 'application/javascript' });
      const worker = new Worker(URL.createObjectURL(blob));

      workers.set(id, { worker, done: false, result: null });

      worker.onmessage = (e) => {
        const state = workers.get(e.data.id);
        if (state) {
          state.done = true;
          state.result = e.data.result;
        }
      };

      worker.postMessage({ module: wasmModule, bytecode });
      return id;
    },

    isWorkerDone: (id) => {
      const state = workers.get(id);
      return state ? state.done : true;
    },

    getWorkerResult: (id) => {
      const state = workers.get(id);
      if (state && state.done) {
        workers.delete(id);
        return state.result;
      }
      return 0;
    },

    waitWorkerResult: (id) => {
      // Note: True blocking not possible in browser JS
      // This busy-waits which is not ideal but matches the sync API
      const state = workers.get(id);
      if (!state) return 0;
      // For proper async, use isWorkerDone + getWorkerResult in a loop
      while (!state.done) { /* spin */ }
      const result = state.result;
      workers.delete(id);
      return result;
    },

    cancelWorker: (id) => {
      const state = workers.get(id);
      if (state) {
        state.worker.terminate();
        workers.delete(id);
      }
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
  wasmModule = compiled; // Cache for viral spawning in Web Workers
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
