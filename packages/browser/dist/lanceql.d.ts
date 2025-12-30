// LanceQL WASM TypeScript Definitions
// Auto-marshalling: strings and Uint8Array are automatically copied to WASM memory

/** Raw WASM exports - use via lanceql._proxy for auto-marshalling */
export interface LanceQLWasm {
  // Memory management
  memory: WebAssembly.Memory;
  alloc(len: number): number;
  free(ptr: number, len: number): void;
  resetHeap(): void;

  // Version
  getVersion(): number;

  // File validation and parsing
  isValidLanceFile(data: Uint8Array): number;
  parseFooterGetColumns(data: Uint8Array): number;
  parseFooterGetMajorVersion(data: Uint8Array): number;
  parseFooterGetMinorVersion(data: Uint8Array): number;
  getColumnMetaStart(data: Uint8Array): bigint;
  getColumnMetaOffsetsStart(data: Uint8Array): bigint;

  // File operations
  openFile(data: Uint8Array): number;
  closeFile(): void;
  getNumColumns(): number;
  getRowCount(colIdx: number): bigint;
  getColumnBufferOffset(colIdx: number): bigint;
  getColumnBufferSize(colIdx: number): bigint;

  // Column reading - integers
  readInt64Column(colIdx: number, outPtr: number, maxLen: number): number;
  readInt32Column(colIdx: number, outPtr: number, maxLen: number): number;
  readInt16Column(colIdx: number, outPtr: number, maxLen: number): number;
  readInt8Column(colIdx: number, outPtr: number, maxLen: number): number;
  readUint64Column(colIdx: number, outPtr: number, maxLen: number): number;
  readUint32Column(colIdx: number, outPtr: number, maxLen: number): number;
  readUint16Column(colIdx: number, outPtr: number, maxLen: number): number;
  readUint8Column(colIdx: number, outPtr: number, maxLen: number): number;

  // Column reading - floats
  readFloat64Column(colIdx: number, outPtr: number, maxLen: number): number;
  readFloat32Column(colIdx: number, outPtr: number, maxLen: number): number;

  // Column reading - bool
  readBoolColumn(colIdx: number, outPtr: number, maxLen: number): number;

  // Index-based reading
  readInt64AtIndices(colIdx: number, indicesPtr: number, indicesLen: number, outPtr: number): number;
  readInt32AtIndices(colIdx: number, indicesPtr: number, indicesLen: number, outPtr: number): number;
  readFloat64AtIndices(colIdx: number, indicesPtr: number, indicesLen: number, outPtr: number): number;
  readFloat32AtIndices(colIdx: number, indicesPtr: number, indicesLen: number, outPtr: number): number;
  readUint8AtIndices(colIdx: number, indicesPtr: number, indicesLen: number, outPtr: number): number;
  readBoolAtIndices(colIdx: number, indicesPtr: number, indicesLen: number, outPtr: number): number;

  // Buffer allocation
  allocInt64Buffer(count: number): number;
  allocInt32Buffer(count: number): number;
  allocInt16Buffer(count: number): number;
  allocInt8Buffer(count: number): number;
  allocUint64Buffer(count: number): number;
  allocUint16Buffer(count: number): number;
  allocFloat64Buffer(count: number): number;
  allocFloat32Buffer(count: number): number;
  allocIndexBuffer(count: number): number;
  allocStringBuffer(size: number): number;
  allocU32Buffer(count: number): number;
  freeInt64Buffer(ptr: number, count: number): void;
  freeFloat64Buffer(ptr: number, count: number): void;

  // Filtering
  filterInt64Column(colIdx: number, op: number, value: bigint, outPtr: number, maxLen: number): number;
  filterFloat64Column(colIdx: number, op: number, value: number, outPtr: number, maxLen: number): number;

  // Aggregations
  sumInt64Column(colIdx: number): bigint;
  sumFloat64Column(colIdx: number): number;
  minInt64Column(colIdx: number): bigint;
  maxInt64Column(colIdx: number): bigint;
  avgFloat64Column(colIdx: number): number;

  // String columns
  getStringCount(colIdx: number): bigint;
  readStringAt(colIdx: number, rowIdx: number, outPtr: number, outMax: number): number;
  readStringsAtIndices(colIdx: number, indicesPtr: number, indicesLen: number, outPtr: number, offsetsPtr: number, maxBytes: number): number;

  // Vector columns
  getVectorInfo(colIdx: number): bigint;
  readVectorAt(colIdx: number, rowIdx: number, outPtr: number, outMax: number): number;

  // Vector similarity
  cosineSimilarity(aPtr: number, bPtr: number, dim: number): number;
  simdCosineSimilarity(aPtr: number, bPtr: number, dim: number): number;
  simdCosineSimilarityNormalized(aPtr: number, bPtr: number, dim: number): number;
  batchCosineSimilarity(queryPtr: number, vectorsPtr: number, dim: number, count: number, scoresPtr: number): void;
  vectorSearchTopK(colIdx: number, queryPtr: number, dim: number, k: number, indicesPtr: number, scoresPtr: number): number;
  vectorSearchBuffer(vectorsPtr: number, vectorCount: number, queryPtr: number, dim: number, k: number, indicesPtr: number, scoresPtr: number): number;
  mergeTopK(indicesA: number, scoresA: number, countA: number, indicesB: number, scoresB: number, countB: number, k: number, outIndices: number, outScores: number): number;

