import fs from 'fs';

const wasmBuffer = fs.readFileSync('./clip.wasm');
const { instance } = await WebAssembly.instantiate(wasmBuffer);
const wasm = instance.exports;

console.log('WASM loaded');

const initResult = wasm.clip_init();
console.log('Init result:', initResult);

console.log('Loading model...');
// Use OpenAI CLIP model
const modelData = fs.readFileSync('./clip-vit-b32-openai.gguf');
console.log('Model size:', modelData.byteLength, 'bytes');

const bufPtr = wasm.clip_alloc_model_buffer(modelData.byteLength);
console.log('Buffer allocated at:', bufPtr);

if (!bufPtr) {
    console.log('ERROR: Failed to allocate buffer');
    process.exit(1);
}

const wasmMem = new Uint8Array(wasm.memory.buffer);
wasmMem.set(modelData, bufPtr);
console.log('Model data copied');

const loadResult = wasm.clip_load_model(modelData.byteLength);
console.log('Load result:', loadResult);

if (loadResult !== 0) {
    console.log('ERROR: Model loading failed');
    process.exit(1);
}

console.log('Encoding: "a photo of a cat"');
const text = 'a photo of a cat';
const textBuf = wasm.clip_get_text_buffer();
const textBytes = new TextEncoder().encode(text);
const mem = new Uint8Array(wasm.memory.buffer);
mem.set(textBytes, textBuf);

const encodeResult = wasm.clip_encode_text(textBytes.length);
console.log('Encode result:', encodeResult);

if (encodeResult !== 0) {
    console.log('ERROR: Encoding failed');
    process.exit(1);
}

const outputBuf = wasm.clip_get_output_buffer();
const outputDim = wasm.clip_get_output_dim();
const embedding = new Float32Array(wasm.memory.buffer, outputBuf, outputDim);

console.log('First 8:', Array.from(embedding.slice(0, 8)).map(v => v.toFixed(4)));

let norm = 0;
for (let i = 0; i < embedding.length; i++) norm += embedding[i] ** 2;
console.log('L2 norm:', Math.sqrt(norm).toFixed(6));

console.log('SUCCESS!');
