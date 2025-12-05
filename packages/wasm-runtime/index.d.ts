// metal0 WASM Runtime TypeScript Definitions

/**
 * Pointer + length returned from WASM for complex types
 */
export interface PtrLen {
  ptr: number;
  len: number;
}

/**
 * Custom import handlers for @wasm_import declarations
 */
export interface ImportHandlers {
  [namespace: string]: {
    [funcName: string]: (...args: any[]) => any;
  };
}

/**
 * Utility functions for custom handlers
 */
export interface Utils {
  /** Read UTF-8 string from WASM memory */
  readStr(ptr: number, len: number): string;
  /** Write string to WASM memory, returns {ptr, len} */
  writeStr(s: string): PtrLen;
  /** TextEncoder instance */
  encoder: TextEncoder;
  /** TextDecoder instance */
  decoder: TextDecoder;
  /** Get WASM memory */
  getMemory(): WebAssembly.Memory;
}

/**
 * Loaded WASM module with auto-marshaled exports
 */
export interface WasmModule {
  /** Batch process multiple inputs */
  batch<T, R>(inputs: T[], funcName: string): R[];
  /** Access raw WASM memory */
  memory: WebAssembly.Memory;
  /** Access raw WASM exports without marshaling */
  _raw: WebAssembly.Exports;
  /** Any exported function - auto-marshals string args */
  [funcName: string]: (...args: any[]) => any;
}

/**
 * Load WASM module with dynamic imports
 *
 * @param source - URL or ArrayBuffer of WASM binary
 * @param customHandlers - User-provided handlers for @wasm_import functions
 * @returns Proxy-wrapped module with all exports
 *
 * @example
 * ```typescript
 * import { load } from '@metal0/wasm-runtime';
 *
 * const mod = await load('./my_module.wasm', {
 *   js: {
 *     myFetch: (ptr, len) => { ... }
 *   }
 * });
 *
 * const result = mod.process("hello");
 * ```
 */
export function load(
  source: string | ArrayBuffer,
  customHandlers?: ImportHandlers
): Promise<WasmModule>;

/** Legacy overload for type inference */
export function load<T extends object>(
  wasmSource: string | BufferSource
): Promise<T & WasmModule>;

/**
 * Batch process multiple inputs through a WASM function
 *
 * @param inputs - Array of inputs to process
 * @param funcName - Name of WASM function to call
 * @returns Array of results
 */
export function batch<T, R>(inputs: T[], funcName: string): R[];

/**
 * Register custom import handlers before loading
 *
 * @param namespace - Import namespace (e.g., "js", "wasi")
 * @param funcs - Object of handler functions
 *
 * @example
 * ```typescript
 * import { registerHandlers, load } from '@metal0/wasm-runtime';
 *
 * registerHandlers('js', {
 *   fetch: async (urlPtr, urlLen) => {
 *     const url = utils.readStr(urlPtr, urlLen);
 *     const res = await fetch(url);
 *     return utils.writeStr(await res.text());
 *   }
 * });
 *
 * const mod = await load('./module.wasm');
 * ```
 */
export function registerHandlers(
  namespace: string,
  funcs: { [funcName: string]: (...args: any[]) => any }
): void;

/**
 * Utility functions for implementing custom handlers
 */
export const utils: Utils;

declare const _default: {
  load: typeof load;
  batch: typeof batch;
  registerHandlers: typeof registerHandlers;
  utils: Utils;
};

export default _default;
