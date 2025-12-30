/**
 * LanceQL WASM Loader and Initialization
 *
 * Core module for loading the LanceQL WebAssembly module and managing
 * the WASM runtime environment.
 */

// Immer-style WASM runtime - auto string/bytes marshalling
const E = new TextEncoder();
const D = new TextDecoder();
let _w, _m, _p = 0, _M = 0;

// Get shared buffer view (lazy allocation)
const _g = () => {
    if (!_p || !_M) return null;
    return new Uint8Array(_m.buffer, _p, _M);
};

// Ensure shared buffer is large enough
const _ensure = (size) => {
    if (_p && size <= _M) return true;
    // Free old buffer if exists
    if (_p && _w.free) _w.free(_p, _M);
    _M = Math.max(size + 1024, 4096); // At least 4KB
    _p = _w.alloc(_M);
    return _p !== 0;
};

// Marshal JS value to WASM args (strings and Uint8Array auto-copied to WASM memory)
const _x = a => {
    if (a instanceof Uint8Array) {
        if (!_ensure(a.length)) return [a]; // Fallback if alloc fails
        _g().set(a);
        return [_p, a.length];
    }
    if (typeof a !== 'string') return [a];
    const b = E.encode(a);
    if (!_ensure(b.length)) return [a]; // Fallback if alloc fails
    _g().set(b);
    return [_p, b.length];
};

// Read string from WASM memory
export const readStr = (ptr, len) => D.decode(new Uint8Array(_m.buffer, ptr, len));

// Read bytes from WASM memory (returns copy)
export const readBytes = (ptr, len) => new Uint8Array(_m.buffer, ptr, len).slice();

// WASM utils exported for advanced usage
export const wasmUtils = {
    readStr,
    readBytes,
    encoder: E,
    decoder: D,
    getMemory: () => _m,
    getExports: () => _w,
};

// LanceQL high-level methods factory (needs proxy reference)
const _createLanceqlMethods = (proxy) => ({
    /**
     * Get the library version.
     * @returns {string} Version string like "0.1.0"
     */
    getVersion() {
        const v = _w.getVersion();
        const major = (v >> 16) & 0xFF;
        const minor = (v >> 8) & 0xFF;
        const patch = v & 0xFF;
        return `${major}.${minor}.${patch}`;
    },

    /**
     * Open a Lance file from an ArrayBuffer (local file).
     * @param {ArrayBuffer} data - The Lance file data
     * @returns {LanceFile}
     */
    open(data) {
        // Import dynamically to avoid circular dependencies
        const { LanceFile } = require('./file.js');
        return new LanceFile(proxy, data);
    },

    /**
     * Open a Lance file from a URL using HTTP Range requests.
     * @param {string} url - URL to the Lance file
     * @returns {Promise<RemoteLanceFile>}
     */
    async openUrl(url) {
        const { RemoteLanceFile } = require('./remote-file.js');
        return await RemoteLanceFile.open(proxy, url);
    },

    /**
     * Open a Lance dataset from a base URL using HTTP Range requests.
     * @param {string} baseUrl - Base URL to the Lance dataset
     * @param {object} [options] - Options for opening
     * @param {number} [options.version] - Specific version to load
     * @returns {Promise<RemoteLanceDataset>}
     */
    async openDataset(baseUrl, options = {}) {
        const { RemoteLanceDataset } = require('./dataset.js');
        return await RemoteLanceDataset.open(proxy, baseUrl, options);
    },

    /**
     * Parse footer from Lance file data.
     * @param {ArrayBuffer} data
     * @returns {{numColumns: number, majorVersion: number, minorVersion: number} | null}
     */
    parseFooter(data) {
        const bytes = new Uint8Array(data);
        const ptr = _w.alloc(bytes.length);
        if (!ptr) return null;

        try {
            new Uint8Array(_m.buffer).set(bytes, ptr);

            const numColumns = _w.parseFooterGetColumns(ptr, bytes.length);
            const majorVersion = _w.parseFooterGetMajorVersion(ptr, bytes.length);
            const minorVersion = _w.parseFooterGetMinorVersion(ptr, bytes.length);

            if (numColumns === 0 && majorVersion === 0) {
                return null;
            }

            return { numColumns, majorVersion, minorVersion };
        } finally {
            _w.free(ptr, bytes.length);
        }
    },

    /**
     * Check if data is a valid Lance file.
     * @param {ArrayBuffer} data
     * @returns {boolean}
     */
    isValidLanceFile(data) {
        const bytes = new Uint8Array(data);
        const ptr = _w.alloc(bytes.length);
        if (!ptr) return false;

        try {
            new Uint8Array(_m.buffer).set(bytes, ptr);
            return _w.isValidLanceFile(ptr, bytes.length) === 1;
        } finally {
            _w.free(ptr, bytes.length);
        }
    }
});

/**
 * LanceQL WASM loader class
 *
 * Provides an Immer-style proxy interface to the LanceQL WebAssembly module
 * with automatic marshalling of strings and byte arrays.
 */
export class LanceQL {
    /**
     * Load LanceQL from a WASM file path or URL.
     * Returns Immer-style proxy with auto string/bytes marshalling.
     * @param {string} wasmPath - Path to the lanceql.wasm file
     * @returns {Promise<LanceQL>}
     */
    static async load(wasmPath = './lanceql.wasm') {
        const response = await fetch(wasmPath);
        const wasmBytes = await response.arrayBuffer();
        const wasmModule = await WebAssembly.instantiate(wasmBytes, {});

        _w = wasmModule.instance.exports;
        _m = _w.memory;

        // Create Immer-style proxy that auto-marshals string/bytes arguments
        // Also includes high-level LanceQL methods
        let _methods = null;
        const proxy = new Proxy({}, {
            get(_, n) {
                // Lazy init methods with proxy reference
                if (!_methods) _methods = _createLanceqlMethods(proxy);
                // High-level LanceQL methods
                if (n in _methods) return _methods[n];
                // Special properties
                if (n === 'memory') return _m;
                if (n === 'raw') return _w;  // Raw WASM exports
                if (n === 'wasm') return _w; // Backward compatibility
                // WASM functions with auto-marshalling
                if (typeof _w[n] === 'function') {
                    return (...a) => _w[n](...a.flatMap(_x));
                }
                return _w[n];
            }
        });

        return proxy;
    }
}

// Export default
export default LanceQL;