  // CLIP text encoder
  clip_init(): number;
  clip_get_text_buffer(): number;
  clip_get_text_buffer_size(): number;
  clip_get_output_buffer(): number;
  clip_get_output_dim(): number;
  clip_alloc_model_buffer(size: number): number;
  clip_weights_loaded(): number;
  clip_load_model(size: number): number;
  clip_encode_text(textLen: number): number;
  clip_test_add(a: number, b: number): number;

  // MiniLM text encoder
  minilm_init(): number;
  minilm_get_text_buffer(): number;
  minilm_get_text_buffer_size(): number;
  minilm_get_output_buffer(): number;
  minilm_get_output_dim(): number;
  minilm_alloc_model_buffer(size: number): number;
  minilm_weights_loaded(): number;
  minilm_load_model(size: number): number;
  minilm_encode_text(textLen: number): number;

  // Zstd decompression
  zstd_decompress(compressedPtr: number, compressedLen: number, outPtr: number, outLen: number): number;
  zstd_get_decompressed_size(compressedPtr: number, compressedLen: number): number;
}

/** WASM utilities for advanced usage */
export interface WasmUtils {
  readStr(ptr: number, len: number): string;
  readBytes(ptr: number, len: number): Uint8Array;
  encoder: TextEncoder;
  decoder: TextDecoder;
  getMemory(): WebAssembly.Memory;
  getExports(): LanceQLWasm;
}

export const wasmUtils: WasmUtils;

/** Lance file opened from local ArrayBuffer */
export class LanceFile {
  readonly numColumns: number;
  readonly majorVersion: number;
  readonly minorVersion: number;

  getRowCount(colIdx: number): number;
  readInt64Column(colIdx: number): BigInt64Array;
  readFloat64Column(colIdx: number): Float64Array;
  readStringAt(colIdx: number, rowIdx: number): string;
  getVectorInfo(colIdx: number): { dimension: number; rows: number };
  readVectorAt(colIdx: number, rowIdx: number): Float32Array;
  close(): void;
}

/** Lance file opened from remote URL via HTTP Range requests */
export class RemoteLanceFile {
  readonly url: string;
  readonly fileSize: number;
  readonly numColumns: number;
  readonly majorVersion: number;
  readonly minorVersion: number;

  static open(lanceql: LanceQL, url: string): Promise<RemoteLanceFile>;

  getRowCount(): Promise<number>;
  getColumnType(colIdx: number): Promise<string>;
  readColumnData(colIdx: number, offset: number, length: number): Promise<ArrayBuffer>;
  readInt64Column(colIdx: number, limit?: number): Promise<BigInt64Array>;
  readFloat64Column(colIdx: number, limit?: number): Promise<Float64Array>;
  readStrings(colIdx: number, limit?: number): Promise<string[]>;
  getVectorInfo(colIdx: number): Promise<{ dimension: number; rows: number }>;
  readVectors(colIdx: number, indices: number[]): Promise<Float32Array[]>;
  close(): void;
}

/** Lance dataset with multiple fragments */
export class RemoteLanceDataset {
  readonly baseUrl: string;
  readonly version: number;
  readonly numColumns: number;
  readonly columnNames: string[];
  readonly totalRows: number;

  static open(lanceql: LanceQL, baseUrl: string, options?: { version?: number }): Promise<RemoteLanceDataset>;

  getVersions(): Promise<number[]>;
  getColumnType(colIdx: number): Promise<string>;
  readInt64Column(colIdx: number, limit?: number, offset?: number): Promise<BigInt64Array>;
  readFloat64Column(colIdx: number, limit?: number, offset?: number): Promise<Float64Array>;
  readStrings(colIdx: number, limit?: number, offset?: number): Promise<string[]>;
  readStringsAtIndices(colIdx: number, indices: number[]): Promise<string[]>;
  getVectorInfo(colIdx: number): Promise<{ dimension: number; rows: number }>;
  readVectorsAtIndices(colIdx: number, indices: number[]): Promise<Float32Array[]>;
  vectorSearch(colIdx: number, query: Float32Array, k: number): Promise<{ indices: number[]; scores: number[] }>;
}

/**
 * LanceQL - Immer-style proxy with auto string/bytes marshalling
 *
 * Usage:
 *   const lanceql = await LanceQL.load('./lanceql.wasm');
 *   lanceql.someFunc("hello");       // strings auto-copied to WASM memory
 *   lanceql.parseData(bytes);        // Uint8Array auto-copied too
 *   lanceql.raw.someFunc(ptr, len);  // raw access when needed
 */
