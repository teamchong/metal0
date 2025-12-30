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
// OPFS Storage (Origin Private File System)
// =============================================================================

/**
 * OPFS-only storage for Lance database files.
 * Uses Origin Private File System exclusively for high-performance file access.
 */
export interface OPFSStorage {
  /**
   * Open the storage (ensure root directory exists)
   */
  open(): Promise<OPFSStorage>;

  /**
   * Save data to a file
   * @param path File path (e.g., 'mydb/users/frag_001.lance')
   * @param data File data
   */
  save(path: string, data: Uint8Array): Promise<{ path: string; size: number }>;

  /**
   * Load data from a file
   * @param path File path
   * @returns File data or null if not found
   */
  load(path: string): Promise<Uint8Array | null>;

  /**
   * Delete a file
   * @param path File path
   */
  delete(path: string): Promise<boolean>;

  /**
   * List files in a directory
   * @param dirPath Directory path
   */
  list(dirPath?: string): Promise<Array<{ name: string; type: 'file' | 'directory' }>>;

  /**
   * Check if a file exists
   * @param path File path
   */
  exists(path: string): Promise<boolean>;

  /**
   * Delete a directory and all contents
   * @param dirPath Directory path
   */
  deleteDir(dirPath: string): Promise<boolean>;

  /**
   * Read a byte range from a file without loading the entire file
   * @param path File path
   * @param offset Start byte offset
   * @param length Number of bytes to read
   */
  readRange(path: string, offset: number, length: number): Promise<Uint8Array | null>;

  /**
   * Get file size without loading the file
   * @param path File path
   */
  getFileSize(path: string): Promise<number | null>;

  /**
   * Open a file for chunked reading
   * @param path File path
   */
  openFile(path: string): Promise<OPFSFileReader | null>;
}

/** Global OPFS storage instance */
export const opfsStorage: OPFSStorage;

/** OPFSStorage class for creating custom instances */
export const OPFSStorage: {
  new(rootDir?: string): OPFSStorage;
};

/**
 * OPFS File Reader for chunked/streaming reads.
 * Wraps a FileSystemFileHandle for efficient byte-range access.
 */
export interface OPFSFileReader {
  /**
   * Get file size
   */
  getSize(): Promise<number>;

  /**
   * Read a byte range
   * @param offset Start byte offset
   * @param length Number of bytes to read
   */
  readRange(offset: number, length: number): Promise<Uint8Array>;

  /**
   * Read from end of file (useful for footer)
   * @param length Number of bytes to read from end
   */
  readFromEnd(length: number): Promise<Uint8Array>;

  /**
   * Invalidate cache (call after file is modified)
   */
  invalidate(): void;
}

/** OPFSFileReader class */
export const OPFSFileReader: {
  new(fileHandle: FileSystemFileHandle): OPFSFileReader;
};

/**
 * LRU Cache statistics
 */
export interface LRUCacheStats {
  entries: number;
  currentSize: number;
  maxSize: number;
  utilization: string;
}

/**
 * LRU Cache for page data.
 * Keeps recently accessed pages in memory to avoid repeated OPFS reads.
 */
export interface LRUCache {
  /**
   * Get item from cache
   * @param key Cache key
   */
  get(key: string): Uint8Array | null;

  /**
   * Put item in cache
   * @param key Cache key
   * @param data Data to cache
   */
  put(key: string, data: Uint8Array): void;

  /**
   * Clear entire cache
   */
  clear(): void;

  /**
   * Get cache statistics
   */
  stats(): LRUCacheStats;
}

/** LRUCache class */
export const LRUCache: {
  new(maxSize?: number): LRUCache;
};

/**
 * Lance file footer information
 */
export interface LanceFooter {
  columnMetaStart: bigint;
  columnMetaOffsetsStart: bigint;
  globalBuffOffsetsStart: bigint;
  numGlobalBuffers: number;
  numColumns: number;
  majorVersion: number;
  minorVersion: number;
}

