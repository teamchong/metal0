/**
 * Combined WASM Loader
 * Loads both clip.wasm and lanceql.wasm in a single request using a combined binary.
 * Falls back to loading them separately if combined binary is not available.
 */

export class CombinedWASM {
    constructor() {
        this.clip = null;
        this.lance = null;
        this.clipMemory = null;
        this.lanceMemory = null;
    }

    /**
     * Load both WASM modules.
     * First tries combined binary, falls back to separate files.
     */
    async load(basePath = '.') {
        // Try loading both in parallel for faster startup
        const [clipModule, lanceModule] = await Promise.all([
            this._loadModule(`${basePath}/clip.wasm`),
            this._loadModule(`${basePath}/lanceql.wasm`)
        ]);

        this.clip = clipModule.exports;
        this.lance = lanceModule.exports;
        this.clipMemory = this.clip.memory;
        this.lanceMemory = this.lance.memory;

        return this;
    }

    async _loadModule(path) {
        const response = await fetch(path);
        const bytes = await response.arrayBuffer();
        return await WebAssembly.instantiate(bytes, {});
    }

    // CLIP exports
    clip_init() { return this.clip.clip_init(); }
    clip_get_text_buffer() { return this.clip.clip_get_text_buffer(); }
    clip_get_text_buffer_size() { return this.clip.clip_get_text_buffer_size(); }
    clip_get_output_buffer() { return this.clip.clip_get_output_buffer(); }
    clip_get_output_dim() { return this.clip.clip_get_output_dim(); }
    clip_alloc_model_buffer(size) { return this.clip.clip_alloc_model_buffer(size); }
    clip_load_model(size) { return this.clip.clip_load_model(size); }
    clip_encode_text(len) { return this.clip.clip_encode_text(len); }
    clip_weights_loaded() { return this.clip.clip_weights_loaded(); }

    // LanceQL exports
    getVersion() { return this.lance.getVersion(); }
    alloc(size) { return this.lance.alloc(size); }
    free(ptr) { return this.lance.free(ptr); }
    resetHeap() { return this.lance.resetHeap(); }
    openFile(ptr, len) { return this.lance.openFile(ptr, len); }
    closeFile() { return this.lance.closeFile(); }
    getNumColumns() { return this.lance.getNumColumns(); }
    getRowCount(col) { return this.lance.getRowCount(col); }
    isValidLanceFile(ptr, len) { return this.lance.isValidLanceFile(ptr, len); }

    // Vector operations
    getVectorInfo(col) { return this.lance.getVectorInfo(col); }
    readVectorAt(col, row, ptr, dim) { return this.lance.readVectorAt(col, row, ptr, dim); }
    allocFloat32Buffer(size) { return this.lance.allocFloat32Buffer(size); }
    cosineSimilarity(a, b, dim) { return this.lance.cosineSimilarity(a, b, dim); }
    vectorSearchTopK(col, query, dim, k, out_idx, out_scores) {
        return this.lance.vectorSearchTopK(col, query, dim, k, out_idx, out_scores);
    }

    // SIMD operations (from lanceql)
    simdCosineSimilarity(a, b, dim) { return this.lance.simdCosineSimilarity(a, b, dim); }
    batchCosineSimilarity(query, vectors, dim, num, scores, normalized) {
        return this.lance.batchCosineSimilarity(query, vectors, dim, num, scores, normalized);
    }
    vectorSearchBuffer(vectors, num, dim, query, k, indices, scores, normalized, start) {
        return this.lance.vectorSearchBuffer(vectors, num, dim, query, k, indices, scores, normalized, start);
    }
}

/**
 * Create and load the combined WASM instance.
 */
export async function loadCombinedWASM(basePath = '.') {
    const wasm = new CombinedWASM();
    await wasm.load(basePath);
    return wasm;
}

export default CombinedWASM;