export interface LanceQL extends LanceQLWasm {
  /** Raw WASM exports without auto marshalling */
  readonly raw: LanceQLWasm;
  /** WASM exports (backward compatibility, same as raw) */
  readonly wasm: LanceQLWasm;
  /** WASM memory */
  readonly memory: WebAssembly.Memory;

  /** Get library version string (e.g., "0.1.0") */
  getVersion(): string;

  /** Open local Lance file from ArrayBuffer */
  open(data: ArrayBuffer): LanceFile;

  /** Open remote Lance file via HTTP Range requests */
  openUrl(url: string): Promise<RemoteLanceFile>;

  /** Open remote Lance dataset with manifest discovery */
  openDataset(baseUrl: string, options?: { version?: number }): Promise<RemoteLanceDataset>;

  /** Parse footer from Lance file data */
  parseFooter(data: ArrayBuffer): { numColumns: number; majorVersion: number; minorVersion: number } | null;

  /** Check if data is a valid Lance file */
  isValidLanceFile(data: ArrayBuffer): boolean;
}

export const LanceQL: {
  /**
   * Load LanceQL from WASM file
   * @param wasmPath Path to lanceql.wasm file
   */
  load(wasmPath?: string): Promise<LanceQL>;
};

export default LanceQL;

// =============================================================================
// Dataset Storage (IndexedDB + OPFS)
// =============================================================================

export interface DatasetInfo {
  name: string;
  size: number;
  timestamp: number;
  storage: 'indexeddb' | 'opfs';
  [key: string]: any;
}

export interface StorageUsage {
  datasets: number;
  totalSize: number;
  indexedDBCount: number;
  opfsCount: number;
  quota: {
    usage: number;
    quota: number;
  } | null;
}

export interface DatasetStorage {
  /**
   * Save a dataset file to local storage.
   * Files <50MB use IndexedDB, larger files use OPFS.
   * @param name Unique dataset name
   * @param data File data
   * @param metadata Optional metadata to store
   */
  save(name: string, data: ArrayBuffer | Uint8Array, metadata?: Record<string, any>): Promise<DatasetInfo>;

  /**
   * Load a dataset file from local storage.
   * @param name Dataset name
   * @returns File data or null if not found
   */
  load(name: string): Promise<Uint8Array | null>;

  /**
   * List all saved datasets.
   */
  list(): Promise<DatasetInfo[]>;

  /**
   * Delete a saved dataset.
   * @param name Dataset name
   */
  delete(name: string): Promise<void>;

  /**
   * Check if a dataset exists.
   * @param name Dataset name
   */
  exists(name: string): Promise<boolean>;

  /**
   * Get storage usage information.
   */
  getUsage(): Promise<StorageUsage>;
}

/** Global dataset storage instance */
export const datasetStorage: DatasetStorage;

/** DatasetStorage class for creating custom instances */
export const DatasetStorage: {
  new(dbName?: string, version?: number): DatasetStorage;
};

// =============================================================================
// CSS-Driven Data Engine (LanceData)
// =============================================================================

/**
 * LanceData initialization options
 */
export interface LanceDataOptions {
  /** Default dataset URL */
  dataset?: string;
  /** WASM module URL (optional) */
  wasmUrl?: string;
}

/**
 * Custom renderer function type
 */
export type LanceDataRenderer = (results: any[], config: LanceDataConfig) => string;

/**
 * Configuration parsed from CSS variables
 */
export interface LanceDataConfig {
  /** SQL query from --query variable */
  query?: string;
  /** Renderer type from --render variable */
  render: string;
  /** Input binding selector from --bind variable */
  bind?: string;
  /** Dataset URL from --dataset variable */
  dataset?: string;
  /** Column names from --columns variable */
  columns?: string[];
  /** Row limit from --limit variable */
  limit?: number;
}

/**
 * CSS-driven data binding for Lance datasets.
 *
 * @example
 * ```html
 * <!-- Pure CSS data binding -->
 * <div class="lance-data"
 *      style="--query: 'SELECT * FROM data LIMIT 10'; --render: table;">
 * </div>
 * ```
 *
 * CSS Variables:
 * - --query: SQL query string (required)
 * - --render: Renderer type - table, list, value, images, json, count (default: table)
 * - --bind: Input element selector for reactive binding
 * - --dataset: Dataset URL (optional, uses default if not set)
 * - --columns: Comma-separated column names to display
 * - --limit: Maximum rows to display
 */
export class LanceData {
  /**
   * Initialize CSS-driven data binding.
   * Must be called once before using lance-data elements.
   */
  static init(options?: LanceDataOptions): Promise<void>;

  /**
   * Register a custom renderer.
   * @param name Renderer name (used in --render CSS variable)
   * @param fn Renderer function (results, config) => html
   */
  static registerRenderer(name: string, fn: LanceDataRenderer): void;

  /**
   * Clear the query cache.
   */
  static clearCache(): void;

  /**
   * Refresh all lance-data elements.
   */
  static refresh(): void;

  /**
   * Destroy and clean up all bindings.
   */
  static destroy(): void;
}

export { LanceData };