/**
 * Chunked Lance File Reader.
 * Reads Lance files from OPFS without loading entire file into memory.
 */
export interface ChunkedLanceReader {
  /** Parsed footer information */
  readonly footer: LanceFooter | null;

  /**
   * Get file size
   */
  getSize(): Promise<number>;

  /**
   * Get number of columns
   */
  getNumColumns(): number;

  /**
   * Get Lance format version
   */
  getVersion(): { major: number; minor: number };

  /**
   * Read raw column metadata bytes
   * @param colIdx Column index
   */
  readColumnMetaRaw(colIdx: number): Promise<Uint8Array>;

  /**
   * Read a specific byte range from the file
   * @param offset Start offset
   * @param length Number of bytes
   */
  readRange(offset: number, length: number): Promise<Uint8Array>;

  /**
   * Get cache statistics
   */
  getCacheStats(): LRUCacheStats;

  /**
   * Close the reader and release resources
   */
  close(): void;
}

/** ChunkedLanceReader class */
export const ChunkedLanceReader: {
  /**
   * Open a Lance file from OPFS
   * @param storage OPFS storage instance
   * @param path File path in OPFS
   * @param pageCache Optional shared page cache
   */
  open(storage: OPFSStorage, path: string, pageCache?: LRUCache): Promise<ChunkedLanceReader>;
};

// =============================================================================
// Protobuf Encoder
// =============================================================================

/**
 * Simple Protobuf encoder for Lance metadata.
 * Only implements what's needed for Lance file writing.
 */
export interface ProtobufEncoder {
  /**
   * Encode a varint field
   * @param fieldNum Field number
   * @param value Value to encode
   */
  writeVarint(fieldNum: number, value: number | bigint): void;

  /**
   * Encode a length-delimited field (bytes or nested message)
   * @param fieldNum Field number
   * @param data Data to encode
   */
  writeBytes(fieldNum: number, data: Uint8Array): void;

  /**
   * Encode packed repeated uint64 as varints
   * @param fieldNum Field number
   * @param values Values to encode
   */
  writePackedUint64(fieldNum: number, values: bigint[] | number[]): void;

  /**
   * Get the encoded bytes
   */
  toBytes(): Uint8Array;

  /**
   * Clear the encoder for reuse
   */
  clear(): void;
}

/** ProtobufEncoder class */
export const ProtobufEncoder: {
  new(): ProtobufEncoder;

  /**
   * Encode a varint (variable-length integer)
   */
  encodeVarint(value: number | bigint): Uint8Array;

  /**
   * Encode a field header (tag)
   */
  encodeFieldHeader(fieldNum: number, wireType: number): Uint8Array;
};

// =============================================================================
// Pure Lance Writer (No WASM)
// =============================================================================

/**
 * Lance column types
 */
export const LanceColumnType: {
  INT64: 'int64';
  FLOAT64: 'float64';
  STRING: 'string';
  BOOL: 'bool';
  INT32: 'int32';
  FLOAT32: 'float32';
};

/**
 * Pure Lance Writer options
 */
export interface PureLanceWriterOptions {
  /** Lance format major version (default: 0) */
  majorVersion?: number;
  /** Lance format minor version (default: 3 for v2.0) */
  minorVersion?: number;
}

/**
 * Pure JavaScript Lance File Writer - Creates Lance files without WASM.
 * Use this when WASM is not available or for simple file creation.
 * Supports basic column types: int64, float64, string, bool.
 *
 * @example
 * ```javascript
 * const writer = new PureLanceWriter();
 * writer.addInt64Column('id', BigInt64Array.from([1n, 2n, 3n]));
 * writer.addFloat64Column('score', new Float64Array([0.5, 0.8, 0.3]));
 * writer.addStringColumn('name', ['Alice', 'Bob', 'Charlie']);
 * const lanceData = writer.finalize();
 * await opfsStorage.save('mydata.lance', lanceData);
 * ```
 */
