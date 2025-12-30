/**
 * LanceQL Worker - Runs WASM operations in parallel for vector search and data processing.
 *
 * This worker:
 * 1. Loads its own copy of the WASM module
 * 2. Receives vector data from main thread (via transferable ArrayBuffer or SharedArrayBuffer)
 * 3. Performs SIMD-accelerated vector search
 * 4. Returns top-k results to main thread
 */

let wasm = null;
let memory = null;
let workerId = -1;

// Initialize WASM module
async function initWasm() {
    try {
        const response = await fetch('lanceql.wasm');
        const bytes = await response.arrayBuffer();
        const module = await WebAssembly.instantiate(bytes, {
            env: {
                // No imports needed for our simple WASM
            }
        });

        wasm = module.instance.exports;
        memory = wasm.memory;

        return true;
    } catch (e) {
        console.error('[Worker] Failed to init WASM:', e);
        return false;
    }
}

// Copy Float32Array to WASM memory and return pointer
function copyToWasm(data) {
    const ptr = wasm.alloc(data.byteLength);
    if (!ptr) throw new Error('Failed to allocate WASM memory');

    const wasmArray = new Uint8Array(memory.buffer, ptr, data.byteLength);
    wasmArray.set(new Uint8Array(data.buffer, data.byteOffset, data.byteLength));

    return ptr;
}

// Allocate output buffers in WASM
function allocateOutputBuffers(k) {
    const indicesPtr = wasm.allocIndexBuffer(k);
    const scoresPtr = wasm.allocFloat32Buffer(k);

    if (!indicesPtr || !scoresPtr) {
        throw new Error('Failed to allocate output buffers');
    }

    return { indicesPtr, scoresPtr };
}

// Read results from WASM memory
function readResults(indicesPtr, scoresPtr, k) {
    const indices = new Uint32Array(memory.buffer, indicesPtr, k);
    const scores = new Float32Array(memory.buffer, scoresPtr, k);

    // Copy to new arrays (memory may be invalidated on reset)
    return {
        indices: new Uint32Array(indices),
        scores: new Float32Array(scores)
    };
}

/**
 * Perform vector search on a chunk of vectors.
 *
 * @param {Object} params
 * @param {Float32Array} params.vectors - Flattened vector data [numVectors * dim]
 * @param {Float32Array} params.query - Query vector [dim]
 * @param {number} params.dim - Vector dimension
 * @param {number} params.numVectors - Number of vectors
 * @param {number} params.topK - Number of results to return
 * @param {number} params.startIndex - Global start index for this chunk
 * @param {boolean} params.normalized - Whether vectors are L2-normalized
 */
function vectorSearch(params) {
    const { vectors, query, dim, numVectors, topK, startIndex, normalized } = params;

    // Reset heap for each search to avoid memory fragmentation
    wasm.resetHeap();

    // Copy data to WASM memory
    const vectorsPtr = copyToWasm(vectors);
    const queryPtr = copyToWasm(query);

    // Allocate output buffers
    const { indicesPtr, scoresPtr } = allocateOutputBuffers(topK);

    // Perform SIMD-accelerated search
    const resultCount = wasm.vectorSearchBuffer(
        vectorsPtr,
        numVectors,
        dim,
        queryPtr,
        topK,
        indicesPtr,
        scoresPtr,
        normalized ? 1 : 0,
        startIndex
    );

    // Read results
    const results = readResults(indicesPtr, scoresPtr, resultCount);

    return {
        indices: results.indices,
        scores: results.scores,
        count: resultCount
    };
}

/**
 * Process a fragment file - decode footer, metadata, and extract vectors.
 * Used when vectors need to be extracted from raw Lance file data.
 */
function processFragment(params) {
    const { fileData, vectorColIdx, startIndex } = params;

    wasm.resetHeap();

    // Copy file data to WASM
    const filePtr = copyToWasm(new Uint8Array(fileData));

    // Open file
    if (!wasm.openFile(filePtr, fileData.byteLength)) {
        throw new Error('Invalid Lance file');
    }

    // Get vector info
    const vecInfo = wasm.getVectorInfo(vectorColIdx);
    const numRows = Number(vecInfo >> 32n);
    const dim = Number(vecInfo & 0xFFFFFFFFn);

    if (dim === 0 || numRows === 0) {
        wasm.closeFile();
        return { numRows: 0, dim: 0, vectors: null };
    }

    // Read all vectors
    const vectorsPtr = wasm.allocFloat32Buffer(numRows * dim);
    if (!vectorsPtr) {
        wasm.closeFile();
        throw new Error('Failed to allocate vector buffer');
    }

    // Read vectors row by row
    const vectors = new Float32Array(numRows * dim);
    for (let i = 0; i < numRows; i++) {
        const tempPtr = wasm.allocFloat32Buffer(dim);
        wasm.readVectorAt(vectorColIdx, i, tempPtr, dim);
        const rowVec = new Float32Array(memory.buffer, tempPtr, dim);
        vectors.set(rowVec, i * dim);
    }

    wasm.closeFile();

    return {
        numRows,
        dim,
        vectors,
        startIndex
    };
}

/**
 * Batch cosine similarity computation.
 */
function batchSimilarity(params) {
    const { query, vectors, dim, numVectors, normalized } = params;

    wasm.resetHeap();

    const queryPtr = copyToWasm(query);
    const vectorsPtr = copyToWasm(vectors);
    const scoresPtr = wasm.allocFloat32Buffer(numVectors);

    if (!scoresPtr) {
        throw new Error('Failed to allocate scores buffer');
    }

    wasm.batchCosineSimilarity(
        queryPtr,
        vectorsPtr,
        dim,
        numVectors,
        scoresPtr,
        normalized ? 1 : 0
    );

    const scores = new Float32Array(memory.buffer, scoresPtr, numVectors);
    return { scores: new Float32Array(scores) };
}

// Message handler
self.onmessage = async function(e) {
    const { type, id, params } = e.data;

    try {
        let result;

        switch (type) {
            case 'init':
                workerId = params.workerId;
                const success = await initWasm();
                result = { success, workerId };
                break;

            case 'vectorSearch':
                result = vectorSearch(params);
                break;

            case 'processFragment':
                result = processFragment(params);
                break;

            case 'batchSimilarity':
                result = batchSimilarity(params);
                break;

            case 'ping':
                result = { pong: true, workerId };
                break;

            default:
                throw new Error(`Unknown message type: ${type}`);
        }

        // Send response with transferable arrays for efficiency
        const transfer = [];
        if (result.indices) transfer.push(result.indices.buffer);
        if (result.scores) transfer.push(result.scores.buffer);
        if (result.vectors) transfer.push(result.vectors.buffer);

        self.postMessage({ id, success: true, result }, transfer);

    } catch (error) {
        self.postMessage({
            id,
            success: false,
            error: error.message
        });
    }
};

// Report ready
self.postMessage({ type: 'ready' });
