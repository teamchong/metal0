/**
 * @lanceql/node - SQLite-compatible API for Lance columnar files
 *
 * Drop-in replacement for better-sqlite3 for read-only analytics workloads.
 */

declare module '@lanceql/node' {
  /**
   * Options for opening a database.
   */
  export interface DatabaseOptions {
    /**
     * Always true for Lance files (read-only).
     */
    readonly?: boolean;

    /**
     * Timeout in milliseconds for acquiring a lock.
     * Not applicable to Lance files.
     */
    timeout?: number;
  }

  /**
   * Result of a run() operation.
   */
  export interface RunResult {
    /**
     * Number of rows changed (always 0 for Lance files).
     */
    changes: number;

    /**
     * Last inserted row ID (always 0 for Lance files).
     */
    lastInsertRowid: number | bigint;
  }

  /**
   * Column information from PRAGMA table_info.
   */
  export interface ColumnInfo {
    cid: number;
    name: string;
    type: string;
    notnull: number;
    dflt_value: any;
    pk: number;
  }

  /**
   * A prepared SQL statement.
   */
  export class Statement<BindParameters extends unknown[] = unknown[]> {
    /**
     * The source SQL string.
     */
    readonly source: string;

    /**
     * True if the statement is read-only.
     */
    readonly reader: boolean;

    /**
     * Execute the statement and return all result rows.
     * @param params - Bound parameters for the statement
     * @returns Array of result row objects
     */
    all(...params: BindParameters): Record<string, any>[];

    /**
     * Execute the statement and return the first result row.
     * @param params - Bound parameters for the statement
     * @returns First row object, or undefined if no results
     */
    get(...params: BindParameters): Record<string, any> | undefined;

    /**
     * Execute the statement for its side effects.
     * @param params - Bound parameters for the statement
     * @returns Run result with changes count
     */
    run(...params: BindParameters): RunResult;

    /**
     * Bind parameters to the statement.
     * @param params - Parameters to bind
     * @returns The statement for chaining
     */
    bind(...params: BindParameters): this;

    /**
     * Iterate over all result rows.
     * @param params - Bound parameters for the statement
     */
    iterate(...params: BindParameters): IterableIterator<Record<string, any>>;

    /**
     * Get column names from the result.
     */
    columns(): Array<{ name: string; type: string | null }>;

    /**
     * Expand bound parameters into literal values.
     * @param params - Parameters to expand
     * @returns Expanded SQL string
     */
    expand(...params: BindParameters): string;
  }

  /**
   * A SQLite-compatible database connection to a Lance file.
   */
  export class Database {
    /**
     * Open a Lance file or dataset directory.
     * @param path - Path to .lance file or Lance dataset directory
     * @param options - Database options
     */
    constructor(path: string | Buffer, options?: DatabaseOptions);

    /**
     * True if the database connection is open.
     */
    readonly open: boolean;

    /**
     * True if the database is in a transaction (always false for Lance).
     */
    readonly inTransaction: boolean;

    /**
     * The path to the database file.
     */
    readonly name: string;

    /**
     * True if the database is read-only (always true for Lance).
     */
    readonly readonly: boolean;

    /**
     * Memory usage statistics (not supported - returns empty object).
     */
    readonly memory: boolean;

    /**
     * Create a prepared statement.
     * @param sql - SQL query string
     * @returns Prepared statement
     */
    prepare<T extends unknown[] = unknown[]>(sql: string): Statement<T>;

    /**
     * Execute one or more SQL statements.
     * @param sql - SQL to execute
     * @returns The database for chaining
     */
    exec(sql: string): this;

    /**
     * Get PRAGMA information (limited support).
     */
    pragma(sql: string, options?: { simple?: boolean }): any;

    /**
     * Close the database connection.
     * @returns The database for chaining
     */
    close(): this;

    /**
     * Register a user-defined function (not supported).
     * @throws SqliteError
     */
    function(name: string, fn: (...args: any[]) => any): this;
    function(name: string, options: object, fn: (...args: any[]) => any): this;

    /**
     * Register an aggregate function (not supported).
     * @throws SqliteError
     */
    aggregate(name: string, options: object): this;

    /**
     * Create a virtual table (not supported).
     * @throws SqliteError
     */
    table(name: string, definition: object): this;

    /**
     * Load an extension (not supported).
     * @throws SqliteError
     */
    loadExtension(path: string): this;

    /**
     * Create a database backup (not supported).
     * @throws SqliteError
     */
    backup(destination: string | Database, options?: object): Promise<void>;

    /**
     * Serialize the database (not supported).
     * @throws SqliteError
     */
    serialize(options?: object): Buffer;

    /**
     * Begin a transaction (no-op for read-only Lance).
     */
    transaction<T>(fn: () => T): () => T;

    /**
     * Execute a function with SAVEPOINT (not supported).
     * @throws SqliteError
     */
    unsafeMode(enabled?: boolean): this;
  }

  /**
   * SQLite-compatible error class.
   */
  export class SqliteError extends Error {
    /**
     * SQLite error code (e.g., 'SQLITE_ERROR').
     */
    code: string;

    /**
     * Create a new SqliteError.
     * @param message - Error message
     * @param code - SQLite error code
     */
    constructor(message: string, code: string);
  }

  export default Database;
}