export interface PureLanceWriter {
  /**
   * Add an int64 column
   * @param name Column name
   * @param values Column values
   */
  addInt64Column(name: string, values: BigInt64Array): void;

  /**
   * Add an int32 column
   * @param name Column name
   * @param values Column values
   */
  addInt32Column(name: string, values: Int32Array): void;

  /**
   * Add a float64 column
   * @param name Column name
   * @param values Column values
   */
  addFloat64Column(name: string, values: Float64Array): void;

  /**
   * Add a float32 column
   * @param name Column name
   * @param values Column values
   */
  addFloat32Column(name: string, values: Float32Array): void;

  /**
   * Add a boolean column
   * @param name Column name
   * @param values Column values
   */
  addBoolColumn(name: string, values: boolean[]): void;

  /**
   * Add a string column
   * @param name Column name
   * @param values Column values
   */
  addStringColumn(name: string, values: string[]): void;

  /**
   * Finalize and create the Lance file
   * @returns Complete Lance file data
   */
  finalize(): Uint8Array;

  /**
   * Get the number of columns
   */
  getNumColumns(): number;

  /**
   * Get the row count
   */
  getRowCount(): number | null;

  /**
   * Get column names
   */
  getColumnNames(): string[];
}

/** PureLanceWriter class */
export const PureLanceWriter: {
  new(options?: PureLanceWriterOptions): PureLanceWriter;
};

// =============================================================================
// Local Database (OPFS-backed)
// =============================================================================

/**
 * Column definition for table creation
 */
export interface ColumnDefinition {
  name: string;
  type: 'int64' | 'int32' | 'float64' | 'float32' | 'string' | 'bool' | 'vector';
  primaryKey?: boolean;
  vectorDim?: number;
}

/**
 * Scan options for streaming reads
 */
export interface ScanOptions {
  /** Number of rows per batch (default: 10000) */
  batchSize?: number;
  /** Filter function */
  where?: (row: Record<string, any>) => boolean;
  /** Columns to include */
  columns?: string[];
}

/**
 * Select query options
 */
export interface SelectOptions {
  /** Columns to select (use ['*'] for all) */
  columns?: string[];
  /** Filter function */
  where?: (row: Record<string, any>) => boolean;
  /** Maximum rows to return */
  limit?: number;
  /** Rows to skip */
  offset?: number;
  /** Order by */
  orderBy?: { column: string; desc?: boolean };
}

/**
 * Local database backed by OPFS storage.
 * Supports full CRUD operations with SQL interface.
 *
 * @example
 * ```javascript
 * const db = new LocalDatabase('mydb');
 * await db.open();
 *
 * await db.createTable('users', [
 *   { name: 'id', type: 'int64', primaryKey: true },
 *   { name: 'name', type: 'string' },
 *   { name: 'score', type: 'float64' }
 * ]);
 *
 * await db.insert('users', [
 *   { id: 1, name: 'Alice', score: 95.5 },
 *   { id: 2, name: 'Bob', score: 87.3 }
 * ]);
 *
 * const users = await db.select('users', { where: r => r.score > 90 });
 * ```
 */
export class LocalDatabase {
  constructor(name: string, storage?: OPFSStorage);

  /** Database name */
  readonly name: string;

  /** Current version number */
  readonly version: number;

  /**
   * Open or create the database
   */
  open(): Promise<LocalDatabase>;

  /**
   * Create a new table
   * @param tableName Table name
   * @param columns Column definitions
   */
  createTable(tableName: string, columns: ColumnDefinition[]): Promise<{ success: boolean; table: string }>;

  /**
   * Drop a table
   * @param tableName Table name
   */
  dropTable(tableName: string): Promise<{ success: boolean; table: string }>;

  /**
   * Insert rows into a table
   * @param tableName Table name
   * @param rows Array of row objects
   */
  insert(tableName: string, rows: Record<string, any>[]): Promise<{ success: boolean; inserted: number }>;

