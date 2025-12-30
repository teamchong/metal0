import fs from 'fs';

// Load WASM directly
const wasmBuffer = fs.readFileSync('./lanceql.wasm');
const { instance } = await WebAssembly.instantiate(wasmBuffer);
const wasm = instance.exports;

// Use the newer file with FixedSizeList
const files = fs.readdirSync('clip_sample.lance/data/');
const lanceFile = files.find(f => f.endsWith('.lance'));
console.log('Using file:', lanceFile);
const data = fs.readFileSync(`clip_sample.lance/data/${lanceFile}`);

// Check magic bytes
const magic = Buffer.from(data.slice(-4)).toString();
console.log('Magic:', magic);
console.log('File valid:', magic === 'LANC');

// Get footer info
const footer = data.slice(-40);
const numColumns = footer.readUInt32LE(28);
console.log('numColumns from footer:', numColumns);

// Copy data to WASM memory
const dataPtr = wasm.alloc(data.length);
console.log('Data ptr:', dataPtr);
const wasmMem = new Uint8Array(wasm.memory.buffer);
wasmMem.set(new Uint8Array(data.buffer || data), dataPtr);

// Open lance file
const openResult = wasm.openFile(dataPtr, data.length);
console.log('Open result:', openResult);

if (openResult === 0) {
    console.log('ERROR: Failed to open lance file');
    process.exit(1);
}

// Get column count
const colCount = wasm.getNumColumns();
console.log('WASM numColumns:', colCount);

// Try to read vector info for each column
console.log('\n=== Vector Info ===');
for (let i = 0; i < colCount; i++) {
    try {
        const packed = wasm.getVectorInfo(i);
        const rows = Number(BigInt(packed) >> 32n);
        const dimension = Number(BigInt(packed) & 0xFFFFFFFFn);
        console.log('Column', i, '- rows:', rows, 'dimension:', dimension);
    } catch (e) {
        console.log('Column', i, 'error:', e.message);
    }
}

// Try column debug info
console.log('\n=== Column Debug Info ===');
for (let i = 0; i < colCount; i++) {
    try {
        const infoPtr = wasm.getColumnDebugInfo(i);
        if (infoPtr) {
            const view = new DataView(wasm.memory.buffer, infoPtr, 48);
            const numPages = view.getUint32(0, true);
            const rows = Number(view.getBigUint64(8, true));
            const nulls = Number(view.getBigUint64(16, true));
            const encoding = view.getUint8(24);
            const physicalType = view.getUint8(25);
            console.log('Column', i, '- pages:', numPages, 'rows:', rows, 'nulls:', nulls, 'encoding:', encoding, 'physicalType:', physicalType);
        }
    } catch (e) {
        console.log('Column', i, 'debug error:', e.message);
    }
}

// Test string reading
console.log('\n=== String Reading ===');
for (let col = 0; col < 2; col++) {
    console.log(`\nColumn ${col} string count:`, wasm.getStringCount(col));
    for (let row = 0; row < 3; row++) {
        const maxLen = 4096;
        const bufPtr = wasm.allocStringBuffer(maxLen);
        if (bufPtr) {
            const len = wasm.readStringAt(col, row, bufPtr, maxLen);
            console.log(`  Row ${row}: len=${len}`);
            if (len > 0) {
                const bytes = new Uint8Array(wasm.memory.buffer, bufPtr, len);
                const str = new TextDecoder().decode(bytes);
                console.log(`    Value: "${str}"`);
            }
            wasm.free(bufPtr, maxLen);
        }
    }
}

wasm.closeFile();
console.log('\nDone');
