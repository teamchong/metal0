/**
 * LanceQL - Zig/WASM implementation of the Lance columnar file format reader
 */

export interface SchemaField {
  name: string;
  id: number;
  type: string;
}

export interface VectorInfo {
  dimension: number;
  rows: number;
  offset: number;
  size: number;
}

export interface VectorSearchResult {
  indices: number[];
  scores: number[];
  usedIndex?: boolean;
}

export interface VectorSearchOptions {
  nprobe?: number;
  useIndex?: boolean;
}

export interface SQLQueryResult {
  columns: string[];
  rows: any[][];
  total: number;
  rowIndices?: number[];
  startRowIdx?: number;
}

export interface IVFIndexData {
  centroids: Float32Array | null;
  numPartitions: number;
  dimension: number;
  partitionOffsets: number[];
  partitionLengths: number[];
  metricType: string;
}

/**
 * Main LanceQL class for loading and initializing the WASM module
 */
export default class LanceQL {
  wasm: WebAssembly.Exports;
  memory: WebAssembly.Memory;

  constructor(wasm: WebAssembly.Exports, memory: WebAssembly.Memory);

  /**
   * Initialize LanceQL from a WASM file URL
   */
  static init(wasmUrl?: string): Promise<LanceQL>;

  /**
   * Get the library version
   */
  getVersion(): string;

  /**
   * Open a local Lance file from an ArrayBuffer
   */
  openFile(data: ArrayBuffer): LanceFile;

  /**
   * Open a remote Lance file via HTTP Range requests
   */
  openRemoteFile(url: string): Promise<RemoteLanceFile>;
}

/**
 * Local Lance file reader
 */
export class LanceFile {
  numColumns: number;
  majorVersion: number;
  minorVersion: number;

  /**
   * Get the number of rows in a column
   */
  getRowCount(colIdx: number): bigint;

  /**
   * Read int64 values at specific indices
   */
  readInt64AtIndices(colIdx: number, indices: Uint32Array): BigInt64Array;

  /**
   * Read float64 values at specific indices
   */
  readFloat64AtIndices(colIdx: number, indices: Uint32Array): Float64Array;

  /**
   * Read int32 values at specific indices
   */
  readInt32AtIndices(colIdx: number, indices: Uint32Array): Int32Array;

  /**
   * Read float32 values at specific indices
   */
  readFloat32AtIndices(colIdx: number, indices: Uint32Array): Float32Array;

  /**
   * Read a string at a specific row index
   */
  readStringAt(colIdx: number, rowIdx: number): string;

  /**
   * Get vector info for a column
   */
  getVectorInfo(colIdx: number): VectorInfo;

  /**
   * Read a vector at a specific row index
   */
  readVectorAt(colIdx: number, rowIdx: number): Float32Array;

  /**
   * Free resources
   */
  close(): void;
}

/**
 * Remote Lance file reader with HTTP Range request support
 */
export class RemoteLanceFile {
  url: string;
  fileSize: number;
  numColumns: number;
  columnNames: string[];
  schema: SchemaField[] | null;
  datasetBaseUrl: string | null;

  /**
   * Open a remote Lance file
   */
  static open(lanceql: LanceQL, url: string): Promise<RemoteLanceFile>;

  /**
   * Detect column types from schema
   */
  detectColumnTypes(): Promise<string[]>;

  /**
   * Get the row count for a column
   */
  getRowCount(colIdx: number): Promise<number>;

  /**
   * Read int64 values at specific indices
   */
  readInt64AtIndices(colIdx: number, indices: number[]): Promise<BigInt64Array>;

  /**
   * Read float64 values at specific indices
   */
  readFloat64AtIndices(colIdx: number, indices: number[]): Promise<Float64Array>;

  /**
   * Read int32 values at specific indices
   */
  readInt32AtIndices(colIdx: number, indices: number[]): Promise<Int32Array>;

  /**
   * Read float32 values at specific indices
   */
  readFloat32AtIndices(colIdx: number, indices: number[]): Promise<Float32Array>;

  /**
   * Read strings at specific indices
   */
  readStringsAtIndices(colIdx: number, indices: number[]): Promise<string[]>;

  /**
   * Read vectors at specific indices
   */
  readVectorsAtIndices(colIdx: number, indices: number[]): Promise<Float32Array[]>;

  /**
   * Get vector info for a column
   */
  getVectorInfo(colIdx: number): Promise<VectorInfo>;

  /**
   * Check if ANN index is available
   */
  hasIndex(): boolean;

  /**
   * Perform vector similarity search
   */
  vectorSearch(
    colIdx: number,
    queryVec: Float32Array,
    topK?: number,
    onProgress?: (current: number, total: number) => void,
    options?: VectorSearchOptions
  ): Promise<VectorSearchResult>;

  /**
   * Compute cosine similarity between two vectors
   */
  cosineSimilarity(vecA: Float32Array, vecB: Float32Array): number;

  /**
   * Fetch bytes from a specific range
   */
  fetchRange(start: number, end: number): Promise<ArrayBuffer>;
}

/**
 * IVF (Inverted File Index) for Approximate Nearest Neighbor search
 */
export class IVFIndex {
  centroids: Float32Array | null;
  numPartitions: number;
  dimension: number;
  partitionOffsets: number[];
  partitionLengths: number[];
  metricType: string;

  /**
   * Try to load IVF index from a Lance dataset
   */
  static tryLoad(datasetBaseUrl: string): Promise<IVFIndex | null>;

  /**
   * Find the nearest partitions to a query vector
   */
  findNearestPartitions(queryVec: Float32Array, nprobe?: number): number[];
}

/**
 * SQL Query Executor
 */
export class SQLExecutor {
  constructor(file: RemoteLanceFile);

  /**
   * Execute a SQL query
   */
  execute(
    sql: string,
    onProgress?: (message: string, current: number, total: number) => void
  ): Promise<SQLQueryResult>;
}

/**
 * Parse a SQL string and return the AST
 */
export function parseSQL(sql: string): object;