  /**
   * Delete rows from a table
   * @param tableName Table name
   * @param predicate Filter function to select rows to delete
   */
  delete(tableName: string, predicate: (row: Record<string, any>) => boolean): Promise<{ success: boolean; deleted: number }>;

  /**
   * Update rows in a table
   * @param tableName Table name
   * @param updates Column updates
   * @param predicate Filter function to select rows to update
   */
  update(tableName: string, updates: Record<string, any>, predicate: (row: Record<string, any>) => boolean): Promise<{ success: boolean; updated: number }>;

  /**
   * Select rows from a table
   * @param tableName Table name
   * @param options Query options
   */
  select(tableName: string, options?: SelectOptions): Promise<Record<string, any>[]>;

  /**
   * Streaming scan - yields batches of rows for memory-efficient processing
   * @param tableName Table name
   * @param options Scan options
   */
  scan(tableName: string, options?: ScanOptions): AsyncGenerator<Record<string, any>[], void, unknown>;

  /**
   * Count rows in a table
   * @param tableName Table name
   * @param where Optional filter function
   */
  count(tableName: string, where?: (row: Record<string, any>) => boolean): Promise<number>;

  /**
   * Get table schema
   * @param tableName Table name
   */
  getSchema(tableName: string): ColumnDefinition[];

  /**
   * Get table info
   * @param tableName Table name
   */
  getTable(tableName: string): { name: string; schema: ColumnDefinition[]; rowCount: number; fragments: string[] } | undefined;

  /**
   * List all tables
   */
  listTables(): string[];

  /**
   * Execute SQL statement
   * @param sql SQL statement
   */
  exec(sql: string): Promise<any>;

  /**
   * Compact the database (merge fragments, remove deleted rows)
   */
  compact(): Promise<{ success: boolean; compacted: number }>;

  /**
   * Close the database
   */
  close(): Promise<void>;
}

// =============================================================================
// Unified LanceData API
// =============================================================================

/**
 * Data source type
 */
export type LanceDataType = 'local' | 'remote' | 'cached';

/**
 * Base interface for unified Lance data access.
 * Provides common interface for both local (OPFS) and remote (HTTP) Lance files.
 */
export interface LanceDataBase {
  /** Data source type */
  readonly type: LanceDataType;

  /**
   * Get schema information
   */
  getSchema(): Promise<Array<{ name: string; type: string }>>;

  /**
   * Get total row count
   */
  getRowCount(): Promise<number>;

  /**
   * Read column data
   * @param colIdx Column index
   * @param start Start row (default: 0)
   * @param count Number of rows (default: all)
   */
  readColumn(colIdx: number, start?: number, count?: number): Promise<any>;

  /**
   * Streaming scan - yields batches of rows
   * @param options Scan options
   */
  scan(options?: ScanOptions): AsyncGenerator<Record<string, any>[], void, unknown>;

  /**
   * Insert rows (local sources only)
   * @param rows Rows to insert
   */
  insert?(rows: Record<string, any>[]): Promise<any>;

  /**
   * Check if data is cached locally
   */
  isCached(): boolean;

  /**
   * Prefetch data to local cache
   */
  prefetch(): Promise<void>;

  /**
   * Evict data from local cache
   */
  evict(): Promise<void>;

  /**
   * Close the data source
   */
  close(): Promise<void>;
}

/**
 * OPFS-backed Lance data for local files.
 * Uses ChunkedLanceReader for efficient memory usage.
 */
export class OPFSLanceData implements LanceDataBase {
  constructor(path: string, storage?: OPFSStorage);

  readonly type: LanceDataType;
  readonly path: string;

  /**
   * Open OPFS Lance file or database
   */
  open(): Promise<OPFSLanceData>;

  getSchema(): Promise<Array<{ name: string; type: string }>>;
  getRowCount(): Promise<number>;
  readColumn(colIdx: number, start?: number, count?: number): Promise<any>;
  scan(options?: ScanOptions): AsyncGenerator<Record<string, any>[], void, unknown>;
  insert(rows: Record<string, any>[]): Promise<any>;
  isCached(): boolean;
  prefetch(): Promise<void>;
  evict(): Promise<void>;
  close(): Promise<void>;
}

/**
 * HTTP-backed Lance data for remote files.
 * Uses HotTierCache for OPFS caching.
 */
export class RemoteLanceData implements LanceDataBase {
  constructor(url: string);

  readonly type: LanceDataType;
  readonly url: string;

  /**
   * Open remote Lance file
   */
  open(): Promise<RemoteLanceData>;

  getSchema(): Promise<Array<{ name: string; type: string }>>;
  getRowCount(): Promise<number>;
  readColumn(colIdx: number, start?: number, count?: number): Promise<any>;
  scan(options?: ScanOptions): AsyncGenerator<Record<string, any>[], void, unknown>;
  isCached(): boolean;
  prefetch(): Promise<void>;
  evict(): Promise<void>;
  close(): Promise<void>;
}

/**
 * Factory function to open Lance data from any source.
 * Supports:
 * - opfs://path - Local OPFS file or database
 * - https://url - Remote HTTP file (with optional caching)
 *
 * @param source Data source URI
 *
 * @example
 * ```javascript
 * // Local OPFS database
 * const local = await openLance('opfs://mydb');
 * for await (const batch of local.scan()) {
 *   processBatch(batch);
 * }
 *
 * // Remote file with caching
 * const remote = await openLance('https://example.com/data.lance');
 * await remote.prefetch(); // Cache to OPFS
 * const data = await remote.readColumn(0);
 * ```
 */
export function openLance(source: string): Promise<LanceDataBase>;

// =============================================================================
// Memory Management
// =============================================================================

/**
 * Memory usage information
 */
export interface MemoryUsage {
  usedHeapMB: number;
  totalHeapMB: number;
  limitMB: number;
}

/**
 * Memory manager options
 */
export interface MemoryManagerOptions {
  /** Target max heap usage in MB (default: 100) */
  maxHeapMB?: number;
  /** Warning threshold ratio (default: 0.8) */
  warningThreshold?: number;
}

/**
 * Global memory manager for browser environment.
 * Monitors memory usage and triggers cleanup when needed.
 */
export interface MemoryManager {
  /**
   * Register a cache for memory management
   */
  registerCache(cache: LRUCache): void;

  /**
   * Unregister a cache
   */
  unregisterCache(cache: LRUCache): void;

  /**
   * Get current memory usage (Chrome/Chromium only)
   */
  getMemoryUsage(): MemoryUsage | null;

  /**
   * Check memory and trigger cleanup if needed
   */
  checkAndCleanup(): boolean;

  /**
   * Force cleanup of all registered caches
   */
  cleanup(): void;

  /**
   * Get aggregate cache stats
   */
  getCacheStats(): {
    caches: number;
    totalEntries: number;
    totalSizeMB: string;
    totalMaxSizeMB: string;
    memory: MemoryUsage | null;
  };
}

/** MemoryManager class */
export const MemoryManager: {
  new(options?: MemoryManagerOptions): MemoryManager;
};

/** Global memory manager instance */
export const memoryManager: MemoryManager;

/**
 * Streaming utilities for large file processing
 */
export const StreamUtils: {
  /**
   * Process items in batches with memory-aware pacing
   */
  processBatches<T, R>(
    source: AsyncIterable<T>,
    processor: (batch: T) => Promise<R>,
    options?: { batchSize?: number; pauseAfter?: number }
  ): AsyncGenerator<R, void, unknown>;

  /**
   * Create a progress-reporting wrapper for async iterables
   */
  withProgress<T>(
    source: AsyncIterable<T>,
    onProgress: (processed: number) => void
  ): AsyncGenerator<T, void, unknown>;

  /**
   * Limit memory usage by processing in chunks with explicit cleanup
   */
  throttle<T>(
    source: AsyncIterable<T>,
    maxChunksInFlight?: number
  ): AsyncGenerator<T, void, unknown>;
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
