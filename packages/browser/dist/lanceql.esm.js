/**
 * LanceQL WASM Loader
 *
 * JavaScript wrapper for the LanceQL WebAssembly module.
 * Provides a high-level API for reading Lance files in the browser.
 * Supports both local files and remote URLs via HTTP Range requests.
 */

/**
 * IndexedDB cache for dataset metadata.
 * Caches schema, column types, and fragment info to speed up repeat visits.
 */
class MetadataCache {
    constructor(dbName = 'lanceql-cache', version = 1) {
        this.dbName = dbName;
        this.version = version;
        this.db = null;
    }

    async open() {
        if (this.db) return this.db;

        return new Promise((resolve, reject) => {
            const request = indexedDB.open(this.dbName, this.version);

            request.onerror = () => reject(request.error);
            request.onsuccess = () => {
                this.db = request.result;
                resolve(this.db);
            };

            request.onupgradeneeded = (event) => {
                const db = event.target.result;
                if (!db.objectStoreNames.contains('datasets')) {
                    const store = db.createObjectStore('datasets', { keyPath: 'url' });
                    store.createIndex('timestamp', 'timestamp');
                }
            };
        });
    }

    /**
     * Get cached metadata for a dataset URL.
     * @param {string} url - Dataset URL
     * @returns {Promise<Object|null>} Cached metadata or null
     */
    async get(url) {
        try {
            const db = await this.open();
            return new Promise((resolve) => {
                const tx = db.transaction('datasets', 'readonly');
                const store = tx.objectStore('datasets');
                const request = store.get(url);
                request.onsuccess = () => resolve(request.result || null);
                request.onerror = () => resolve(null);
            });
        } catch (e) {
            console.warn('[MetadataCache] Get failed:', e);
            return null;
        }
    }

    /**
     * Cache metadata for a dataset URL.
     * @param {string} url - Dataset URL
     * @param {Object} metadata - Metadata to cache (schema, columnTypes, fragments, etc.)
     */
    async set(url, metadata) {
        try {
            const db = await this.open();
            return new Promise((resolve, reject) => {
                const tx = db.transaction('datasets', 'readwrite');
                const store = tx.objectStore('datasets');
                const data = {
                    url,
                    timestamp: Date.now(),
                    ...metadata
                };
                const request = store.put(data);
                request.onsuccess = () => resolve();
                request.onerror = () => reject(request.error);
            });
        } catch (e) {
            console.warn('[MetadataCache] Set failed:', e);
        }
    }

    /**
     * Delete cached metadata for a URL.
     * @param {string} url - Dataset URL
     */
    async delete(url) {
        try {
            const db = await this.open();
            return new Promise((resolve) => {
                const tx = db.transaction('datasets', 'readwrite');
                const store = tx.objectStore('datasets');
                store.delete(url);
                tx.oncomplete = () => resolve();
            });
        } catch (e) {
            console.warn('[MetadataCache] Delete failed:', e);
        }
    }

    /**
     * Clear all cached metadata.
     */
    async clear() {
        try {
            const db = await this.open();
            return new Promise((resolve) => {
                const tx = db.transaction('datasets', 'readwrite');
                const store = tx.objectStore('datasets');
                store.clear();
                tx.oncomplete = () => resolve();
            });
        } catch (e) {
            console.warn('[MetadataCache] Clear failed:', e);
        }
    }
}

// Global cache instance
const metadataCache = new MetadataCache();

/**
 * OPFS-only storage for Lance database files.
 *
 * Uses Origin Private File System (OPFS) exclusively - no IndexedDB.
 * This avoids migration complexity as data grows.
 *
 * OPFS benefits:
 * - High performance file access
 * - No size limits (beyond disk quota)
 * - File-like API suitable for Lance format
 * - Same approach as SQLite WASM
 */
class OPFSStorage {
    constructor(rootDir = 'lanceql') {
        this.rootDir = rootDir;
        this.root = null;
    }

    /**
     * Get OPFS root directory, creating if needed
     */
    async getRoot() {
        if (this.root) return this.root;

        if (typeof navigator === 'undefined' || !navigator.storage?.getDirectory) {
            throw new Error('OPFS not available. Requires modern browser with Origin Private File System support.');
        }

        const opfsRoot = await navigator.storage.getDirectory();
        this.root = await opfsRoot.getDirectoryHandle(this.rootDir, { create: true });
        return this.root;
    }

    async open() {
        await this.getRoot();
        return this;
    }

    /**
     * Get or create a subdirectory
     */
    async getDir(path) {
        const root = await this.getRoot();
        const parts = path.split('/').filter(p => p);

        let current = root;
        for (const part of parts) {
            current = await current.getDirectoryHandle(part, { create: true });
        }
        return current;
    }

    /**
     * Save data to a file
     * @param {string} path - File path (e.g., 'mydb/users/frag_001.lance')
     * @param {Uint8Array} data - File data
     */
    async save(path, data) {
        const parts = path.split('/');
        const fileName = parts.pop();
        const dirPath = parts.join('/');

        const dir = dirPath ? await this.getDir(dirPath) : await this.getRoot();
        const fileHandle = await dir.getFileHandle(fileName, { create: true });

        // Use sync access handle for better performance if available
        if (fileHandle.createSyncAccessHandle) {
            try {
                const accessHandle = await fileHandle.createSyncAccessHandle();
                accessHandle.truncate(0);
                accessHandle.write(data, { at: 0 });
                accessHandle.flush();
                accessHandle.close();
                return { path, size: data.byteLength };
            } catch (e) {
                // Fall back to writable stream
            }
        }

        const writable = await fileHandle.createWritable();
        await writable.write(data);
        await writable.close();

        return { path, size: data.byteLength };
    }

    /**
     * Load data from a file
     * @param {string} path - File path
     * @returns {Promise<Uint8Array|null>}
     */
    async load(path) {
        try {
            const parts = path.split('/');
            const fileName = parts.pop();
            const dirPath = parts.join('/');

            const dir = dirPath ? await this.getDir(dirPath) : await this.getRoot();
            const fileHandle = await dir.getFileHandle(fileName);
            const file = await fileHandle.getFile();
            const buffer = await file.arrayBuffer();
            return new Uint8Array(buffer);
        } catch (e) {
            if (e.name === 'NotFoundError') {
                return null;
            }
            throw e;
        }
    }

    /**
     * Delete a file
     * @param {string} path - File path
     */
    async delete(path) {
        try {
            const parts = path.split('/');
            const fileName = parts.pop();
            const dirPath = parts.join('/');

            const dir = dirPath ? await this.getDir(dirPath) : await this.getRoot();
            await dir.removeEntry(fileName);
            return true;
        } catch (e) {
            if (e.name === 'NotFoundError') {
                return false;
            }
            throw e;
        }
    }

    /**
     * List files in a directory
     * @param {string} dirPath - Directory path
     * @returns {Promise<string[]>} File names
     */
    async list(dirPath = '') {
        try {
            const dir = dirPath ? await this.getDir(dirPath) : await this.getRoot();
            const files = [];
            for await (const [name, handle] of dir.entries()) {
                files.push({
                    name,
                    type: handle.kind, // 'file' or 'directory'
                });
            }
            return files;
        } catch (e) {
            return [];
        }
    }

    /**
     * Check if a file exists
     * @param {string} path - File path
     */
    async exists(path) {
        try {
            const parts = path.split('/');
            const fileName = parts.pop();
            const dirPath = parts.join('/');

            const dir = dirPath ? await this.getDir(dirPath) : await this.getRoot();
            await dir.getFileHandle(fileName);
            return true;
        } catch (e) {
            return false;
        }
    }

    /**
     * Delete a directory and all contents
     * @param {string} dirPath - Directory path
     */
    async deleteDir(dirPath) {
        try {
            const parts = dirPath.split('/');
            const dirName = parts.pop();
            const parentPath = parts.join('/');

            const parent = parentPath ? await this.getDir(parentPath) : await this.getRoot();
            await parent.removeEntry(dirName, { recursive: true });
            return true;
        } catch (e) {
            return false;
        }
    }
}

// Legacy IndexedDB + OPFS storage (deprecated, use OPFSStorage instead)
class DatasetStorage {
    constructor(dbName = 'lanceql-files', version = 1) {
        this.dbName = dbName;
        this.version = version;
        this.db = null;
        this.SIZE_THRESHOLD = 50 * 1024 * 1024; // 50MB
    }

    async open() {
        if (this.db) return this.db;

        return new Promise((resolve, reject) => {
            const request = indexedDB.open(this.dbName, this.version);

            request.onerror = () => reject(request.error);
            request.onsuccess = () => {
                this.db = request.result;
                resolve(this.db);
            };

            request.onupgradeneeded = (event) => {
                const db = event.target.result;
                if (!db.objectStoreNames.contains('files')) {
                    db.createObjectStore('files', { keyPath: 'name' });
                }
                if (!db.objectStoreNames.contains('index')) {
                    const store = db.createObjectStore('index', { keyPath: 'name' });
                    store.createIndex('timestamp', 'timestamp');
                    store.createIndex('size', 'size');
                }
            };
        });
    }

    async hasOPFS() {
        try {
            return 'storage' in navigator && 'getDirectory' in navigator.storage;
        } catch {
            return false;
        }
    }

    async save(name, data, metadata = {}) {
        const db = await this.open();
        const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : data;
        const size = bytes.byteLength;
        const useOPFS = size >= this.SIZE_THRESHOLD && await this.hasOPFS();

        if (useOPFS) {
            try {
                const root = await navigator.storage.getDirectory();
                const fileHandle = await root.getFileHandle(name, { create: true });
                const writable = await fileHandle.createWritable();
                await writable.write(bytes);
                await writable.close();
            } catch (e) {
                console.warn('[DatasetStorage] OPFS save failed, falling back to IndexedDB:', e);
            }
        }

        if (!useOPFS) {
            await new Promise((resolve, reject) => {
                const tx = db.transaction('files', 'readwrite');
                const store = tx.objectStore('files');
                store.put({ name, data: bytes });
                tx.oncomplete = () => resolve();
                tx.onerror = () => reject(tx.error);
            });
        }

        await new Promise((resolve, reject) => {
            const tx = db.transaction('index', 'readwrite');
            const store = tx.objectStore('index');
            store.put({
                name,
                size,
                timestamp: Date.now(),
                storage: useOPFS ? 'opfs' : 'indexeddb',
                ...metadata
            });
            tx.oncomplete = () => resolve();
            tx.onerror = () => reject(tx.error);
        });

        return { name, size, storage: useOPFS ? 'opfs' : 'indexeddb' };
    }

    async load(name) {
        const db = await this.open();

        const entry = await new Promise((resolve) => {
            const tx = db.transaction('index', 'readonly');
            const store = tx.objectStore('index');
            const request = store.get(name);
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => resolve(null);
        });

        if (!entry) return null;

        if (entry.storage === 'opfs') {
            try {
                const root = await navigator.storage.getDirectory();
                const fileHandle = await root.getFileHandle(name);
                const file = await fileHandle.getFile();
                const buffer = await file.arrayBuffer();
                return new Uint8Array(buffer);
            } catch (e) {
                console.warn('[DatasetStorage] OPFS load failed:', e);
                return null;
            }
        }

        return new Promise((resolve) => {
            const tx = db.transaction('files', 'readonly');
            const store = tx.objectStore('files');
            const request = store.get(name);
            request.onsuccess = () => {
                const result = request.result;
                resolve(result ? result.data : null);
            };
            request.onerror = () => resolve(null);
        });
    }

    async list() {
        const db = await this.open();

        return new Promise((resolve) => {
            const tx = db.transaction('index', 'readonly');
            const store = tx.objectStore('index');
            const request = store.getAll();
            request.onsuccess = () => resolve(request.result || []);
            request.onerror = () => resolve([]);
        });
    }

    async delete(name) {
        const db = await this.open();

        const entry = await new Promise((resolve) => {
            const tx = db.transaction('index', 'readonly');
            const store = tx.objectStore('index');
            const request = store.get(name);
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => resolve(null);
        });

        if (entry?.storage === 'opfs') {
            try {
                const root = await navigator.storage.getDirectory();
                await root.removeEntry(name);
            } catch (e) {
                console.warn('[DatasetStorage] OPFS delete failed:', e);
            }
        }

        await new Promise((resolve) => {
            const tx = db.transaction('files', 'readwrite');
            const store = tx.objectStore('files');
            store.delete(name);
            tx.oncomplete = () => resolve();
        });

        // Delete from index
        await new Promise((resolve) => {
            const tx = db.transaction('index', 'readwrite');
            const store = tx.objectStore('index');
            store.delete(name);
            tx.oncomplete = () => resolve();
        });
    }

    /**
     * Check if a dataset exists.
     * @param {string} name - Dataset name
     * @returns {Promise<boolean>}
     */
    async exists(name) {
        const db = await this.open();

        return new Promise((resolve) => {
            const tx = db.transaction('index', 'readonly');
            const store = tx.objectStore('index');
            const request = store.get(name);
            request.onsuccess = () => resolve(!!request.result);
            request.onerror = () => resolve(false);
        });
    }

    /**
     * Get storage usage info.
     * @returns {Promise<Object>} Usage stats
     */
    async getUsage() {
        const datasets = await this.list();
        const totalSize = datasets.reduce((sum, d) => sum + (d.size || 0), 0);
        const indexedDBCount = datasets.filter(d => d.storage === 'indexeddb').length;
        const opfsCount = datasets.filter(d => d.storage === 'opfs').length;

        let quota = null;
        if (navigator.storage?.estimate) {
            quota = await navigator.storage.estimate();
        }

        return {
            datasets: datasets.length,
            totalSize,
            indexedDBCount,
            opfsCount,
            quota
        };
    }
}

// Global storage instances
const opfsStorage = new OPFSStorage();  // OPFS-only (recommended)
const datasetStorage = new DatasetStorage();  // Legacy IndexedDB + OPFS

// Export storage for external use
export { opfsStorage, OPFSStorage, datasetStorage, DatasetStorage };

// =============================================================================
// LocalDatabase - ACID-compliant local database with CRUD support
// =============================================================================

/**
 * Data types for schema definition
 */
const DataType = {
    INT: 'int64',
    INTEGER: 'int64',
    BIGINT: 'int64',
    FLOAT: 'float32',
    DOUBLE: 'float64',
    TEXT: 'string',
    VARCHAR: 'string',
    BOOLEAN: 'bool',
    BOOL: 'bool',
    VECTOR: 'vector',
};

/**
 * LocalDatabase - ACID-compliant database stored in IndexedDB/OPFS
 *
 * Uses manifest-based versioning for ACID:
 * - Atomicity: Manifest update is atomic
 * - Consistency: Always read from valid manifest
 * - Isolation: Each transaction sees snapshot
 * - Durability: Persisted to OPFS (Origin Private File System)
 *
 * Storage: Uses OPFS exclusively for all data sizes. No IndexedDB migration needed.
 */
export class LocalDatabase {
    constructor(name, storage = opfsStorage) {
        this.name = name;
        this.storage = storage;
        this.tables = new Map();  // tableName -> TableState
        this.version = 0;
        this.manifestKey = `${name}/__manifest__`;
    }

    /**
     * Open or create the database
     */
    async open() {
        // Load manifest from storage
        const manifestData = await this.storage.load(this.manifestKey);
        if (manifestData) {
            const manifest = JSON.parse(new TextDecoder().decode(manifestData));
            this.version = manifest.version || 0;
            this.tables = new Map(Object.entries(manifest.tables || {}));
        }
        return this;
    }

    /**
     * Save manifest to storage (atomic commit point)
     */
    async _saveManifest() {
        this.version++;
        const manifest = {
            version: this.version,
            timestamp: Date.now(),
            tables: Object.fromEntries(this.tables),
        };
        const data = new TextEncoder().encode(JSON.stringify(manifest));
        await this.storage.save(this.manifestKey, data);
    }

    /**
     * CREATE TABLE
     * @param {string} tableName - Table name
     * @param {Array} columns - Column definitions [{name, type, primaryKey?, vectorDim?}]
     */
    async createTable(tableName, columns) {
        if (this.tables.has(tableName)) {
            throw new Error(`Table '${tableName}' already exists`);
        }

        const schema = columns.map(col => ({
            name: col.name,
            type: DataType[col.type?.toUpperCase()] || col.type || 'string',
            primaryKey: col.primaryKey || false,
            vectorDim: col.vectorDim || null,
        }));

        const tableState = {
            name: tableName,
            schema,
            fragments: [],      // List of data fragment keys
            deletionVector: [], // Row IDs that are deleted
            rowCount: 0,
            nextRowId: 0,
            createdAt: Date.now(),
        };

        this.tables.set(tableName, tableState);
        await this._saveManifest();

        return { success: true, table: tableName };
    }

    /**
     * DROP TABLE
     * @param {string} tableName - Table name
     */
    async dropTable(tableName) {
        if (!this.tables.has(tableName)) {
            throw new Error(`Table '${tableName}' does not exist`);
        }

        const table = this.tables.get(tableName);

        // Delete all fragments
        for (const fragKey of table.fragments) {
            await this.storage.delete(fragKey);
        }

        this.tables.delete(tableName);
        await this._saveManifest();

        return { success: true, table: tableName };
    }

    /**
     * INSERT INTO
     * @param {string} tableName - Table name
     * @param {Array} rows - Array of row objects [{col1: val1, col2: val2}, ...]
     */
    async insert(tableName, rows) {
        if (!this.tables.has(tableName)) {
            throw new Error(`Table '${tableName}' does not exist`);
        }

        const table = this.tables.get(tableName);

        // Assign row IDs
        const rowsWithIds = rows.map(row => ({
            __rowId: table.nextRowId++,
            ...row,
        }));

        // Create new fragment
        const fragKey = `${this.name}/${tableName}/frag_${Date.now()}_${Math.random().toString(36).slice(2)}`;
        const fragData = new TextEncoder().encode(JSON.stringify(rowsWithIds));
        await this.storage.save(fragKey, fragData);

        // Update table state
        table.fragments.push(fragKey);
        table.rowCount += rows.length;

        await this._saveManifest();

        return { success: true, inserted: rows.length };
    }

    /**
     * DELETE FROM
     * @param {string} tableName - Table name
     * @param {Function} predicate - Filter function (row) => boolean
     */
    async delete(tableName, predicate) {
        if (!this.tables.has(tableName)) {
            throw new Error(`Table '${tableName}' does not exist`);
        }

        const table = this.tables.get(tableName);
        const allRows = await this._readAllRows(tableName);

        let deletedCount = 0;
        for (const row of allRows) {
            if (predicate(row)) {
                table.deletionVector.push(row.__rowId);
                deletedCount++;
                table.rowCount--;
            }
        }

        await this._saveManifest();

        return { success: true, deleted: deletedCount };
    }

    /**
     * UPDATE
     * @param {string} tableName - Table name
     * @param {Object} updates - Column updates {col1: newVal, col2: newVal}
     * @param {Function} predicate - Filter function (row) => boolean
     */
    async update(tableName, updates, predicate) {
        if (!this.tables.has(tableName)) {
            throw new Error(`Table '${tableName}' does not exist`);
        }

        const table = this.tables.get(tableName);
        const allRows = await this._readAllRows(tableName);

        const updatedRows = [];
        let updatedCount = 0;

        for (const row of allRows) {
            if (predicate(row)) {
                // Mark old row as deleted
                table.deletionVector.push(row.__rowId);
                table.rowCount--;

                // Create new row with updates
                const newRow = { ...row, ...updates };
                delete newRow.__rowId;
                updatedRows.push(newRow);
                updatedCount++;
            }
        }

        // Insert updated rows as new fragment
        if (updatedRows.length > 0) {
            await this.insert(tableName, updatedRows);
        } else {
            await this._saveManifest();
        }

        return { success: true, updated: updatedCount };
    }

    /**
     * SELECT (query)
     * @param {string} tableName - Table name
     * @param {Object} options - Query options {columns, where, limit, offset, orderBy}
     */
    async select(tableName, options = {}) {
        if (!this.tables.has(tableName)) {
            throw new Error(`Table '${tableName}' does not exist`);
        }

        let rows = await this._readAllRows(tableName);

        // WHERE filter
        if (options.where) {
            rows = rows.filter(options.where);
        }

        // ORDER BY
        if (options.orderBy) {
            const { column, desc } = options.orderBy;
            rows.sort((a, b) => {
                const cmp = a[column] < b[column] ? -1 : a[column] > b[column] ? 1 : 0;
                return desc ? -cmp : cmp;
            });
        }

        // OFFSET
        if (options.offset) {
            rows = rows.slice(options.offset);
        }

        // LIMIT
        if (options.limit) {
            rows = rows.slice(0, options.limit);
        }

        // Column projection
        if (options.columns && options.columns.length > 0 && options.columns[0] !== '*') {
            rows = rows.map(row => {
                const projected = {};
                for (const col of options.columns) {
                    projected[col] = row[col];
                }
                return projected;
            });
        }

        // Remove internal __rowId
        rows = rows.map(row => {
            const { __rowId, ...rest } = row;
            return rest;
        });

        return rows;
    }

    /**
     * Read all rows from a table (excluding deleted)
     */
    async _readAllRows(tableName) {
        const table = this.tables.get(tableName);
        const deletedSet = new Set(table.deletionVector);
        const allRows = [];

        for (const fragKey of table.fragments) {
            const fragData = await this.storage.load(fragKey);
            if (fragData) {
                const rows = JSON.parse(new TextDecoder().decode(fragData));
                for (const row of rows) {
                    if (!deletedSet.has(row.__rowId)) {
                        allRows.push(row);
                    }
                }
            }
        }

        return allRows;
    }

    /**
     * Get table info
     */
    getTable(tableName) {
        return this.tables.get(tableName);
    }

    /**
     * List all tables
     */
    listTables() {
        return Array.from(this.tables.keys());
    }

    /**
     * Execute SQL statement using standard SQLParser
     * @param {string} sql - SQL statement
     * @returns {Promise<any>} Result
     */
    async exec(sql) {
        const lexer = new SQLLexer(sql);
        const tokens = lexer.tokenize();
        const parser = new SQLParser(tokens);
        const ast = parser.parse();

        return this._executeAST(ast);
    }

    /**
     * Execute parsed AST
     */
    async _executeAST(ast) {
        const type = ast.type.toUpperCase();

        switch (type) {
            case 'CREATE_TABLE':
                return this.createTable(ast.table, ast.columns);

            case 'DROP_TABLE':
                return this.dropTable(ast.table);

            case 'INSERT': {
                // Convert from parser format to insert format
                const table = this.tables.get(ast.table);
                if (!table) {
                    throw new Error(`Table '${ast.table}' does not exist`);
                }

                // Map value rows to row objects
                const columnNames = ast.columns || table.schema.map(c => c.name);
                const rows = ast.rows.map(valueRow => {
                    const row = {};
                    valueRow.forEach((val, i) => {
                        row[columnNames[i]] = val.value;
                    });
                    return row;
                });

                return this.insert(ast.table, rows);
            }

            case 'DELETE': {
                const deletePredicate = ast.where
                    ? (row) => this._evalWhereExpr(ast.where, row)
                    : () => true;
                return this.delete(ast.table, deletePredicate);
            }

            case 'UPDATE': {
                // Convert assignments to updates object
                const updates = {};
                for (const assignment of ast.assignments) {
                    updates[assignment.column] = assignment.value.value;
                }

                const updatePredicate = ast.where
                    ? (row) => this._evalWhereExpr(ast.where, row)
                    : () => true;
                return this.update(ast.table, updates, updatePredicate);
            }

            case 'SELECT': {
                const tableName = ast.from?.name || ast.from?.table || ast.from;
                if (!tableName) {
                    throw new Error('SELECT requires FROM clause for LocalDatabase');
                }

                const selectOptions = {
                    columns: ast.columns === '*' ? ['*'] :
                        ast.columns.map(c => c.type === 'star' ? '*' : c.expr?.column || c.column || c),
                    where: ast.where ? (row) => this._evalWhereExpr(ast.where, row) : null,
                    limit: ast.limit,
                    offset: ast.offset,
                    orderBy: ast.orderBy?.[0] ? {
                        column: ast.orderBy[0].column,
                        desc: ast.orderBy[0].descending
                    } : null,
                };
                return this.select(tableName, selectOptions);
            }

            default:
                throw new Error(`Unknown statement type: ${ast.type}`);
        }
    }

    /**
     * Evaluate WHERE expression from standard SQLParser AST
     */
    _evalWhereExpr(expr, row) {
        if (!expr) return true;

        if (expr.type === 'binary') {
            const op = expr.op;

            // Handle AND/OR
            if (op === 'AND' || op === '&&') {
                return this._evalWhereExpr(expr.left, row) && this._evalWhereExpr(expr.right, row);
            }
            if (op === 'OR' || op === '||') {
                return this._evalWhereExpr(expr.left, row) || this._evalWhereExpr(expr.right, row);
            }

            // Get column value and literal value
            const leftVal = expr.left.type === 'column' ?
                row[expr.left.column] :
                expr.left.value;
            const rightVal = expr.right.type === 'column' ?
                row[expr.right.column] :
                expr.right.value;

            switch (op) {
                case '=':
                case '==':
                    return leftVal === rightVal;
                case '!=':
                case '<>':
                    return leftVal !== rightVal;
                case '<':
                    return leftVal < rightVal;
                case '<=':
                    return leftVal <= rightVal;
                case '>':
                    return leftVal > rightVal;
                case '>=':
                    return leftVal >= rightVal;
                case 'LIKE':
                    const pattern = String(rightVal).replace(/%/g, '.*').replace(/_/g, '.');
                    return new RegExp(`^${pattern}$`, 'i').test(leftVal);
                default:
                    return true;
            }
        }

        return true;
    }

    /**
     * Evaluate WHERE clause
     */
    _evalWhere(where, row) {
        if (!where) return true;

        switch (where.op) {
            case 'AND':
                return this._evalWhere(where.left, row) && this._evalWhere(where.right, row);
            case 'OR':
                return this._evalWhere(where.left, row) || this._evalWhere(where.right, row);
            case '=':
                return row[where.column] === where.value;
            case '!=':
            case '<>':
                return row[where.column] !== where.value;
            case '<':
                return row[where.column] < where.value;
            case '<=':
                return row[where.column] <= where.value;
            case '>':
                return row[where.column] > where.value;
            case '>=':
                return row[where.column] >= where.value;
            case 'LIKE':
                const pattern = where.value.replace(/%/g, '.*').replace(/_/g, '.');
                return new RegExp(`^${pattern}$`, 'i').test(row[where.column]);
            default:
                return true;
        }
    }

    /**
     * Compact the database (merge fragments, remove deleted rows)
     */
    async compact() {
        for (const [tableName, table] of this.tables) {
            const allRows = await this._readAllRows(tableName);

            // Delete old fragments
            for (const fragKey of table.fragments) {
                await this.storage.delete(fragKey);
            }

            // Reset table state
            table.fragments = [];
            table.deletionVector = [];
            table.rowCount = 0;
            table.nextRowId = 0;

            // Re-insert all rows as single fragment
            if (allRows.length > 0) {
                // Remove old __rowId
                const cleanRows = allRows.map(({ __rowId, ...rest }) => rest);
                await this.insert(tableName, cleanRows);
            }
        }

        return { success: true, compacted: this.tables.size };
    }

    /**
     * Close the database
     */
    async close() {
        await this._saveManifest();
    }
}

/**
 * SQL Parser for LocalDatabase (supports CREATE, INSERT, UPDATE, DELETE, SELECT)
 */
class LocalSQLParser {
    constructor(tokens) {
        this.tokens = tokens;
        this.pos = 0;
    }

    peek() {
        return this.tokens[this.pos] || { type: TokenType.EOF };
    }

    advance() {
        return this.tokens[this.pos++] || { type: TokenType.EOF };
    }

    match(type) {
        if (this.peek().type === type) {
            return this.advance();
        }
        return null;
    }

    expect(type) {
        const token = this.advance();
        if (token.type !== type) {
            throw new Error(`Expected ${type}, got ${token.type}`);
        }
        return token;
    }

    parse() {
        const token = this.peek();

        switch (token.type) {
            case TokenType.CREATE:
                return this.parseCreate();
            case TokenType.DROP:
                return this.parseDrop();
            case TokenType.INSERT:
                return this.parseInsert();
            case TokenType.UPDATE:
                return this.parseUpdate();
            case TokenType.DELETE:
                return this.parseDelete();
            case TokenType.SELECT:
                return this.parseSelect();
            default:
                throw new Error(`Unexpected token: ${token.type}`);
        }
    }

    parseCreate() {
        this.expect(TokenType.CREATE);
        this.expect(TokenType.TABLE);
        const tableName = this.expect(TokenType.IDENTIFIER).value;
        this.expect(TokenType.LPAREN);

        const columns = [];
        do {
            const colName = this.expect(TokenType.IDENTIFIER).value;
            const colType = this.parseDataType();
            const col = { name: colName, type: colType };

            // Check for PRIMARY KEY
            if (this.match(TokenType.PRIMARY)) {
                this.expect(TokenType.KEY);
                col.primaryKey = true;
            }

            columns.push(col);
        } while (this.match(TokenType.COMMA));

        this.expect(TokenType.RPAREN);

        return { type: 'create_table', table: tableName, columns };
    }

    parseDataType() {
        const token = this.advance();
        let type = token.value || token.type;

        // Handle VECTOR(dim)
        if (type === 'VECTOR' && this.match(TokenType.LPAREN)) {
            const dim = this.expect(TokenType.NUMBER).value;
            this.expect(TokenType.RPAREN);
            return { type: 'vector', dim: parseInt(dim) };
        }

        // Handle VARCHAR(len)
        if ((type === 'VARCHAR' || type === 'TEXT') && this.match(TokenType.LPAREN)) {
            this.expect(TokenType.NUMBER); // ignore length
            this.expect(TokenType.RPAREN);
        }

        return type;
    }

    parseDrop() {
        this.expect(TokenType.DROP);
        this.expect(TokenType.TABLE);
        const tableName = this.expect(TokenType.IDENTIFIER).value;
        return { type: 'drop_table', table: tableName };
    }

    parseInsert() {
        this.expect(TokenType.INSERT);
        this.expect(TokenType.INTO);
        const tableName = this.expect(TokenType.IDENTIFIER).value;

        // Optional column list
        let columns = null;
        if (this.match(TokenType.LPAREN)) {
            columns = [this.expect(TokenType.IDENTIFIER).value];
            while (this.match(TokenType.COMMA)) {
                columns.push(this.expect(TokenType.IDENTIFIER).value);
            }
            this.expect(TokenType.RPAREN);
        }

        this.expect(TokenType.VALUES);

        const rows = [];
        do {
            this.expect(TokenType.LPAREN);
            const values = [this.parseValue()];
            while (this.match(TokenType.COMMA)) {
                values.push(this.parseValue());
            }
            this.expect(TokenType.RPAREN);

            // Build row object
            if (columns) {
                const row = {};
                columns.forEach((col, i) => row[col] = values[i]);
                rows.push(row);
            } else {
                rows.push(values); // positional - needs schema lookup
            }
        } while (this.match(TokenType.COMMA));

        return { type: 'insert', table: tableName, columns, rows };
    }

    parseValue() {
        const token = this.peek();

        if (token.type === TokenType.NUMBER) {
            this.advance();
            const num = parseFloat(token.value);
            return Number.isInteger(num) ? parseInt(token.value) : num;
        }
        if (token.type === TokenType.STRING) {
            this.advance();
            return token.value;
        }
        if (token.type === TokenType.NULL) {
            this.advance();
            return null;
        }
        if (token.type === TokenType.TRUE) {
            this.advance();
            return true;
        }
        if (token.type === TokenType.FALSE) {
            this.advance();
            return false;
        }
        // Vector literal [1.0, 2.0, 3.0]
        if (this.match(TokenType.LBRACKET)) {
            const vec = [];
            do {
                vec.push(parseFloat(this.expect(TokenType.NUMBER).value));
            } while (this.match(TokenType.COMMA));
            this.expect(TokenType.RBRACKET);
            return vec;
        }

        throw new Error(`Unexpected value token: ${token.type}`);
    }

    parseUpdate() {
        this.expect(TokenType.UPDATE);
        const tableName = this.expect(TokenType.IDENTIFIER).value;
        this.expect(TokenType.SET);

        const set = {};
        do {
            const col = this.expect(TokenType.IDENTIFIER).value;
            this.expect(TokenType.EQ);
            set[col] = this.parseValue();
        } while (this.match(TokenType.COMMA));

        let where = null;
        if (this.match(TokenType.WHERE)) {
            where = this.parseWhereExpr();
        }

        return { type: 'update', table: tableName, set, where };
    }

    parseDelete() {
        this.expect(TokenType.DELETE);
        this.expect(TokenType.FROM);
        const tableName = this.expect(TokenType.IDENTIFIER).value;

        let where = null;
        if (this.match(TokenType.WHERE)) {
            where = this.parseWhereExpr();
        }

        return { type: 'delete', table: tableName, where };
    }

    parseSelect() {
        this.expect(TokenType.SELECT);

        // Columns
        const columns = [];
        if (this.match(TokenType.STAR)) {
            columns.push('*');
        } else {
            columns.push(this.expect(TokenType.IDENTIFIER).value);
            while (this.match(TokenType.COMMA)) {
                columns.push(this.expect(TokenType.IDENTIFIER).value);
            }
        }

        this.expect(TokenType.FROM);
        const tableName = this.expect(TokenType.IDENTIFIER).value;

        let where = null;
        if (this.match(TokenType.WHERE)) {
            where = this.parseWhereExpr();
        }

        let orderBy = null;
        if (this.match(TokenType.ORDER)) {
            this.expect(TokenType.BY);
            const column = this.expect(TokenType.IDENTIFIER).value;
            const desc = !!this.match(TokenType.DESC);
            if (!desc) this.match(TokenType.ASC);
            orderBy = { column, desc };
        }

        let limit = null;
        if (this.match(TokenType.LIMIT)) {
            limit = parseInt(this.expect(TokenType.NUMBER).value);
        }

        let offset = null;
        if (this.match(TokenType.OFFSET)) {
            offset = parseInt(this.expect(TokenType.NUMBER).value);
        }

        return { type: 'select', table: tableName, columns, where, orderBy, limit, offset };
    }

    parseWhereExpr() {
        return this.parseOrExpr();
    }

    parseOrExpr() {
        let left = this.parseAndExpr();
        while (this.match(TokenType.OR)) {
            const right = this.parseAndExpr();
            left = { op: 'OR', left, right };
        }
        return left;
    }

    parseAndExpr() {
        let left = this.parseComparison();
        while (this.match(TokenType.AND)) {
            const right = this.parseComparison();
            left = { op: 'AND', left, right };
        }
        return left;
    }

    parseComparison() {
        const column = this.expect(TokenType.IDENTIFIER).value;

        let op;
        if (this.match(TokenType.EQ)) op = '=';
        else if (this.match(TokenType.NE)) op = '!=';
        else if (this.match(TokenType.LT)) op = '<';
        else if (this.match(TokenType.LE)) op = '<=';
        else if (this.match(TokenType.GT)) op = '>';
        else if (this.match(TokenType.GE)) op = '>=';
        else if (this.match(TokenType.LIKE)) op = 'LIKE';
        else throw new Error(`Expected comparison operator`);

        const value = this.parseValue();
        return { op, column, value };
    }
}

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
const readStr = (ptr, len) => D.decode(new Uint8Array(_m.buffer, ptr, len));

// Read bytes from WASM memory (returns copy)
const readBytes = (ptr, len) => new Uint8Array(_m.buffer, ptr, len).slice();

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
        return new LanceFile(proxy, data);
    },

    /**
     * Open a Lance file from a URL using HTTP Range requests.
     * @param {string} url - URL to the Lance file
     * @returns {Promise<RemoteLanceFile>}
     */
    async openUrl(url) {
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
    },

    /**
     * Create a new LanceDatabase for multi-table queries with JOINs.
     * @returns {LanceDatabase}
     */
    createDatabase() {
        // Store reference to lanceql instance for registerRemote()
        if (typeof window !== 'undefined') {
            window.lanceql = proxy;
        } else if (typeof globalThis !== 'undefined') {
            globalThis.lanceql = proxy;
        }
        return new LanceDatabase();
    }
});

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

/**
 * Represents an open Lance file (loaded entirely in memory).
 */
export class LanceFile {
    constructor(lanceql, data) {
        this.lanceql = lanceql;
        this.wasm = lanceql.wasm;
        this.memory = lanceql.memory;

        // Copy data to WASM memory
        const bytes = new Uint8Array(data);
        this.dataPtr = this.wasm.alloc(bytes.length);
        if (!this.dataPtr) {
            throw new Error('Failed to allocate memory for Lance file');
        }
        this.dataLen = bytes.length;
        new Uint8Array(this.memory.buffer).set(bytes, this.dataPtr);

        // Open the file
        const result = this.wasm.openFile(this.dataPtr, this.dataLen);
        if (result === 0) {
            this.wasm.free(this.dataPtr, this.dataLen);
            throw new Error('Failed to open Lance file');
        }
    }

    /**
     * Close the file and free memory.
     */
    close() {
        this.wasm.closeFile();
        if (this.dataPtr) {
            this.wasm.free(this.dataPtr, this.dataLen);
            this.dataPtr = null;
        }
    }

    /**
     * Get the number of columns.
     * @returns {number}
     */
    get numColumns() {
        return this.wasm.getNumColumns();
    }

    /**
     * Get the row count for a column.
     * @param {number} colIdx
     * @returns {bigint}
     */
    getRowCount(colIdx) {
        return this.wasm.getRowCount(colIdx);
    }

    /**
     * Get debug info for a column.
     * @param {number} colIdx
     * @returns {{offset: bigint, size: bigint, rows: bigint}}
     */
    getColumnDebugInfo(colIdx) {
        return {
            offset: this.wasm.getColumnBufferOffset(colIdx),
            size: this.wasm.getColumnBufferSize(colIdx),
            rows: this.wasm.getRowCount(colIdx)
        };
    }

    /**
     * Read an int64 column as a BigInt64Array.
     * @param {number} colIdx - Column index
     * @returns {BigInt64Array}
     */
    readInt64Column(colIdx) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new BigInt64Array(0);

        const bufPtr = this.wasm.allocInt64Buffer(rowCount);
        if (!bufPtr) throw new Error('Failed to allocate int64 buffer');

        try {
            const count = this.wasm.readInt64Column(colIdx, bufPtr, rowCount);
            const result = new BigInt64Array(count);
            const view = new BigInt64Array(this.memory.buffer, bufPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.freeInt64Buffer(bufPtr, rowCount);
        }
    }

    /**
     * Read a float64 column as a Float64Array.
     * @param {number} colIdx - Column index
     * @returns {Float64Array}
     */
    readFloat64Column(colIdx) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new Float64Array(0);

        const bufPtr = this.wasm.allocFloat64Buffer(rowCount);
        if (!bufPtr) throw new Error('Failed to allocate float64 buffer');

        try {
            const count = this.wasm.readFloat64Column(colIdx, bufPtr, rowCount);
            const result = new Float64Array(count);
            const view = new Float64Array(this.memory.buffer, bufPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.freeFloat64Buffer(bufPtr, rowCount);
        }
    }

    // ========================================================================
    // Additional Numeric Type Column Methods
    // ========================================================================

    /**
     * Read an int32 column as an Int32Array.
     * @param {number} colIdx - Column index
     * @returns {Int32Array}
     */
    readInt32Column(colIdx) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new Int32Array(0);

        const bufPtr = this.wasm.allocInt32Buffer(rowCount);
        if (!bufPtr) throw new Error('Failed to allocate int32 buffer');

        try {
            const count = this.wasm.readInt32Column(colIdx, bufPtr, rowCount);
            const result = new Int32Array(count);
            const view = new Int32Array(this.memory.buffer, bufPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(bufPtr, rowCount * 4);
        }
    }

    /**
     * Read an int16 column as an Int16Array.
     * @param {number} colIdx - Column index
     * @returns {Int16Array}
     */
    readInt16Column(colIdx) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new Int16Array(0);

        const bufPtr = this.wasm.allocInt16Buffer(rowCount);
        if (!bufPtr) throw new Error('Failed to allocate int16 buffer');

        try {
            const count = this.wasm.readInt16Column(colIdx, bufPtr, rowCount);
            const result = new Int16Array(count);
            const view = new Int16Array(this.memory.buffer, bufPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(bufPtr, rowCount * 2);
        }
    }

    /**
     * Read an int8 column as an Int8Array.
     * @param {number} colIdx - Column index
     * @returns {Int8Array}
     */
    readInt8Column(colIdx) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new Int8Array(0);

        const bufPtr = this.wasm.allocInt8Buffer(rowCount);
        if (!bufPtr) throw new Error('Failed to allocate int8 buffer');

        try {
            const count = this.wasm.readInt8Column(colIdx, bufPtr, rowCount);
            const result = new Int8Array(count);
            const view = new Int8Array(this.memory.buffer, bufPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(bufPtr, rowCount);
        }
    }

    /**
     * Read a uint64 column as a BigUint64Array.
     * @param {number} colIdx - Column index
     * @returns {BigUint64Array}
     */
    readUint64Column(colIdx) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new BigUint64Array(0);

        const bufPtr = this.wasm.allocUint64Buffer(rowCount);
        if (!bufPtr) throw new Error('Failed to allocate uint64 buffer');

        try {
            const count = this.wasm.readUint64Column(colIdx, bufPtr, rowCount);
            const result = new BigUint64Array(count);
            const view = new BigUint64Array(this.memory.buffer, bufPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(bufPtr, rowCount * 8);
        }
    }

    /**
     * Read a uint32 column as a Uint32Array.
     * @param {number} colIdx - Column index
     * @returns {Uint32Array}
     */
    readUint32Column(colIdx) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new Uint32Array(0);

        const bufPtr = this.wasm.allocIndexBuffer(rowCount);
        if (!bufPtr) throw new Error('Failed to allocate uint32 buffer');

        try {
            const count = this.wasm.readUint32Column(colIdx, bufPtr, rowCount);
            const result = new Uint32Array(count);
            const view = new Uint32Array(this.memory.buffer, bufPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(bufPtr, rowCount * 4);
        }
    }

    /**
     * Read a uint16 column as a Uint16Array.
     * @param {number} colIdx - Column index
     * @returns {Uint16Array}
     */
    readUint16Column(colIdx) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new Uint16Array(0);

        const bufPtr = this.wasm.allocUint16Buffer(rowCount);
        if (!bufPtr) throw new Error('Failed to allocate uint16 buffer');

        try {
            const count = this.wasm.readUint16Column(colIdx, bufPtr, rowCount);
            const result = new Uint16Array(count);
            const view = new Uint16Array(this.memory.buffer, bufPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(bufPtr, rowCount * 2);
        }
    }

    /**
     * Read a uint8 column as a Uint8Array.
     * @param {number} colIdx - Column index
     * @returns {Uint8Array}
     */
    readUint8Column(colIdx) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new Uint8Array(0);

        const bufPtr = this.wasm.allocStringBuffer(rowCount);
        if (!bufPtr) throw new Error('Failed to allocate uint8 buffer');

        try {
            const count = this.wasm.readUint8Column(colIdx, bufPtr, rowCount);
            const result = new Uint8Array(count);
            const view = new Uint8Array(this.memory.buffer, bufPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(bufPtr, rowCount);
        }
    }

    /**
     * Read a float32 column as a Float32Array.
     * @param {number} colIdx - Column index
     * @returns {Float32Array}
     */
    readFloat32Column(colIdx) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new Float32Array(0);

        const bufPtr = this.wasm.allocFloat32Buffer(rowCount);
        if (!bufPtr) throw new Error('Failed to allocate float32 buffer');

        try {
            const count = this.wasm.readFloat32Column(colIdx, bufPtr, rowCount);
            const result = new Float32Array(count);
            const view = new Float32Array(this.memory.buffer, bufPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(bufPtr, rowCount * 4);
        }
    }

    /**
     * Read a boolean column as a Uint8Array (0 or 1 values).
     * @param {number} colIdx - Column index
     * @returns {Uint8Array}
     */
    readBoolColumn(colIdx) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new Uint8Array(0);

        const bufPtr = this.wasm.allocStringBuffer(rowCount);
        if (!bufPtr) throw new Error('Failed to allocate bool buffer');

        try {
            const count = this.wasm.readBoolColumn(colIdx, bufPtr, rowCount);
            const result = new Uint8Array(count);
            const view = new Uint8Array(this.memory.buffer, bufPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(bufPtr, rowCount);
        }
    }

    /**
     * Read int32 values at specific row indices.
     * @param {number} colIdx - Column index
     * @param {Uint32Array} indices - Row indices to read
     * @returns {Int32Array}
     */
    readInt32AtIndices(colIdx, indices) {
        if (indices.length === 0) return new Int32Array(0);

        const idxPtr = this.wasm.allocIndexBuffer(indices.length);
        if (!idxPtr) throw new Error('Failed to allocate index buffer');

        const outPtr = this.wasm.allocInt32Buffer(indices.length);
        if (!outPtr) {
            this.wasm.free(idxPtr, indices.length * 4);
            throw new Error('Failed to allocate output buffer');
        }

        try {
            new Uint32Array(this.memory.buffer, idxPtr, indices.length).set(indices);
            const count = this.wasm.readInt32AtIndices(colIdx, idxPtr, indices.length, outPtr);
            const result = new Int32Array(count);
            const view = new Int32Array(this.memory.buffer, outPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(idxPtr, indices.length * 4);
            this.wasm.free(outPtr, indices.length * 4);
        }
    }

    /**
     * Read float32 values at specific row indices.
     * @param {number} colIdx - Column index
     * @param {Uint32Array} indices - Row indices to read
     * @returns {Float32Array}
     */
    readFloat32AtIndices(colIdx, indices) {
        if (indices.length === 0) return new Float32Array(0);

        const idxPtr = this.wasm.allocIndexBuffer(indices.length);
        if (!idxPtr) throw new Error('Failed to allocate index buffer');

        const outPtr = this.wasm.allocFloat32Buffer(indices.length);
        if (!outPtr) {
            this.wasm.free(idxPtr, indices.length * 4);
            throw new Error('Failed to allocate output buffer');
        }

        try {
            new Uint32Array(this.memory.buffer, idxPtr, indices.length).set(indices);
            const count = this.wasm.readFloat32AtIndices(colIdx, idxPtr, indices.length, outPtr);
            const result = new Float32Array(count);
            const view = new Float32Array(this.memory.buffer, outPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(idxPtr, indices.length * 4);
            this.wasm.free(outPtr, indices.length * 4);
        }
    }

    /**
     * Read uint8 values at specific row indices.
     * @param {number} colIdx - Column index
     * @param {Uint32Array} indices - Row indices to read
     * @returns {Uint8Array}
     */
    readUint8AtIndices(colIdx, indices) {
        if (indices.length === 0) return new Uint8Array(0);

        const idxPtr = this.wasm.allocIndexBuffer(indices.length);
        if (!idxPtr) throw new Error('Failed to allocate index buffer');

        const outPtr = this.wasm.allocStringBuffer(indices.length);
        if (!outPtr) {
            this.wasm.free(idxPtr, indices.length * 4);
            throw new Error('Failed to allocate output buffer');
        }

        try {
            new Uint32Array(this.memory.buffer, idxPtr, indices.length).set(indices);
            const count = this.wasm.readUint8AtIndices(colIdx, idxPtr, indices.length, outPtr);
            const result = new Uint8Array(count);
            const view = new Uint8Array(this.memory.buffer, outPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(idxPtr, indices.length * 4);
            this.wasm.free(outPtr, indices.length);
        }
    }

    /**
     * Read bool values at specific row indices.
     * @param {number} colIdx - Column index
     * @param {Uint32Array} indices - Row indices to read
     * @returns {Uint8Array}
     */
    readBoolAtIndices(colIdx, indices) {
        if (indices.length === 0) return new Uint8Array(0);

        const idxPtr = this.wasm.allocIndexBuffer(indices.length);
        if (!idxPtr) throw new Error('Failed to allocate index buffer');

        const outPtr = this.wasm.allocStringBuffer(indices.length);
        if (!outPtr) {
            this.wasm.free(idxPtr, indices.length * 4);
            throw new Error('Failed to allocate output buffer');
        }

        try {
            new Uint32Array(this.memory.buffer, idxPtr, indices.length).set(indices);
            const count = this.wasm.readBoolAtIndices(colIdx, idxPtr, indices.length, outPtr);
            const result = new Uint8Array(count);
            const view = new Uint8Array(this.memory.buffer, outPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(idxPtr, indices.length * 4);
            this.wasm.free(outPtr, indices.length);
        }
    }

    // ========================================================================
    // Query Methods
    // ========================================================================

    /**
     * Filter operator constants.
     */
    static Op = {
        EQ: 0,  // Equal
        NE: 1,  // Not equal
        LT: 2,  // Less than
        LE: 3,  // Less than or equal
        GT: 4,  // Greater than
        GE: 5   // Greater than or equal
    };

    /**
     * Filter int64 column and return matching row indices.
     * @param {number} colIdx - Column index
     * @param {number} op - Comparison operator (use LanceFile.Op)
     * @param {bigint|number} value - Value to compare against
     * @returns {Uint32Array} Array of matching row indices
     */
    filterInt64(colIdx, op, value) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new Uint32Array(0);

        const idxPtr = this.wasm.allocIndexBuffer(rowCount);
        if (!idxPtr) throw new Error('Failed to allocate index buffer');

        try {
            const count = this.wasm.filterInt64Column(
                colIdx, op, BigInt(value), idxPtr, rowCount
            );
            const result = new Uint32Array(count);
            const view = new Uint32Array(this.memory.buffer, idxPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(idxPtr, rowCount * 4);
        }
    }

    /**
     * Filter float64 column and return matching row indices.
     * @param {number} colIdx - Column index
     * @param {number} op - Comparison operator (use LanceFile.Op)
     * @param {number} value - Value to compare against
     * @returns {Uint32Array} Array of matching row indices
     */
    filterFloat64(colIdx, op, value) {
        const rowCount = Number(this.getRowCount(colIdx));
        if (rowCount === 0) return new Uint32Array(0);

        const idxPtr = this.wasm.allocIndexBuffer(rowCount);
        if (!idxPtr) throw new Error('Failed to allocate index buffer');

        try {
            const count = this.wasm.filterFloat64Column(
                colIdx, op, value, idxPtr, rowCount
            );
            const result = new Uint32Array(count);
            const view = new Uint32Array(this.memory.buffer, idxPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(idxPtr, rowCount * 4);
        }
    }

    /**
     * Read int64 values at specific row indices.
     * @param {number} colIdx - Column index
     * @param {Uint32Array} indices - Row indices to read
     * @returns {BigInt64Array}
     */
    readInt64AtIndices(colIdx, indices) {
        if (indices.length === 0) return new BigInt64Array(0);

        // Copy indices to WASM memory
        const idxPtr = this.wasm.allocIndexBuffer(indices.length);
        if (!idxPtr) throw new Error('Failed to allocate index buffer');

        const outPtr = this.wasm.allocInt64Buffer(indices.length);
        if (!outPtr) {
            this.wasm.free(idxPtr, indices.length * 4);
            throw new Error('Failed to allocate output buffer');
        }

        try {
            new Uint32Array(this.memory.buffer, idxPtr, indices.length).set(indices);

            const count = this.wasm.readInt64AtIndices(
                colIdx, idxPtr, indices.length, outPtr
            );

            const result = new BigInt64Array(count);
            const view = new BigInt64Array(this.memory.buffer, outPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(idxPtr, indices.length * 4);
            this.wasm.freeInt64Buffer(outPtr, indices.length);
        }
    }

    /**
     * Read float64 values at specific row indices.
     * @param {number} colIdx - Column index
     * @param {Uint32Array} indices - Row indices to read
     * @returns {Float64Array}
     */
    readFloat64AtIndices(colIdx, indices) {
        if (indices.length === 0) return new Float64Array(0);

        // Copy indices to WASM memory
        const idxPtr = this.wasm.allocIndexBuffer(indices.length);
        if (!idxPtr) throw new Error('Failed to allocate index buffer');

        const outPtr = this.wasm.allocFloat64Buffer(indices.length);
        if (!outPtr) {
            this.wasm.free(idxPtr, indices.length * 4);
            throw new Error('Failed to allocate output buffer');
        }

        try {
            new Uint32Array(this.memory.buffer, idxPtr, indices.length).set(indices);

            const count = this.wasm.readFloat64AtIndices(
                colIdx, idxPtr, indices.length, outPtr
            );

            const result = new Float64Array(count);
            const view = new Float64Array(this.memory.buffer, outPtr, count);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(idxPtr, indices.length * 4);
            this.wasm.freeFloat64Buffer(outPtr, indices.length);
        }
    }

    // ========================================================================
    // Aggregation Methods
    // ========================================================================

    /**
     * Sum all values in an int64 column.
     * @param {number} colIdx - Column index
     * @returns {bigint}
     */
    sumInt64(colIdx) {
        return this.wasm.sumInt64Column(colIdx);
    }

    /**
     * Sum all values in a float64 column.
     * @param {number} colIdx - Column index
     * @returns {number}
     */
    sumFloat64(colIdx) {
        return this.wasm.sumFloat64Column(colIdx);
    }

    /**
     * Get minimum value in an int64 column.
     * @param {number} colIdx - Column index
     * @returns {bigint}
     */
    minInt64(colIdx) {
        return this.wasm.minInt64Column(colIdx);
    }

    /**
     * Get maximum value in an int64 column.
     * @param {number} colIdx - Column index
     * @returns {bigint}
     */
    maxInt64(colIdx) {
        return this.wasm.maxInt64Column(colIdx);
    }

    /**
     * Get average of a float64 column.
     * @param {number} colIdx - Column index
     * @returns {number}
     */
    avgFloat64(colIdx) {
        return this.wasm.avgFloat64Column(colIdx);
    }

    // ========================================================================
    // String Column Methods
    // ========================================================================

    /**
     * Debug: Get string column buffer info
     * @param {number} colIdx - Column index
     * @returns {{offsetsSize: number, dataSize: number}}
     */
    debugStringColInfo(colIdx) {
        const packed = this.wasm.debugStringColInfo(colIdx);
        return {
            offsetsSize: Number(BigInt(packed) >> 32n),
            dataSize: Number(BigInt(packed) & 0xFFFFFFFFn)
        };
    }

    /**
     * Debug: Get string read info for a specific row
     * @param {number} colIdx - Column index
     * @param {number} rowIdx - Row index
     * @returns {{strStart: number, strLen: number} | {error: string}}
     */
    debugReadStringInfo(colIdx, rowIdx) {
        const packed = this.wasm.debugReadStringInfo(colIdx, rowIdx);
        // Check for error codes (0xDEAD00XX)
        if ((packed & 0xFFFF0000n) === 0xDEAD0000n) {
            const errCode = Number(packed & 0xFFFFn);
            const errors = {
                1: 'No file data',
                2: 'No column entry',
                3: 'Col meta out of bounds',
                4: 'Not a string column',
                5: 'Row out of bounds',
                6: 'Invalid offset size'
            };
            return { error: errors[errCode] || `Unknown error ${errCode}` };
        }
        return {
            strStart: Number(BigInt(packed) >> 32n),
            strLen: Number(BigInt(packed) & 0xFFFFFFFFn)
        };
    }

    /**
     * Debug: Get data_start position for string column
     * @param {number} colIdx - Column index
     * @returns {{dataStart: number, fileLen: number}}
     */
    debugStringDataStart(colIdx) {
        const packed = this.wasm.debugStringDataStart(colIdx);
        return {
            dataStart: Number(BigInt(packed) >> 32n),
            fileLen: Number(BigInt(packed) & 0xFFFFFFFFn)
        };
    }

    /**
     * Get the number of strings in a column.
     * @param {number} colIdx - Column index
     * @returns {number}
     */
    getStringCount(colIdx) {
        return Number(this.wasm.getStringCount(colIdx));
    }

    /**
     * Read a single string at a specific row index.
     * @param {number} colIdx - Column index
     * @param {number} rowIdx - Row index
     * @returns {string}
     */
    readStringAt(colIdx, rowIdx) {
        const maxLen = 4096; // Max string length to read
        const bufPtr = this.wasm.allocStringBuffer(maxLen);
        if (!bufPtr) throw new Error('Failed to allocate string buffer');

        try {
            const actualLen = this.wasm.readStringAt(colIdx, rowIdx, bufPtr, maxLen);
            if (actualLen === 0) return '';

            const bytes = new Uint8Array(this.memory.buffer, bufPtr, Math.min(actualLen, maxLen));
            return new TextDecoder().decode(bytes);
        } finally {
            this.wasm.free(bufPtr, maxLen);
        }
    }

    /**
     * Read all strings from a column.
     * @param {number} colIdx - Column index
     * @param {number} limit - Maximum number of strings to read
     * @returns {string[]}
     */
    readStringColumn(colIdx, limit = 1000) {
        const count = Math.min(this.getStringCount(colIdx), limit);
        if (count === 0) return [];

        const results = [];
        for (let i = 0; i < count; i++) {
            results.push(this.readStringAt(colIdx, i));
        }
        return results;
    }

    /**
     * Read strings at specific row indices.
     * @param {number} colIdx - Column index
     * @param {Uint32Array} indices - Row indices to read
     * @returns {string[]}
     */
    readStringsAtIndices(colIdx, indices) {
        if (indices.length === 0) return [];

        // Use smaller buffer - estimate based on indices count
        // Assume average string is ~256 bytes, capped at 256KB to avoid WASM memory issues
        const maxTotalLen = Math.min(indices.length * 256, 256 * 1024);
        const idxPtr = this.wasm.allocIndexBuffer(indices.length);
        if (!idxPtr) throw new Error('Failed to allocate index buffer');

        const strBufPtr = this.wasm.allocStringBuffer(maxTotalLen);
        if (!strBufPtr) {
            this.wasm.free(idxPtr, indices.length * 4);
            throw new Error('Failed to allocate string buffer');
        }

        const lenBufPtr = this.wasm.allocU32Buffer(indices.length);
        if (!lenBufPtr) {
            this.wasm.free(idxPtr, indices.length * 4);
            this.wasm.free(strBufPtr, maxTotalLen);
            throw new Error('Failed to allocate length buffer');
        }

        try {
            // Copy indices to WASM
            new Uint32Array(this.memory.buffer, idxPtr, indices.length).set(indices);

            // Read strings
            const totalWritten = this.wasm.readStringsAtIndices(
                colIdx, idxPtr, indices.length, strBufPtr, maxTotalLen, lenBufPtr
            );

            // Get lengths
            const lengths = new Uint32Array(this.memory.buffer, lenBufPtr, indices.length);

            // Decode strings
            const results = [];
            let offset = 0;
            for (let i = 0; i < indices.length; i++) {
                const len = lengths[i];
                if (len > 0 && offset + len <= totalWritten) {
                    const bytes = new Uint8Array(this.memory.buffer, strBufPtr + offset, len);
                    results.push(new TextDecoder().decode(bytes));
                    offset += len;
                } else {
                    results.push('');
                }
            }
            return results;
        } finally {
            this.wasm.free(idxPtr, indices.length * 4);
            this.wasm.free(strBufPtr, maxTotalLen);
            this.wasm.free(lenBufPtr, indices.length * 4);
        }
    }

    // ========================================================================
    // Vector Column Support (for embeddings/semantic search)
    // ========================================================================

    /**
     * Get vector info for a column.
     * @param {number} colIdx - Column index
     * @returns {{rows: number, dimension: number}}
     */
    getVectorInfo(colIdx) {
        const packed = this.wasm.getVectorInfo(colIdx);
        return {
            rows: Number(BigInt(packed) >> 32n),
            dimension: Number(BigInt(packed) & 0xFFFFFFFFn)
        };
    }

    /**
     * Read a single vector at index.
     * @param {number} colIdx - Column index
     * @param {number} rowIdx - Row index
     * @returns {Float32Array}
     */
    readVectorAt(colIdx, rowIdx) {
        const info = this.getVectorInfo(colIdx);
        if (info.dimension === 0) return new Float32Array(0);

        const bufPtr = this.wasm.allocFloat32Buffer(info.dimension);
        if (!bufPtr) throw new Error('Failed to allocate vector buffer');

        try {
            const dim = this.wasm.readVectorAt(colIdx, rowIdx, bufPtr, info.dimension);
            const result = new Float32Array(dim);
            const view = new Float32Array(this.memory.buffer, bufPtr, dim);
            result.set(view);
            return result;
        } finally {
            this.wasm.free(bufPtr, info.dimension * 4);
        }
    }

    /**
     * Compute cosine similarity between two vectors.
     * @param {Float32Array} vecA
     * @param {Float32Array} vecB
     * @returns {number} Similarity score (-1 to 1)
     */
    cosineSimilarity(vecA, vecB) {
        if (vecA.length !== vecB.length) {
            throw new Error('Vector dimensions must match');
        }

        const ptrA = this.wasm.allocFloat32Buffer(vecA.length);
        const ptrB = this.wasm.allocFloat32Buffer(vecB.length);
        if (!ptrA || !ptrB) throw new Error('Failed to allocate buffers');

        try {
            new Float32Array(this.memory.buffer, ptrA, vecA.length).set(vecA);
            new Float32Array(this.memory.buffer, ptrB, vecB.length).set(vecB);
            return this.wasm.cosineSimilarity(ptrA, ptrB, vecA.length);
        } finally {
            this.wasm.free(ptrA, vecA.length * 4);
            this.wasm.free(ptrB, vecB.length * 4);
        }
    }

    /**
     * Find top-k most similar vectors to query.
     * @param {number} colIdx - Column index with vectors
     * @param {Float32Array} queryVec - Query vector
     * @param {number} topK - Number of results to return
     * @returns {{indices: Uint32Array, scores: Float32Array}}
     */
    vectorSearch(colIdx, queryVec, topK = 10) {
        const queryPtr = this.wasm.allocFloat32Buffer(queryVec.length);
        const indicesPtr = this.wasm.allocIndexBuffer(topK);
        const scoresPtr = this.wasm.allocFloat32Buffer(topK);

        if (!queryPtr || !indicesPtr || !scoresPtr) {
            throw new Error('Failed to allocate buffers');
        }

        try {
            new Float32Array(this.memory.buffer, queryPtr, queryVec.length).set(queryVec);

            const count = this.wasm.vectorSearchTopK(
                colIdx, queryPtr, queryVec.length, topK, indicesPtr, scoresPtr
            );

            const indices = new Uint32Array(count);
            const scores = new Float32Array(count);

            indices.set(new Uint32Array(this.memory.buffer, indicesPtr, count));
            scores.set(new Float32Array(this.memory.buffer, scoresPtr, count));

            return { indices, scores };
        } finally {
            this.wasm.free(queryPtr, queryVec.length * 4);
            this.wasm.free(indicesPtr, topK * 4);
            this.wasm.free(scoresPtr, topK * 4);
        }
    }

    // ========================================================================
    // DataFrame-like API
    // ========================================================================

    /**
     * Create a DataFrame-like query builder for this file.
     * @returns {DataFrame}
     */
    df() {
        return new DataFrame(this);
    }
}

/**
 * DataFrame-like query builder for fluent queries.
 */
export class DataFrame {
    constructor(file) {
        this.file = file;
        this._filterOps = [];  // Array of {colIdx, op, value, type}
        this._selectCols = null;
        this._limitValue = null;
    }

    /**
     * Filter rows where column matches condition.
     * @param {number} colIdx - Column index
     * @param {string} op - Operator: '=', '!=', '<', '<=', '>', '>='
     * @param {number|bigint} value - Value to compare
     * @param {string} type - 'int64' or 'float64'
     * @returns {DataFrame}
     */
    filter(colIdx, op, value, type = 'int64') {
        const opMap = {
            '=': LanceFile.Op.EQ, '==': LanceFile.Op.EQ,
            '!=': LanceFile.Op.NE, '<>': LanceFile.Op.NE,
            '<': LanceFile.Op.LT,
            '<=': LanceFile.Op.LE,
            '>': LanceFile.Op.GT,
            '>=': LanceFile.Op.GE
        };

        const df = new DataFrame(this.file);
        df._filterOps = [...this._filterOps, { colIdx, op: opMap[op], value, type }];
        df._selectCols = this._selectCols;
        df._limitValue = this._limitValue;
        return df;
    }

    /**
     * Select specific columns.
     * @param {...number} colIndices - Column indices to select
     * @returns {DataFrame}
     */
    select(...colIndices) {
        const df = new DataFrame(this.file);
        df._filterOps = [...this._filterOps];
        df._selectCols = colIndices;
        df._limitValue = this._limitValue;
        return df;
    }

    /**
     * Limit number of results.
     * @param {number} n - Maximum rows
     * @returns {DataFrame}
     */
    limit(n) {
        const df = new DataFrame(this.file);
        df._filterOps = [...this._filterOps];
        df._selectCols = this._selectCols;
        df._limitValue = n;
        return df;
    }

    /**
     * Execute the query and return row indices.
     * @returns {Uint32Array}
     */
    collectIndices() {
        let indices = null;

        // Apply filters
        for (const f of this._filterOps) {
            let newIndices;
            if (f.type === 'int64') {
                newIndices = this.file.filterInt64(f.colIdx, f.op, f.value);
            } else {
                newIndices = this.file.filterFloat64(f.colIdx, f.op, f.value);
            }

            if (indices === null) {
                indices = newIndices;
            } else {
                // Intersect indices
                const set = new Set(newIndices);
                indices = indices.filter(i => set.has(i));
                indices = new Uint32Array(indices);
            }
        }

        // If no filters, get all row indices
        if (indices === null) {
            const rowCount = Number(this.file.getRowCount(0));
            indices = new Uint32Array(rowCount);
            for (let i = 0; i < rowCount; i++) indices[i] = i;
        }

        // Apply limit
        if (this._limitValue !== null && indices.length > this._limitValue) {
            indices = indices.slice(0, this._limitValue);
        }

        return indices;
    }

    /**
     * Execute the query and return results as arrays.
     * @returns {Object} Object with column data arrays
     */
    collect() {
        const indices = this.collectIndices();
        const result = { _indices: indices };

        const cols = this._selectCols ||
            Array.from({ length: this.file.numColumns }, (_, i) => i);

        for (const colIdx of cols) {
            // Try int64 first, then float64
            try {
                result[`col${colIdx}`] = this.file.readInt64AtIndices(colIdx, indices);
            } catch {
                try {
                    result[`col${colIdx}`] = this.file.readFloat64AtIndices(colIdx, indices);
                } catch {
                    result[`col${colIdx}`] = null;
                }
            }
        }

        return result;
    }

    /**
     * Count matching rows.
     * @returns {number}
     */
    count() {
        return this.collectIndices().length;
    }
}

/**
 * Represents a Lance file opened from a remote URL.
 * Uses HTTP Range requests to fetch data on demand.
 */
export class RemoteLanceFile {
    constructor(lanceql, url, fileSize, footerData) {
        this.lanceql = lanceql;
        this.wasm = lanceql.wasm;
        this.memory = lanceql.memory;
        this.url = url;
        this.fileSize = fileSize;

        // Store footer data in WASM memory
        const bytes = new Uint8Array(footerData);
        this.footerPtr = this.wasm.alloc(bytes.length);
        if (!this.footerPtr) {
            throw new Error('Failed to allocate memory for footer');
        }
        this.footerLen = bytes.length;
        new Uint8Array(this.memory.buffer).set(bytes, this.footerPtr);

        // Parse footer
        this._numColumns = this.wasm.parseFooterGetColumns(this.footerPtr, this.footerLen);
        this._majorVersion = this.wasm.parseFooterGetMajorVersion(this.footerPtr, this.footerLen);
        this._minorVersion = this.wasm.parseFooterGetMinorVersion(this.footerPtr, this.footerLen);
        this._columnMetaStart = this.wasm.getColumnMetaStart(this.footerPtr, this.footerLen);
        this._columnMetaOffsetsStart = this.wasm.getColumnMetaOffsetsStart(this.footerPtr, this.footerLen);

        // Cache for column metadata to avoid repeated fetches
        this._columnMetaCache = new Map();
        this._columnOffsetCache = new Map();
        this._columnTypes = null;

        // Schema info from manifest (populated by loadSchema())
        this._schema = null;
        this._datasetBaseUrl = null;

        // IVF index for ANN search (populated by tryLoadIndex())
        this._ivfIndex = null;
    }

    /**
     * Open a remote Lance file.
     * @param {LanceQL} lanceql
     * @param {string} url
     * @returns {Promise<RemoteLanceFile>}
     */
    static async open(lanceql, url) {
        // First, get file size with HEAD request
        const headResponse = await fetch(url, { method: 'HEAD' });
        if (!headResponse.ok) {
            throw new Error(`HTTP error: ${headResponse.status}`);
        }

        const contentLength = headResponse.headers.get('Content-Length');
        if (!contentLength) {
            throw new Error('Server did not return Content-Length');
        }
        const fileSize = parseInt(contentLength, 10);

        // Fetch footer (last 40 bytes)
        const footerSize = 40;
        const footerStart = fileSize - footerSize;
        const footerResponse = await fetch(url, {
            headers: {
                'Range': `bytes=${footerStart}-${fileSize - 1}`
            }
        });

        if (!footerResponse.ok && footerResponse.status !== 206) {
            throw new Error(`HTTP error: ${footerResponse.status}`);
        }

        const footerData = await footerResponse.arrayBuffer();

        // Verify magic bytes
        const footerBytes = new Uint8Array(footerData);
        const magic = String.fromCharCode(
            footerBytes[36], footerBytes[37], footerBytes[38], footerBytes[39]
        );
        if (magic !== 'LANC') {
            throw new Error(`Invalid Lance file: expected LANC magic, got "${magic}"`);
        }

        const file = new RemoteLanceFile(lanceql, url, fileSize, footerData);

        // Try to detect and load schema from manifest
        await file._tryLoadSchema();

        // Try to load IVF index for ANN search
        await file._tryLoadIndex();

        // Log summary
        console.log(`[LanceQL] Loaded: ${file._numColumns} columns, ${(fileSize / 1024 / 1024).toFixed(1)}MB, schema: ${file._schema ? 'yes' : 'no'}, index: ${file.hasIndex() ? 'yes' : 'no'}`);

        return file;
    }

    /**
     * Try to load IVF index from dataset.
     * @private
     */
    async _tryLoadIndex() {
        if (!this._datasetBaseUrl) return;

        try {
            this._ivfIndex = await IVFIndex.tryLoad(this._datasetBaseUrl);
        } catch (e) {
            // Index loading is optional, silently ignore
        }
    }

    /**
     * Check if ANN index is available.
     * @returns {boolean}
     */
    hasIndex() {
        return this._ivfIndex !== null && this._ivfIndex.centroids !== null;
    }

    /**
     * Try to detect dataset base URL and load schema from manifest.
     * Lance datasets have structure: base.lance/_versions/, base.lance/data/
     * @private
     */
    async _tryLoadSchema() {
        // Try to infer dataset base URL from file URL
        // Pattern: https://host/path/dataset.lance/data/filename.lance
        const match = this.url.match(/^(.+\.lance)\/data\/.+\.lance$/);
        if (!match) {
            // URL doesn't match standard Lance dataset structure
            return;
        }

        this._datasetBaseUrl = match[1];

        try {
            // Try manifest version 1 first
            const manifestUrl = `${this._datasetBaseUrl}/_versions/1.manifest`;
            const response = await fetch(manifestUrl);

            if (!response.ok) {
                return;
            }

            const manifestData = await response.arrayBuffer();
            this._schema = this._parseManifest(new Uint8Array(manifestData));
        } catch (e) {
            // Silently fail - schema is optional
            // Manifest loading is optional, silently ignore
        }
    }

    /**
     * Parse Lance manifest protobuf to extract schema.
     * Manifest structure:
     * - 4 bytes: content length (little-endian u32)
     * - N bytes: protobuf content
     * - 16 bytes: footer (zeros + version + LANC magic)
     * @private
     */
    _parseManifest(bytes) {
        const view = new DataView(bytes.buffer, bytes.byteOffset);

        // Lance manifest file structure:
        // - Chunk 1 (len-prefixed): Transaction metadata (may be small/incremental)
        // - Chunk 2 (len-prefixed): Full manifest with schema + fragments
        // - Footer (16 bytes): Offsets + "LANC" magic

        // Read chunk 1 length
        const chunk1Len = view.getUint32(0, true);

        // Check if there's a chunk 2 (full manifest data)
        const chunk2Start = 4 + chunk1Len;
        let protoData;

        if (chunk2Start + 4 < bytes.length) {
            const chunk2Len = view.getUint32(chunk2Start, true);
            if (chunk2Len > 0 && chunk2Start + 4 + chunk2Len <= bytes.length) {
                // Use chunk 2 (full manifest)
                protoData = bytes.slice(chunk2Start + 4, chunk2Start + 4 + chunk2Len);
            } else {
                protoData = bytes.slice(4, 4 + chunk1Len);
            }
        } else {
            protoData = bytes.slice(4, 4 + chunk1Len);
        }

        let pos = 0;
        const fields = [];

        const readVarint = () => {
            let result = 0;
            let shift = 0;
            while (pos < protoData.length) {
                const byte = protoData[pos++];
                result |= (byte & 0x7F) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7;
            }
            return result;
        };

        // Parse top-level Manifest message
        while (pos < protoData.length) {
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (fieldNum === 1 && wireType === 2) {
                // Field 1 = schema (repeated Field message)
                const fieldLen = readVarint();
                const fieldEnd = pos + fieldLen;

                // Parse Field message
                let name = null;
                let id = null;
                let logicalType = null;

                while (pos < fieldEnd) {
                    const fTag = readVarint();
                    const fNum = fTag >> 3;
                    const fWire = fTag & 0x7;

                    if (fWire === 0) {
                        // Varint
                        const val = readVarint();
                        if (fNum === 3) id = val;  // Field.id
                    } else if (fWire === 2) {
                        // Length-delimited
                        const len = readVarint();
                        const content = protoData.slice(pos, pos + len);
                        pos += len;

                        if (fNum === 2) {
                            // Field.name
                            name = new TextDecoder().decode(content);
                        } else if (fNum === 5) {
                            // Field.logical_type
                            logicalType = new TextDecoder().decode(content);
                        }
                    } else if (fWire === 5) {
                        pos += 4;  // Fixed32
                    } else if (fWire === 1) {
                        pos += 8;  // Fixed64
                    }
                }

                if (name) {
                    fields.push({ name, id, type: logicalType });
                }
            } else {
                // Skip other fields
                if (wireType === 0) {
                    readVarint();
                } else if (wireType === 2) {
                    const len = readVarint();
                    pos += len;
                } else if (wireType === 5) {
                    pos += 4;
                } else if (wireType === 1) {
                    pos += 8;
                }
            }
        }

        return fields;
    }

    /**
     * Get column names from schema (if available).
     * Falls back to 'column_N' if schema not loaded.
     * @returns {string[]}
     */
    get columnNames() {
        if (this._schema && this._schema.length > 0) {
            return this._schema.map(f => f.name);
        }
        // Fallback to generic names
        return Array.from({ length: this._numColumns }, (_, i) => `column_${i}`);
    }

    /**
     * Get full schema info (if available).
     * @returns {Array<{name: string, id: number, type: string}>|null}
     */
    get schema() {
        return this._schema;
    }

    /**
     * Get dataset base URL (if detected).
     * @returns {string|null}
     */
    get datasetBaseUrl() {
        return this._datasetBaseUrl;
    }

    /**
     * Fetch bytes from the remote file at a specific range.
     * @param {number} start - Start offset
     * @param {number} end - End offset (inclusive)
     * @returns {Promise<ArrayBuffer>}
     */
    async fetchRange(start, end) {
        // Debug: console.log(`fetchRange: ${start}-${end} (size: ${end - start + 1})`);

        // Validate range
        if (start < 0 || end < start || end >= this.size) {
            console.error(`Invalid range: ${start}-${end}, file size: ${this.size}`);
        }

        const response = await fetch(this.url, {
            headers: {
                'Range': `bytes=${start}-${end}`
            }
        });

        if (!response.ok && response.status !== 206) {
            console.error(`Fetch failed: ${response.status} for range ${start}-${end}`);
            throw new Error(`HTTP error: ${response.status}`);
        }

        const data = await response.arrayBuffer();

        // Track stats if callback available
        if (this._onFetch) {
            this._onFetch(data.byteLength, 1);
        }

        return data;
    }

    /**
     * Set callback for network stats tracking.
     * @param {function} callback - Function(bytesDownloaded, requestCount)
     */
    onFetch(callback) {
        this._onFetch = callback;
    }

    /**
     * Close the file and free memory.
     */
    close() {
        if (this.footerPtr) {
            this.wasm.free(this.footerPtr, this.footerLen);
            this.footerPtr = null;
        }
    }

    /**
     * Get the number of columns.
     * @returns {number}
     */
    get numColumns() {
        return this._numColumns;
    }

    /**
     * Get the file size.
     * @returns {number}
     */
    get size() {
        return this.fileSize;
    }

    /**
     * Get the version.
     * @returns {{major: number, minor: number}}
     */
    get version() {
        return {
            major: this._majorVersion,
            minor: this._minorVersion
        };
    }

    /**
     * Get the column metadata start offset.
     * @returns {number}
     */
    get columnMetaStart() {
        return Number(this._columnMetaStart);
    }

    /**
     * Get the column metadata offsets start.
     * @returns {number}
     */
    get columnMetaOffsetsStart() {
        return Number(this._columnMetaOffsetsStart);
    }

    /**
     * Get column offset entry from column metadata offsets.
     * Uses caching to avoid repeated fetches.
     * @param {number} colIdx
     * @returns {Promise<{pos: number, len: number}>}
     */
    async getColumnOffsetEntry(colIdx) {
        if (colIdx >= this._numColumns) {
            return { pos: 0, len: 0 };
        }

        // Check cache first
        if (this._columnOffsetCache.has(colIdx)) {
            return this._columnOffsetCache.get(colIdx);
        }

        // Each entry is 16 bytes (8 bytes pos + 8 bytes len)
        const entryOffset = this.columnMetaOffsetsStart + colIdx * 16;
        const data = await this.fetchRange(entryOffset, entryOffset + 15);
        const view = new DataView(data);

        const entry = {
            pos: Number(view.getBigUint64(0, true)),
            len: Number(view.getBigUint64(8, true))
        };

        // Cache the result
        this._columnOffsetCache.set(colIdx, entry);
        return entry;
    }

    /**
     * Get debug info for a column (requires network request).
     * @param {number} colIdx
     * @returns {Promise<{offset: number, size: number, rows: number}>}
     */
    async getColumnDebugInfo(colIdx) {
        const entry = await this.getColumnOffsetEntry(colIdx);
        if (entry.len === 0) {
            return { offset: 0, size: 0, rows: 0 };
        }

        // Fetch column metadata
        const colMetaData = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const bytes = new Uint8Array(colMetaData);

        // Parse column metadata to get buffer info
        const info = this._parseColumnMeta(bytes);
        return info;
    }

    /**
     * Parse column metadata to extract buffer offsets and row count.
     * For nullable columns, there are typically 2 buffers:
     * - Buffer 0: null bitmap
     * - Buffer 1: actual data values
     * @private
     */
    _parseColumnMeta(bytes) {
        let pos = 0;
        const pages = [];
        let totalRows = 0;

        // Read varint as BigInt to handle large values (>2GB offsets)
        const readVarint = () => {
            let result = 0n;
            let shift = 0n;
            while (pos < bytes.length) {
                const byte = bytes[pos++];
                result |= BigInt(byte & 0x7F) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7n;
            }
            return Number(result);
        };

        while (pos < bytes.length) {
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (fieldNum === 2 && wireType === 2) {
                // pages field (length-delimited) - parse ALL pages
                const pageLen = readVarint();
                const pageEnd = pos + pageLen;

                const pageOffsets = [];
                const pageSizes = [];
                let pageRows = 0;

                // Parse page
                while (pos < pageEnd) {
                    const pageTag = readVarint();
                    const pageField = pageTag >> 3;
                    const pageWire = pageTag & 0x7;

                    if (pageField === 1 && pageWire === 2) {
                        // buffer_offsets (packed)
                        const packedLen = readVarint();
                        const packedEnd = pos + packedLen;
                        while (pos < packedEnd) {
                            pageOffsets.push(readVarint());
                        }
                    } else if (pageField === 2 && pageWire === 2) {
                        // buffer_sizes (packed)
                        const packedLen = readVarint();
                        const packedEnd = pos + packedLen;
                        while (pos < packedEnd) {
                            pageSizes.push(readVarint());
                        }
                    } else if (pageField === 3 && pageWire === 0) {
                        // length (rows)
                        pageRows = readVarint();
                    } else {
                        // Skip field
                        if (pageWire === 0) readVarint();
                        else if (pageWire === 2) {
                            const skipLen = readVarint();
                            pos += skipLen;
                        }
                        else if (pageWire === 5) pos += 4;
                        else if (pageWire === 1) pos += 8;
                    }
                }

                pages.push({
                    offsets: pageOffsets,
                    sizes: pageSizes,
                    rows: pageRows
                });
                totalRows += pageRows;
                // Don't break - continue to read more pages
            } else {
                // Skip field
                if (wireType === 0) readVarint();
                else if (wireType === 2) {
                    const skipLen = readVarint();
                    pos += skipLen;
                }
                else if (wireType === 5) pos += 4;
                else if (wireType === 1) pos += 8;
            }
        }

        // Combine all pages - use first page for offset/size (for backward compat)
        // Also compute total size across all pages for multi-page columns
        const firstPage = pages[0] || { offsets: [], sizes: [], rows: 0 };
        const bufferOffsets = firstPage.offsets;
        const bufferSizes = firstPage.sizes;

        // For multi-page columns (like embeddings), compute total size
        let totalSize = 0;
        for (const page of pages) {
            // Use the data buffer (last buffer, or buffer 1 for nullable)
            const dataIdx = page.sizes.length > 1 ? 1 : 0;
            totalSize += page.sizes[dataIdx] || 0;
        }

        // For nullable columns: buffer 0 = null bitmap, buffer 1 = data
        // For non-nullable: buffer 0 = data
        const dataBufferIdx = bufferOffsets.length > 1 ? 1 : 0;
        const nullBitmapIdx = bufferOffsets.length > 1 ? 0 : -1;

        return {
            offset: bufferOffsets[dataBufferIdx] || 0,
            size: pages.length > 1 ? totalSize : (bufferSizes[dataBufferIdx] || 0),
            rows: totalRows,
            nullBitmapOffset: nullBitmapIdx >= 0 ? bufferOffsets[nullBitmapIdx] : null,
            nullBitmapSize: nullBitmapIdx >= 0 ? bufferSizes[nullBitmapIdx] : null,
            bufferOffsets,
            bufferSizes,
            pages  // Include all pages for multi-page access
        };
    }

    /**
     * Parse string column metadata to get offsets and data buffer info.
     * @private
     */
    _parseStringColumnMeta(bytes) {
        // Parse ALL pages for multi-page string columns
        const pages = [];
        let pos = 0;

        const readVarint = () => {
            let result = 0;
            let shift = 0;
            while (pos < bytes.length) {
                const byte = bytes[pos++];
                result |= (byte & 0x7F) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7;
            }
            return result;
        };

        while (pos < bytes.length) {
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (fieldNum === 2 && wireType === 2) {
                // pages field - parse this page
                const pageLen = readVarint();
                const pageEnd = pos + pageLen;

                let bufferOffsets = [0, 0];
                let bufferSizes = [0, 0];
                let rows = 0;

                while (pos < pageEnd) {
                    const pageTag = readVarint();
                    const pageField = pageTag >> 3;
                    const pageWire = pageTag & 0x7;

                    if (pageField === 1 && pageWire === 2) {
                        // buffer_offsets (packed)
                        const packedLen = readVarint();
                        const packedEnd = pos + packedLen;
                        let idx = 0;
                        while (pos < packedEnd && idx < 2) {
                            bufferOffsets[idx++] = readVarint();
                        }
                        pos = packedEnd;
                    } else if (pageField === 2 && pageWire === 2) {
                        // buffer_sizes (packed)
                        const packedLen = readVarint();
                        const packedEnd = pos + packedLen;
                        let idx = 0;
                        while (pos < packedEnd && idx < 2) {
                            bufferSizes[idx++] = readVarint();
                        }
                        pos = packedEnd;
                    } else if (pageField === 3 && pageWire === 0) {
                        rows = readVarint();
                    } else if (pageField === 4 && pageWire === 2) {
                        // encoding field - skip it
                        const skipLen = readVarint();
                        pos += skipLen;
                    } else {
                        // Unknown field - skip based on wire type
                        if (pageWire === 0) readVarint();
                        else if (pageWire === 2) {
                            const skipLen = readVarint();
                            pos += skipLen;
                        }
                        else if (pageWire === 5) pos += 4;
                        else if (pageWire === 1) pos += 8;
                    }
                }

                pages.push({
                    offsetsStart: bufferOffsets[0],
                    offsetsSize: bufferSizes[0],
                    dataStart: bufferOffsets[1],
                    dataSize: bufferSizes[1],
                    rows
                });
            } else {
                // Skip unknown fields
                if (wireType === 0) {
                    readVarint();
                } else if (wireType === 2) {
                    const skipLen = readVarint();
                    pos += skipLen;
                } else if (wireType === 5) {
                    pos += 4;
                } else if (wireType === 1) {
                    pos += 8;
                }
            }
        }

        // Return first page for backwards compatibility, but also include all pages
        const firstPage = pages[0] || { offsetsStart: 0, offsetsSize: 0, dataStart: 0, dataSize: 0, rows: 0 };
        return {
            ...firstPage,
            pages
        };
    }

    /**
     * Batch indices into contiguous ranges to minimize HTTP requests.
     * Groups nearby indices if the gap is smaller than gapThreshold.
     * @private
     */
    _batchIndices(indices, valueSize, gapThreshold = 1024) {
        if (indices.length === 0) return [];

        // Sort indices for contiguous access
        const sorted = [...indices].map((v, i) => ({ idx: v, origPos: i }));
        sorted.sort((a, b) => a.idx - b.idx);

        const batches = [];
        let batchStart = 0;

        for (let i = 1; i <= sorted.length; i++) {
            // Check if we should end the current batch
            const endBatch = i === sorted.length ||
                (sorted[i].idx - sorted[i-1].idx) * valueSize > gapThreshold;

            if (endBatch) {
                batches.push({
                    startIdx: sorted[batchStart].idx,
                    endIdx: sorted[i-1].idx,
                    items: sorted.slice(batchStart, i)
                });
                batchStart = i;
            }
        }

        return batches;
    }

    /**
     * Read int64 values at specific row indices via Range requests.
     * Uses batched fetching to minimize HTTP requests.
     * @param {number} colIdx
     * @param {number[]} indices - Row indices
     * @returns {Promise<BigInt64Array>}
     */
    async readInt64AtIndices(colIdx, indices) {
        if (indices.length === 0) return new BigInt64Array(0);

        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseColumnMeta(new Uint8Array(colMeta));

        // Debug: console.log(`readInt64AtIndices col ${colIdx}: rows=${info.rows}`);

        const results = new BigInt64Array(indices.length);
        const valueSize = 8;

        // Batch indices into contiguous ranges
        const batches = this._batchIndices(indices, valueSize);

        // Fetch each batch in parallel
        await Promise.all(batches.map(async (batch) => {
            const startOffset = info.offset + batch.startIdx * valueSize;
            const endOffset = info.offset + (batch.endIdx + 1) * valueSize - 1;
            const data = await this.fetchRange(startOffset, endOffset);
            const view = new DataView(data);

            // Extract values from batch
            for (const item of batch.items) {
                const localOffset = (item.idx - batch.startIdx) * valueSize;
                results[item.origPos] = view.getBigInt64(localOffset, true);
            }
        }));

        return results;
    }

    /**
     * Read float64 values at specific row indices via Range requests.
     * Uses batched fetching to minimize HTTP requests.
     * @param {number} colIdx
     * @param {number[]} indices
     * @returns {Promise<Float64Array>}
     */
    async readFloat64AtIndices(colIdx, indices) {
        if (indices.length === 0) return new Float64Array(0);

        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseColumnMeta(new Uint8Array(colMeta));

        const results = new Float64Array(indices.length);
        const valueSize = 8;

        // Batch indices into contiguous ranges
        const batches = this._batchIndices(indices, valueSize);

        // Fetch each batch in parallel
        await Promise.all(batches.map(async (batch) => {
            const startOffset = info.offset + batch.startIdx * valueSize;
            const endOffset = info.offset + (batch.endIdx + 1) * valueSize - 1;
            const data = await this.fetchRange(startOffset, endOffset);
            const view = new DataView(data);

            // Extract values from batch
            for (const item of batch.items) {
                const localOffset = (item.idx - batch.startIdx) * valueSize;
                results[item.origPos] = view.getFloat64(localOffset, true);
            }
        }));

        return results;
    }

    /**
     * Read int32 values at specific row indices via Range requests.
     * @param {number} colIdx
     * @param {number[]} indices
     * @returns {Promise<Int32Array>}
     */
    async readInt32AtIndices(colIdx, indices) {
        if (indices.length === 0) return new Int32Array(0);

        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseColumnMeta(new Uint8Array(colMeta));

        const results = new Int32Array(indices.length);
        const valueSize = 4;

        const batches = this._batchIndices(indices, valueSize);

        await Promise.all(batches.map(async (batch) => {
            const startOffset = info.offset + batch.startIdx * valueSize;
            const endOffset = info.offset + (batch.endIdx + 1) * valueSize - 1;
            const data = await this.fetchRange(startOffset, endOffset);
            const view = new DataView(data);

            for (const item of batch.items) {
                const localOffset = (item.idx - batch.startIdx) * valueSize;
                results[item.origPos] = view.getInt32(localOffset, true);
            }
        }));

        return results;
    }

    /**
     * Read float32 values at specific row indices via Range requests.
     * @param {number} colIdx
     * @param {number[]} indices
     * @returns {Promise<Float32Array>}
     */
    async readFloat32AtIndices(colIdx, indices) {
        if (indices.length === 0) return new Float32Array(0);

        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseColumnMeta(new Uint8Array(colMeta));

        const results = new Float32Array(indices.length);
        const valueSize = 4;

        const batches = this._batchIndices(indices, valueSize);

        await Promise.all(batches.map(async (batch) => {
            const startOffset = info.offset + batch.startIdx * valueSize;
            const endOffset = info.offset + (batch.endIdx + 1) * valueSize - 1;
            const data = await this.fetchRange(startOffset, endOffset);
            const view = new DataView(data);

            for (const item of batch.items) {
                const localOffset = (item.idx - batch.startIdx) * valueSize;
                results[item.origPos] = view.getFloat32(localOffset, true);
            }
        }));

        return results;
    }

    /**
     * Read vectors (fixed_size_list of float32) at specific row indices.
     * Returns array of Float32Array vectors.
     * @param {number} colIdx - Vector column index
     * @param {number[]} indices - Row indices to read
     * @returns {Promise<Float32Array[]>} - Array of vectors
     */
    async readVectorsAtIndices(colIdx, indices) {
        if (indices.length === 0) return [];

        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const metaInfo = this._parseColumnMeta(new Uint8Array(colMeta));

        if (!metaInfo.pages || metaInfo.pages.length === 0) {
            return indices.map(() => null);
        }

        // Calculate dimension from first page
        const firstPage = metaInfo.pages[0];
        const dataIdx = firstPage.sizes.length > 1 ? 1 : 0;
        const firstPageSize = firstPage.sizes[dataIdx] || 0;
        const firstPageRows = firstPage.rows || 0;

        if (firstPageRows === 0 || firstPageSize === 0) {
            return indices.map(() => null);
        }

        const dim = Math.floor(firstPageSize / (firstPageRows * 4));
        const vecSize = dim * 4;

        const results = new Array(indices.length).fill(null);

        // Build page index for quick lookup
        let pageRowStart = 0;
        const pageIndex = [];
        for (const page of metaInfo.pages) {
            pageIndex.push({ start: pageRowStart, end: pageRowStart + page.rows, page });
            pageRowStart += page.rows;
        }

        // Group indices by page
        const pageGroups = new Map();
        for (let i = 0; i < indices.length; i++) {
            const rowIdx = indices[i];
            // Find which page contains this row
            for (let p = 0; p < pageIndex.length; p++) {
                const pi = pageIndex[p];
                if (rowIdx >= pi.start && rowIdx < pi.end) {
                    if (!pageGroups.has(p)) {
                        pageGroups.set(p, []);
                    }
                    pageGroups.set(p, [...pageGroups.get(p), { rowIdx, localIdx: rowIdx - pi.start, resultIdx: i }]);
                    break;
                }
            }
        }

        // Fetch vectors from each page
        const fetchPromises = [];
        for (const [pageNum, items] of pageGroups) {
            const page = metaInfo.pages[pageNum];
            const pageDataIdx = page.sizes.length > 1 ? 1 : 0;
            const pageOffset = page.offsets[pageDataIdx] || 0;

            fetchPromises.push((async () => {
                // Sort items by local index for better batching
                items.sort((a, b) => a.localIdx - b.localIdx);

                // Batch contiguous reads
                const batches = [];
                let currentBatch = { start: items[0].localIdx, end: items[0].localIdx, items: [items[0]] };

                for (let i = 1; i < items.length; i++) {
                    const item = items[i];
                    // If within 10 vectors, extend batch (avoid too many small requests)
                    if (item.localIdx - currentBatch.end <= 10) {
                        currentBatch.end = item.localIdx;
                        currentBatch.items.push(item);
                    } else {
                        batches.push(currentBatch);
                        currentBatch = { start: item.localIdx, end: item.localIdx, items: [item] };
                    }
                }
                batches.push(currentBatch);

                // Fetch each batch
                for (const batch of batches) {
                    const startOffset = pageOffset + batch.start * vecSize;
                    const endOffset = pageOffset + (batch.end + 1) * vecSize - 1;
                    const data = await this.fetchRange(startOffset, endOffset);
                    const floatData = new Float32Array(data);

                    for (const item of batch.items) {
                        const localOffset = (item.localIdx - batch.start) * dim;
                        results[item.resultIdx] = floatData.slice(localOffset, localOffset + dim);
                    }
                }
            })());
        }

        await Promise.all(fetchPromises);
        return results;
    }

    /**
     * Read int16 values at specific row indices via Range requests.
     * @param {number} colIdx
     * @param {number[]} indices
     * @returns {Promise<Int16Array>}
     */
    async readInt16AtIndices(colIdx, indices) {
        if (indices.length === 0) return new Int16Array(0);

        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseColumnMeta(new Uint8Array(colMeta));

        const results = new Int16Array(indices.length);
        const valueSize = 2;

        const batches = this._batchIndices(indices, valueSize);

        await Promise.all(batches.map(async (batch) => {
            const startOffset = info.offset + batch.startIdx * valueSize;
            const endOffset = info.offset + (batch.endIdx + 1) * valueSize - 1;
            const data = await this.fetchRange(startOffset, endOffset);
            const view = new DataView(data);

            for (const item of batch.items) {
                const localOffset = (item.idx - batch.startIdx) * valueSize;
                results[item.origPos] = view.getInt16(localOffset, true);
            }
        }));

        return results;
    }

    /**
     * Read uint8 values at specific row indices via Range requests.
     * @param {number} colIdx
     * @param {number[]} indices
     * @returns {Promise<Uint8Array>}
     */
    async readUint8AtIndices(colIdx, indices) {
        if (indices.length === 0) return new Uint8Array(0);

        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseColumnMeta(new Uint8Array(colMeta));

        const results = new Uint8Array(indices.length);
        const valueSize = 1;

        const batches = this._batchIndices(indices, valueSize);

        await Promise.all(batches.map(async (batch) => {
            const startOffset = info.offset + batch.startIdx * valueSize;
            const endOffset = info.offset + (batch.endIdx + 1) * valueSize - 1;
            const data = await this.fetchRange(startOffset, endOffset);
            const bytes = new Uint8Array(data);

            for (const item of batch.items) {
                const localOffset = item.idx - batch.startIdx;
                results[item.origPos] = bytes[localOffset];
            }
        }));

        return results;
    }

    /**
     * Read bool values at specific row indices via Range requests.
     * Boolean values are bit-packed (8 values per byte).
     * @param {number} colIdx
     * @param {number[]} indices
     * @returns {Promise<Uint8Array>}
     */
    async readBoolAtIndices(colIdx, indices) {
        if (indices.length === 0) return new Uint8Array(0);

        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseColumnMeta(new Uint8Array(colMeta));

        const results = new Uint8Array(indices.length);

        // Calculate byte ranges needed for bit-packed booleans
        const byteIndices = indices.map(i => Math.floor(i / 8));
        const uniqueBytes = [...new Set(byteIndices)].sort((a, b) => a - b);

        if (uniqueBytes.length === 0) return results;

        // Fetch the byte range
        const startByte = uniqueBytes[0];
        const endByte = uniqueBytes[uniqueBytes.length - 1];
        const startOffset = info.offset + startByte;
        const endOffset = info.offset + endByte;
        const data = await this.fetchRange(startOffset, endOffset);
        const bytes = new Uint8Array(data);

        // Extract boolean values
        for (let i = 0; i < indices.length; i++) {
            const idx = indices[i];
            const byteIdx = Math.floor(idx / 8);
            const bitIdx = idx % 8;
            const localByteIdx = byteIdx - startByte;
            if (localByteIdx >= 0 && localByteIdx < bytes.length) {
                results[i] = (bytes[localByteIdx] >> bitIdx) & 1;
            }
        }

        return results;
    }

    /**
     * Read a single string at index via Range requests.
     * @param {number} colIdx
     * @param {number} rowIdx
     * @returns {Promise<string>}
     * @throws {Error} If the column is not a string column
     */
    async readStringAt(colIdx, rowIdx) {
        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseStringColumnMeta(new Uint8Array(colMeta));

        // Check if this is actually a string column
        // String columns have: offsetsSize / rows = 4 or 8 bytes per offset
        // Numeric columns with validity bitmap have: offsetsSize = rows / 8 (bitmap)
        if (info.offsetsSize === 0 || info.dataSize === 0) {
            throw new Error(`Not a string column - offsetsSize=${info.offsetsSize}, dataSize=${info.dataSize}`);
        }

        // Calculate bytes per offset - strings have rows offsets of 4 or 8 bytes each
        const bytesPerOffset = info.offsetsSize / info.rows;

        // If bytesPerOffset is not 4 or 8, this is not a string column
        // (e.g., it's a validity bitmap which has rows/8 bytes = 0.125 bytes per row)
        if (bytesPerOffset !== 4 && bytesPerOffset !== 8) {
            throw new Error(`Not a string column - bytesPerOffset=${bytesPerOffset}, expected 4 or 8`);
        }

        if (rowIdx >= info.rows) return '';

        // Determine offset size (4 or 8 bytes)
        const offsetSize = bytesPerOffset;

        // Fetch the two offsets for this string
        const offsetStart = info.offsetsStart + rowIdx * offsetSize;
        const offsetData = await this.fetchRange(offsetStart, offsetStart + offsetSize * 2 - 1);
        const offsetView = new DataView(offsetData);

        let strStart, strEnd;
        if (offsetSize === 4) {
            strStart = offsetView.getUint32(0, true);
            strEnd = offsetView.getUint32(4, true);
        } else {
            strStart = Number(offsetView.getBigUint64(0, true));
            strEnd = Number(offsetView.getBigUint64(8, true));
        }

        if (strEnd <= strStart) return '';
        const strLen = strEnd - strStart;

        // Fetch the string data
        const strData = await this.fetchRange(
            info.dataStart + strStart,
            info.dataStart + strEnd - 1
        );

        return new TextDecoder().decode(strData);
    }

    /**
     * Read multiple strings at indices via Range requests.
     * Uses batched fetching to minimize HTTP requests.
     * @param {number} colIdx
     * @param {number[]} indices
     * @returns {Promise<string[]>}
     */
    async readStringsAtIndices(colIdx, indices) {
        if (indices.length === 0) return [];

        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseStringColumnMeta(new Uint8Array(colMeta));

        if (!info.pages || info.pages.length === 0) {
            return indices.map(() => '');
        }

        const results = new Array(indices.length).fill('');

        // Build page index with cumulative row counts
        let pageRowStart = 0;
        const pageIndex = [];
        for (const page of info.pages) {
            if (page.offsetsSize === 0 || page.dataSize === 0 || page.rows === 0) {
                pageRowStart += page.rows;
                continue;
            }
            pageIndex.push({
                start: pageRowStart,
                end: pageRowStart + page.rows,
                page
            });
            pageRowStart += page.rows;
        }

        // Group indices by page
        const pageGroups = new Map();
        for (let i = 0; i < indices.length; i++) {
            const rowIdx = indices[i];
            // Find which page contains this row
            for (let p = 0; p < pageIndex.length; p++) {
                const pi = pageIndex[p];
                if (rowIdx >= pi.start && rowIdx < pi.end) {
                    if (!pageGroups.has(p)) {
                        pageGroups.set(p, []);
                    }
                    pageGroups.get(p).push({
                        globalIdx: rowIdx,
                        localIdx: rowIdx - pi.start,
                        resultIdx: i
                    });
                    break;
                }
            }
        }

        // Fetch strings from each page
        for (const [pageNum, items] of pageGroups) {
            const pi = pageIndex[pageNum];
            const page = pi.page;

            // Determine offset size (4 or 8 bytes per offset)
            const offsetSize = page.offsetsSize / page.rows;
            if (offsetSize !== 4 && offsetSize !== 8) continue;

            // Sort items by localIdx for efficient batching
            items.sort((a, b) => a.localIdx - b.localIdx);

            // Fetch offsets in batches
            const offsetBatches = [];
            let batchStart = 0;
            for (let i = 1; i <= items.length; i++) {
                if (i === items.length || items[i].localIdx - items[i-1].localIdx > 100) {
                    offsetBatches.push(items.slice(batchStart, i));
                    batchStart = i;
                }
            }

            // Collect string ranges from offset fetches
            // Lance string encoding: offset[N] = end of string N, start is offset[N-1] (or 0 if N=0)
            const stringRanges = [];

            await Promise.all(offsetBatches.map(async (batch) => {
                const minIdx = batch[0].localIdx;
                const maxIdx = batch[batch.length - 1].localIdx;

                // Fetch offsets: need offset[minIdx-1] through offset[maxIdx]
                // But if minIdx=0, we don't need offset[-1] since start is implicitly 0
                const fetchStartIdx = minIdx > 0 ? minIdx - 1 : 0;
                const fetchEndIdx = maxIdx;
                const startOffset = page.offsetsStart + fetchStartIdx * offsetSize;
                const endOffset = page.offsetsStart + (fetchEndIdx + 1) * offsetSize - 1;
                const data = await this.fetchRange(startOffset, endOffset);
                const view = new DataView(data);

                for (const item of batch) {
                    // Position in fetched data
                    const dataIdx = item.localIdx - fetchStartIdx;
                    let strStart, strEnd;

                    if (offsetSize === 4) {
                        // strEnd = offset[localIdx], strStart = offset[localIdx-1] or 0
                        strEnd = view.getUint32(dataIdx * 4, true);
                        strStart = item.localIdx === 0 ? 0 : view.getUint32((dataIdx - 1) * 4, true);
                    } else {
                        strEnd = Number(view.getBigUint64(dataIdx * 8, true));
                        strStart = item.localIdx === 0 ? 0 : Number(view.getBigUint64((dataIdx - 1) * 8, true));
                    }

                    if (strEnd > strStart) {
                        stringRanges.push({
                            start: strStart,
                            end: strEnd,
                            resultIdx: item.resultIdx,
                            dataStart: page.dataStart
                        });
                    }
                }
            }));

            // Fetch string data
            if (stringRanges.length > 0) {
                stringRanges.sort((a, b) => a.start - b.start);

                // Batch nearby string fetches
                const dataBatches = [];
                let dbStart = 0;
                for (let i = 1; i <= stringRanges.length; i++) {
                    if (i === stringRanges.length ||
                        stringRanges[i].start - stringRanges[i-1].end > 4096) {
                        dataBatches.push({
                            rangeStart: stringRanges[dbStart].start,
                            rangeEnd: stringRanges[i-1].end,
                            items: stringRanges.slice(dbStart, i),
                            dataStart: stringRanges[dbStart].dataStart
                        });
                        dbStart = i;
                    }
                }

                await Promise.all(dataBatches.map(async (batch) => {
                    const data = await this.fetchRange(
                        batch.dataStart + batch.rangeStart,
                        batch.dataStart + batch.rangeEnd - 1
                    );
                    const bytes = new Uint8Array(data);

                    for (const item of batch.items) {
                        const localStart = item.start - batch.rangeStart;
                        const len = item.end - item.start;
                        const strBytes = bytes.slice(localStart, localStart + len);
                        results[item.resultIdx] = new TextDecoder().decode(strBytes);
                    }
                }));
            }
        }

        return results;
    }

    /**
     * Get row count for a column.
     * @param {number} colIdx
     * @returns {Promise<number>}
     */
    async getRowCount(colIdx) {
        const info = await this.getColumnDebugInfo(colIdx);
        return info.rows;
    }

    /**
     * Detect column types by sampling first row.
     * Returns array of type strings: 'string', 'int64', 'float64', 'float32', 'int32', 'int16', 'vector', 'unknown'
     * @returns {Promise<string[]>}
     */
    async detectColumnTypes() {
        // Return cached if available
        if (this._columnTypes) {
            return this._columnTypes;
        }

        const types = [];

        // First, try to use schema types if available
        if (this._schema && this._schema.length > 0) {
            // Schema loaded successfully

            // Build a map from schema - schema may have more fields than physical columns
            for (let c = 0; c < this._numColumns; c++) {
                const schemaField = this._schema[c];
                const schemaType = schemaField?.type?.toLowerCase() || '';
                const schemaName = schemaField?.name?.toLowerCase() || '';
                let type = 'unknown';

                // Debug: console.log(`Column ${c}: name="${schemaField?.name}", type="${schemaType}"`);

                // Check if column name suggests it's a vector/embedding
                const isEmbeddingName = schemaName.includes('embedding') || schemaName.includes('vector') ||
                                        schemaName.includes('emb') || schemaName === 'vec';

                // Map Lance/Arrow logical types to our types
                if (schemaType.includes('utf8') || schemaType.includes('string') || schemaType.includes('large_utf8')) {
                    type = 'string';
                } else if (schemaType.includes('fixed_size_list') || schemaType.includes('vector') || isEmbeddingName) {
                    // Vector detection - check schema type OR column name
                    type = 'vector';
                } else if (schemaType.includes('int64') || schemaType === 'int64') {
                    type = 'int64';
                } else if (schemaType.includes('int32') || schemaType === 'int32') {
                    type = 'int32';
                } else if (schemaType.includes('int16') || schemaType === 'int16') {
                    type = 'int16';
                } else if (schemaType.includes('int8') || schemaType === 'int8') {
                    type = 'int8';
                } else if (schemaType.includes('float64') || schemaType.includes('double')) {
                    type = 'float64';
                } else if (schemaType.includes('float32') || schemaType.includes('float') && !schemaType.includes('64')) {
                    type = 'float32';
                } else if (schemaType.includes('bool')) {
                    type = 'bool';
                }

                types.push(type);
            }

            // If we got useful types from schema, cache and return
            if (types.some(t => t !== 'unknown')) {
                // Debug: console.log('Detected types from schema:', types);
                this._columnTypes = types;
                return types;
            }

            // Otherwise fall through to detection
            // Schema types all unknown, fall back to data detection
            types.length = 0;
        }

        // Fall back to detection by examining data
        // Detecting column types from data
        for (let c = 0; c < this._numColumns; c++) {
            let type = 'unknown';
            const colName = this.columnNames[c]?.toLowerCase() || '';

            // Check if column name suggests it's a vector/embedding
            const isEmbeddingName = colName.includes('embedding') || colName.includes('vector') ||
                                    colName.includes('emb') || colName === 'vec';

            // Try string first - if we can read a valid string, it's a string column
            try {
                const str = await this.readStringAt(c, 0);
                // readStringAt throws for non-string columns, returns string for valid string columns
                type = 'string';
                // Detected as string
                types.push(type);
                continue;
            } catch (e) {
                // Not a string column, continue to numeric detection
            }

            // Check numeric column by examining bytes per row
            try {
                const entry = await this.getColumnOffsetEntry(c);
                if (entry.len > 0) {
                    const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
                    const bytes = new Uint8Array(colMeta);
                    const info = this._parseColumnMeta(bytes);

                    // Debug: console.log(`Column ${c}: bytesPerRow=${info.size / info.rows}`);

                    if (info.rows > 0 && info.size > 0) {
                        const bytesPerRow = info.size / info.rows;

                        // If column name suggests embedding, treat as vector regardless of size
                        if (isEmbeddingName && bytesPerRow >= 4) {
                            type = 'vector';
                        } else if (bytesPerRow === 8) {
                            // int64 or float64 - try to distinguish
                            type = 'int64';  // Default to int64
                        } else if (bytesPerRow === 4) {
                            // int32 or float32 - try reading as int32 to check
                            try {
                                const data = await this.readInt32AtIndices(c, [0]);
                                if (data.length > 0) {
                                    const val = data[0];
                                    // Detected int32 via sample value
                                    // Heuristic: small integers likely int32, weird values likely float32
                                    if (val >= -1000000 && val <= 1000000 && Number.isInteger(val)) {
                                        type = 'int32';
                                    } else {
                                        type = 'float32';
                                    }
                                }
                            } catch (e) {
                                type = 'float32';
                            }
                        } else if (bytesPerRow > 8 && bytesPerRow % 4 === 0) {
                            type = 'vector';
                        } else if (bytesPerRow === 2) {
                            type = 'int16';
                        } else if (bytesPerRow === 1) {
                            type = 'int8';
                        }
                    }
                }
            } catch (e) {
                // Failed to detect type for column, leave as unknown
            }

            // Debug: console.log(`Column ${c}: ${type}`);
            types.push(type);
        }

        this._columnTypes = types;
        return types;
    }

    /**
     * Get cached column metadata, fetching if necessary.
     * @private
     */
    async _getCachedColumnMeta(colIdx) {
        if (this._columnMetaCache.has(colIdx)) {
            return this._columnMetaCache.get(colIdx);
        }

        const entry = await this.getColumnOffsetEntry(colIdx);
        if (entry.len === 0) {
            return null;
        }

        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const bytes = new Uint8Array(colMeta);

        this._columnMetaCache.set(colIdx, bytes);
        return bytes;
    }

    // ========================================================================
    // Vector Column Support (for embeddings/semantic search via Range requests)
    // ========================================================================

    /**
     * Get vector info for a column via Range requests.
     * @param {number} colIdx - Column index
     * @returns {Promise<{rows: number, dimension: number}>}
     */
    async getVectorInfo(colIdx) {
        const entry = await this.getColumnOffsetEntry(colIdx);
        if (entry.len === 0) return { rows: 0, dimension: 0 };

        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseColumnMeta(new Uint8Array(colMeta));

        if (info.rows === 0) return { rows: 0, dimension: 0 };

        // Calculate dimension from first page (all pages have same dimension)
        let dimension = 0;
        if (info.pages && info.pages.length > 0) {
            const firstPage = info.pages[0];
            const dataIdx = firstPage.sizes.length > 1 ? 1 : 0;
            const pageSize = firstPage.sizes[dataIdx] || 0;
            const pageRows = firstPage.rows || 0;
            if (pageRows > 0 && pageSize > 0) {
                dimension = Math.floor(pageSize / (pageRows * 4));
            }
        } else if (info.size > 0) {
            // Fallback for single-page
            dimension = Math.floor(info.size / (info.rows * 4));
        }

        return { rows: info.rows, dimension };
    }

    /**
     * Read a single vector at index via Range requests.
     * @param {number} colIdx - Column index
     * @param {number} rowIdx - Row index
     * @returns {Promise<Float32Array>}
     */
    async readVectorAt(colIdx, rowIdx) {
        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseColumnMeta(new Uint8Array(colMeta));

        if (info.rows === 0) return new Float32Array(0);
        if (rowIdx >= info.rows) return new Float32Array(0);

        const dim = Math.floor(info.size / (info.rows * 4));
        if (dim === 0) return new Float32Array(0);

        // Fetch the vector data
        const vecStart = info.offset + rowIdx * dim * 4;
        const vecEnd = vecStart + dim * 4 - 1;
        const data = await this.fetchRange(vecStart, vecEnd);

        return new Float32Array(data);
    }

    /**
     * Read multiple vectors at indices via Range requests.
     * Uses batched fetching for efficiency.
     * @param {number} colIdx - Column index
     * @param {number[]} indices - Row indices
     * @returns {Promise<Float32Array[]>}
     */
    async readVectorsAtIndices(colIdx, indices) {
        if (indices.length === 0) return [];

        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const info = this._parseColumnMeta(new Uint8Array(colMeta));

        if (info.rows === 0) return indices.map(() => new Float32Array(0));

        const dim = Math.floor(info.size / (info.rows * 4));
        if (dim === 0) return indices.map(() => new Float32Array(0));

        const vecSize = dim * 4;
        const results = new Array(indices.length);

        // Batch indices for efficient fetching - parallel with limit
        const batches = this._batchIndices(indices, vecSize, vecSize * 50);
        const BATCH_PARALLEL = 6;

        for (let i = 0; i < batches.length; i += BATCH_PARALLEL) {
            const batchGroup = batches.slice(i, i + BATCH_PARALLEL);
            await Promise.all(batchGroup.map(async (batch) => {
                try {
                    const startOffset = info.offset + batch.startIdx * vecSize;
                    const endOffset = info.offset + (batch.endIdx + 1) * vecSize - 1;
                    const data = await this.fetchRange(startOffset, endOffset);

                    for (const item of batch.items) {
                        const localOffset = (item.idx - batch.startIdx) * vecSize;
                        results[item.origPos] = new Float32Array(
                            data.slice(localOffset, localOffset + vecSize)
                        );
                    }
                } catch (e) {
                    for (const item of batch.items) {
                        results[item.origPos] = new Float32Array(0);
                    }
                }
            }));
        }

        return results;
    }

    /**
     * Compute cosine similarity between two vectors (in JS).
     * @param {Float32Array} vecA
     * @param {Float32Array} vecB
     * @returns {number}
     */
    cosineSimilarity(vecA, vecB) {
        if (vecA.length !== vecB.length) return 0;

        let dot = 0, normA = 0, normB = 0;
        for (let i = 0; i < vecA.length; i++) {
            dot += vecA[i] * vecB[i];
            normA += vecA[i] * vecA[i];
            normB += vecB[i] * vecB[i];
        }

        const denom = Math.sqrt(normA) * Math.sqrt(normB);
        return denom === 0 ? 0 : dot / denom;
    }

    /**
     * Find top-k most similar vectors to query via Range requests.
     * NOTE: This requires scanning the entire vector column which can be slow
     * for large datasets. For production, use an index.
     *
     * @param {number} colIdx - Column index with vectors
     * @param {Float32Array} queryVec - Query vector
     * @param {number} topK - Number of results to return
     * @param {function} onProgress - Progress callback(current, total)
     * @param {object} options - Search options
     * @param {number} options.nprobe - Number of partitions to search (for ANN)
     * @param {boolean} options.useIndex - Whether to use ANN index if available
     * @returns {Promise<{indices: number[], scores: number[], useIndex: boolean}>}
     */
    async vectorSearch(colIdx, queryVec, topK = 10, onProgress = null, options = {}) {
        const { nprobe = 10, useIndex = true } = options;

        const info = await this.getVectorInfo(colIdx);
        if (info.dimension === 0 || info.dimension !== queryVec.length) {
            throw new Error(`Dimension mismatch: query=${queryVec.length}, column=${info.dimension}`);
        }

        // Require IVF index - no brute force fallback
        if (!this.hasIndex()) {
            throw new Error('No IVF index found. Vector search requires an IVF index for efficient querying.');
        }

        if (this._ivfIndex.dimension !== queryVec.length) {
            throw new Error(`Query dimension (${queryVec.length}) does not match index dimension (${this._ivfIndex.dimension}).`);
        }

        return await this._vectorSearchWithIndex(colIdx, queryVec, topK, nprobe, onProgress);
    }

    /**
     * Vector search using IVF index (ANN).
     * Fetches row IDs from auxiliary.idx for nearest partitions,
     * then looks up original vectors by fragment/offset.
     * @private
     */
    async _vectorSearchWithIndex(colIdx, queryVec, topK, nprobe, onProgress) {
        const dim = queryVec.length;

        // Find nearest partitions using centroids
        if (onProgress) onProgress(0, 100);
        const partitions = this._ivfIndex.findNearestPartitions(queryVec, nprobe);
        const estimatedRows = this._ivfIndex.getPartitionRowCount(partitions);

        console.log(`[IVFSearch] Searching ${partitions.length} partitions (~${estimatedRows.toLocaleString()} rows)`);

        // Try to fetch row IDs from auxiliary.idx
        const rowIdMappings = await this._ivfIndex.fetchPartitionRowIds(partitions);

        if (rowIdMappings && rowIdMappings.length > 0) {
            // Use proper row ID mapping from auxiliary.idx
            console.log(`[IVFSearch] Fetched ${rowIdMappings.length} row ID mappings`);
            return await this._searchWithRowIdMappings(colIdx, queryVec, topK, rowIdMappings, onProgress);
        }

        // No fallback - require proper row ID mapping
        throw new Error('Failed to fetch row IDs from IVF index. Dataset may be missing auxiliary.idx or ivf_partitions.bin.');
    }

    /**
     * Search using proper row ID mappings from auxiliary.idx.
     * Groups row IDs by fragment and fetches vectors efficiently.
     * @private
     */
    async _searchWithRowIdMappings(colIdx, queryVec, topK, rowIdMappings, onProgress) {
        const dim = queryVec.length;

        // Group row IDs by fragment for efficient batch fetching
        const byFragment = new Map();
        for (const mapping of rowIdMappings) {
            if (!byFragment.has(mapping.fragId)) {
                byFragment.set(mapping.fragId, []);
            }
            byFragment.get(mapping.fragId).push(mapping.rowOffset);
        }

        console.log(`[IVFSearch] Fetching from ${byFragment.size} fragments`);

        const topResults = [];
        let processed = 0;
        const total = rowIdMappings.length;

        // Process each fragment
        for (const [fragId, offsets] of byFragment) {
            if (onProgress) onProgress(processed, total);

            // Fetch vectors for this fragment's offsets
            const vectors = await this.readVectorsAtIndices(colIdx, offsets);

            for (let i = 0; i < offsets.length; i++) {
                const vec = vectors[i];
                if (!vec || vec.length !== dim) continue;

                // Compute cosine similarity
                let dot = 0, normA = 0, normB = 0;
                for (let k = 0; k < dim; k++) {
                    dot += queryVec[k] * vec[k];
                    normA += queryVec[k] * queryVec[k];
                    normB += vec[k] * vec[k];
                }
                const denom = Math.sqrt(normA) * Math.sqrt(normB);
                const score = denom === 0 ? 0 : dot / denom;

                // Reconstruct global row index from fragment ID and offset
                const globalIdx = fragId * 50000 + offsets[i]; // Assuming 50K rows per fragment

                if (topResults.length < topK) {
                    topResults.push({ idx: globalIdx, score });
                    topResults.sort((a, b) => b.score - a.score);
                } else if (score > topResults[topK - 1].score) {
                    topResults[topK - 1] = { idx: globalIdx, score };
                    topResults.sort((a, b) => b.score - a.score);
                }

                processed++;
            }
        }

        if (onProgress) onProgress(total, total);

        return {
            indices: topResults.map(r => r.idx),
            scores: topResults.map(r => r.score),
            usedIndex: true,
            searchedRows: total
        };
    }

    // NOTE: _searchWithEstimatedPartitions and _vectorSearchBruteForce have been removed.
    // All vector search now requires IVF index with proper partition mapping.
    // Use LanceDataset for multi-fragment datasets with ivf_partitions.bin.

    /**
     * Read all vectors from a column as a flat Float32Array.
     * Used for worker-based parallel search.
     * Handles multi-page columns by fetching and combining all pages.
     * @param {number} colIdx - Vector column index
     * @returns {Promise<Float32Array>} - Flattened vector data [numRows * dim]
     */
    async readVectorColumn(colIdx) {
        const entry = await this.getColumnOffsetEntry(colIdx);
        const colMeta = await this.fetchRange(entry.pos, entry.pos + entry.len - 1);
        const metaInfo = this._parseColumnMeta(new Uint8Array(colMeta));

        if (!metaInfo.pages || metaInfo.pages.length === 0 || metaInfo.rows === 0) {
            return new Float32Array(0);
        }

        // Calculate dimension from first page
        const firstPage = metaInfo.pages[0];
        const dataIdx = firstPage.sizes.length > 1 ? 1 : 0;
        const firstPageSize = firstPage.sizes[dataIdx] || 0;
        const firstPageRows = firstPage.rows || 0;

        if (firstPageRows === 0 || firstPageSize === 0) {
            return new Float32Array(0);
        }

        const dim = Math.floor(firstPageSize / (firstPageRows * 4));
        if (dim === 0) {
            return new Float32Array(0);
        }

        const totalRows = metaInfo.rows;
        const result = new Float32Array(totalRows * dim);

        // Fetch each page in parallel
        const pagePromises = metaInfo.pages.map(async (page, pageIdx) => {
            const pageDataIdx = page.sizes.length > 1 ? 1 : 0;
            const pageOffset = page.offsets[pageDataIdx] || 0;
            const pageSize = page.sizes[pageDataIdx] || 0;

            if (pageSize === 0) return { pageIdx, data: new Float32Array(0), rows: 0 };

            const data = await this.fetchRange(pageOffset, pageOffset + pageSize - 1);
            // data is ArrayBuffer from fetchRange, create Float32Array view directly
            const floatData = new Float32Array(data);
            return {
                pageIdx,
                data: floatData,
                rows: page.rows
            };
        });

        const pageResults = await Promise.all(pagePromises);

        // Combine pages in order
        let offset = 0;
        for (const pageResult of pageResults.sort((a, b) => a.pageIdx - b.pageIdx)) {
            result.set(pageResult.data, offset);
            offset += pageResult.rows * dim;
        }

        return result;
    }
}

// ============================================================================
// ANN/IVF Index Support
// ============================================================================

/**
 * IVF (Inverted File Index) for Approximate Nearest Neighbor search.
 * Stores centroids and partition info to enable fast vector search
 * by only scanning relevant partitions instead of the entire dataset.
 */
export class IVFIndex {
    constructor() {
        this.centroids = null;       // Float32Array of centroids (numPartitions x dimension)
        this.numPartitions = 0;      // Number of IVF partitions
        this.dimension = 0;          // Vector dimension
        this.partitionOffsets = [];  // Byte offset of each partition in the data
        this.partitionLengths = [];  // Number of rows in each partition
        this.metricType = 'cosine';  // Distance metric (cosine, l2, dot)

        // Custom partition index (ivf_partitions.bin)
        this.partitionIndexUrl = null;  // URL to ivf_partitions.bin
        this.partitionStarts = null;    // Uint32Array[257] - cumulative row counts
        this.hasPartitionIndex = false; // Whether partition index is loaded
    }

    /**
     * Try to load IVF index from a Lance dataset.
     * Index structure: dataset.lance/_indices/<uuid>/index.idx
     * @param {string} datasetBaseUrl - Base URL of dataset (e.g., https://host/data.lance)
     * @returns {Promise<IVFIndex|null>}
     */
    static async tryLoad(datasetBaseUrl) {
        if (!datasetBaseUrl) return null;

        try {
            // Find latest manifest version
            const manifestVersion = await IVFIndex._findLatestManifestVersion(datasetBaseUrl);
            console.log(`[IVFIndex] Manifest version: ${manifestVersion}`);
            if (!manifestVersion) return null;

            const manifestUrl = `${datasetBaseUrl}/_versions/${manifestVersion}.manifest`;
            const manifestResp = await fetch(manifestUrl);
            if (!manifestResp.ok) {
                console.log(`[IVFIndex] Failed to fetch manifest: ${manifestResp.status}`);
                return null;
            }

            const manifestData = await manifestResp.arrayBuffer();
            const indexInfo = IVFIndex._parseManifestForIndex(new Uint8Array(manifestData));
            console.log(`[IVFIndex] Index info:`, indexInfo);

            if (!indexInfo || !indexInfo.uuid) {
                // No vector index found in manifest
                console.log('[IVFIndex] No index UUID found in manifest');
                return null;
            }

            console.log(`[IVFIndex] Found index UUID: ${indexInfo.uuid}`);

            // Fetch the index file (contains centroids)
            const indexUrl = `${datasetBaseUrl}/_indices/${indexInfo.uuid}/index.idx`;
            const indexResp = await fetch(indexUrl);
            if (!indexResp.ok) {
                console.warn('[IVFIndex] index.idx not found');
                return null;
            }

            const indexData = await indexResp.arrayBuffer();
            const index = IVFIndex._parseIndexFile(new Uint8Array(indexData), indexInfo);

            if (!index) return null;

            // Store auxiliary URL for later partition data fetching
            index.auxiliaryUrl = `${datasetBaseUrl}/_indices/${indexInfo.uuid}/auxiliary.idx`;
            index.datasetBaseUrl = datasetBaseUrl;

            // Fetch auxiliary.idx metadata (footer + partition info)
            // We only need the last ~13MB which has the partition metadata
            try {
                await index._loadAuxiliaryMetadata();
            } catch (e) {
                console.warn('[IVFIndex] Failed to load auxiliary metadata:', e);
            }

            console.log(`[IVFIndex] Loaded: ${index.numPartitions} partitions, dim=${index.dimension}`);
            if (index.partitionLengths.length > 0) {
                const totalRows = index.partitionLengths.reduce((a, b) => a + b, 0);
                console.log(`[IVFIndex] Partition info: ${totalRows.toLocaleString()} total rows`);
            }

            // Try to load custom partition index (ivf_partitions.bin)
            try {
                await index._loadPartitionIndex();
            } catch (e) {
                console.warn('[IVFIndex] Failed to load partition index:', e);
            }

            return index;
        } catch (e) {
            console.warn('[IVFIndex] Failed to load:', e);
            return null;
        }
    }

    /**
     * Load partition-organized vectors index from ivf_vectors.bin.
     * This file contains:
     *   - Header: 257 uint64 byte offsets (2056 bytes)
     *   - Per partition: [row_count: uint32][row_ids: uint32 × n][vectors: float32 × n × 384]
     * @private
     */
    async _loadPartitionIndex() {
        const url = `${this.datasetBaseUrl}/ivf_vectors.bin`;
        this.partitionVectorsUrl = url;

        // Fetch header (257 uint64s = 2056 bytes)
        const headerResp = await fetch(url, {
            headers: { 'Range': 'bytes=0-2055' }
        });
        if (!headerResp.ok) {
            console.log('[IVFIndex] ivf_vectors.bin not found, IVF search disabled');
            return;
        }

        const headerData = await headerResp.arrayBuffer();
        // Parse as BigUint64Array then convert to regular numbers
        const bigOffsets = new BigUint64Array(headerData);
        this.partitionOffsets = Array.from(bigOffsets, n => Number(n));

        this.hasPartitionIndex = true;
        console.log(`[IVFIndex] Loaded partition vectors index: 256 partitions`);
    }

    /**
     * Fetch partition data (row IDs and vectors) directly from ivf_vectors.bin.
     * Each partition contains: [row_count: uint32][row_ids: uint32 × n][vectors: float32 × n × dim]
     * @param {number[]} partitionIndices - Partition indices to fetch
     * @param {number} dim - Vector dimension (default 384)
     * @param {function} onProgress - Progress callback (bytesLoaded, totalBytes)
     * @returns {Promise<{rowIds: number[], vectors: Float32Array[]}>}
     */
    async fetchPartitionData(partitionIndices, dim = 384, onProgress = null) {
        if (!this.hasPartitionIndex || !this.partitionVectorsUrl) {
            return null;
        }

        const allRowIds = [];
        const allVectors = [];
        let totalBytesToFetch = 0;
        let bytesLoaded = 0;

        // Calculate total bytes for progress reporting
        for (const p of partitionIndices) {
            const startOffset = this.partitionOffsets[p];
            const endOffset = this.partitionOffsets[p + 1];
            totalBytesToFetch += endOffset - startOffset;
        }

        console.log(`[IVFIndex] Fetching ${partitionIndices.length} partitions, ${(totalBytesToFetch / 1024 / 1024).toFixed(1)} MB total`);

        // Fetch partitions in parallel (max 4 concurrent)
        const PARALLEL_LIMIT = 4;
        for (let i = 0; i < partitionIndices.length; i += PARALLEL_LIMIT) {
            const batch = partitionIndices.slice(i, i + PARALLEL_LIMIT);

            const results = await Promise.all(batch.map(async (p) => {
                const startOffset = this.partitionOffsets[p];
                const endOffset = this.partitionOffsets[p + 1];
                const byteSize = endOffset - startOffset;

                try {
                    const resp = await fetch(this.partitionVectorsUrl, {
                        headers: { 'Range': `bytes=${startOffset}-${endOffset - 1}` }
                    });
                    if (!resp.ok) {
                        console.warn(`[IVFIndex] Partition ${p} fetch failed: ${resp.status}`);
                        return { rowIds: [], vectors: [] };
                    }

                    const data = await resp.arrayBuffer();
                    const view = new DataView(data);

                    // Parse: [row_count: uint32][row_ids: uint32 × n][vectors: float32 × n × dim]
                    const rowCount = view.getUint32(0, true);  // little-endian
                    const rowIdsStart = 4;
                    const rowIdsEnd = rowIdsStart + rowCount * 4;
                    const vectorsStart = rowIdsEnd;

                    const rowIds = new Uint32Array(data.slice(rowIdsStart, rowIdsEnd));
                    const vectorsFlat = new Float32Array(data.slice(vectorsStart));

                    // Split flat vectors into individual arrays
                    const vectors = [];
                    for (let j = 0; j < rowCount; j++) {
                        vectors.push(vectorsFlat.slice(j * dim, (j + 1) * dim));
                    }

                    bytesLoaded += byteSize;
                    if (onProgress) onProgress(bytesLoaded, totalBytesToFetch);

                    return { rowIds: Array.from(rowIds), vectors };
                } catch (e) {
                    console.warn(`[IVFIndex] Error fetching partition ${p}:`, e);
                    return { rowIds: [], vectors: [] };
                }
            }));

            // Collect results
            for (const result of results) {
                allRowIds.push(...result.rowIds);
                allVectors.push(...result.vectors);
            }
        }

        console.log(`[IVFIndex] Loaded ${allRowIds.length.toLocaleString()} vectors from ${partitionIndices.length} partitions`);
        return { rowIds: allRowIds, vectors: allVectors };
    }

    /**
     * Find latest manifest version using binary search.
     * @private
     */
    static async _findLatestManifestVersion(baseUrl) {
        // Check common versions in parallel
        const checkVersions = [1, 5, 10, 20, 50, 100];
        const checks = await Promise.all(
            checkVersions.map(async v => {
                try {
                    const url = `${baseUrl}/_versions/${v}.manifest`;
                    const response = await fetch(url, { method: 'HEAD' });
                    return response.ok ? v : 0;
                } catch {
                    return 0;
                }
            })
        );

        let highestFound = Math.max(...checks);
        if (highestFound === 0) return null;

        // Scan forward from highest found
        for (let v = highestFound + 1; v <= highestFound + 30; v++) {
            try {
                const url = `${baseUrl}/_versions/${v}.manifest`;
                const response = await fetch(url, { method: 'HEAD' });
                if (response.ok) {
                    highestFound = v;
                } else {
                    break;
                }
            } catch {
                break;
            }
        }

        return highestFound;
    }

    /**
     * Load partition metadata from auxiliary.idx.
     * Uses HTTP range request to fetch only the metadata section.
     * @private
     */
    async _loadAuxiliaryMetadata() {
        // Fetch file size first
        let headResp;
        try {
            headResp = await fetch(this.auxiliaryUrl, { method: 'HEAD' });
        } catch (e) {
            console.warn('[IVFIndex] HEAD request failed for auxiliary.idx:', e.message);
            return;
        }
        if (!headResp.ok) return;

        const fileSize = parseInt(headResp.headers.get('content-length'));
        if (!fileSize) return;

        // Fetch footer (last 40 bytes) to get metadata locations
        const footerResp = await fetch(this.auxiliaryUrl, {
            headers: { 'Range': `bytes=${fileSize - 40}-${fileSize - 1}` }
        });
        if (!footerResp.ok) return;

        const footer = new Uint8Array(await footerResp.arrayBuffer());
        const view = new DataView(footer.buffer, footer.byteOffset);

        // Parse Lance footer (40 bytes)
        // Bytes 0-7: column_meta_start
        // Bytes 8-15: column_meta_offsets_start
        // Bytes 16-23: global_buff_offsets_start
        // Bytes 24-27: num_global_buffers
        // Bytes 28-31: num_columns
        // Bytes 32-33: major_version
        // Bytes 34-35: minor_version
        // Bytes 36-39: magic "LANC"
        const colMetaStart = Number(view.getBigUint64(0, true));
        const colMetaOffsetsStart = Number(view.getBigUint64(8, true));
        const globalBuffOffsetsStart = Number(view.getBigUint64(16, true));
        const numGlobalBuffers = view.getUint32(24, true);
        const numColumns = view.getUint32(28, true);
        const magic = new TextDecoder().decode(footer.slice(36, 40));

        if (magic !== 'LANC') {
            console.warn('[IVFIndex] Invalid auxiliary.idx magic');
            return;
        }

        console.log(`[IVFIndex] Footer: colMetaStart=${colMetaStart}, colMetaOffsetsStart=${colMetaOffsetsStart}, globalBuffOffsetsStart=${globalBuffOffsetsStart}, numGlobalBuffers=${numGlobalBuffers}, numColumns=${numColumns}`);

        // Fetch global buffer offsets (each buffer has offset + length = 16 bytes)
        const gboSize = numGlobalBuffers * 16;
        const gboResp = await fetch(this.auxiliaryUrl, {
            headers: { 'Range': `bytes=${globalBuffOffsetsStart}-${globalBuffOffsetsStart + gboSize - 1}` }
        });
        if (!gboResp.ok) return;

        const gboData = new Uint8Array(await gboResp.arrayBuffer());
        const gboView = new DataView(gboData.buffer, gboData.byteOffset);

        // Global buffer offsets are stored as [offset, length] pairs
        // Each buffer has: offset (8 bytes) + length (8 bytes) = 16 bytes per buffer
        const buffers = [];
        for (let i = 0; i < numGlobalBuffers; i++) {
            const offset = Number(gboView.getBigUint64(i * 16, true));
            const length = Number(gboView.getBigUint64(i * 16 + 8, true));
            buffers.push({ offset, length });
        }

        console.log(`[IVFIndex] Buffers:`, buffers);

        // Buffer 1 contains row IDs (_rowid column data)
        // Buffer 2 contains PQ codes (__pq_code column data)
        // We need buffer 1 for row ID lookups
        if (buffers.length < 2) return;

        // Store buffer info for later use
        this._auxBuffers = buffers;
        this._auxFileSize = fileSize;

        // Now we need to fetch partition metadata from column metadata
        // The auxiliary.idx stores _rowid and __pq_code columns
        // Partition info (offsets, lengths) is in the column metadata section
        // For now, we'll compute partition info from the row ID buffer
        // Each partition's row IDs are stored contiguously

        // We need to parse column metadata to get partition boundaries
        // Column metadata is at col_meta_start, with offsets at col_meta_off_start
        const colMetaOffResp = await fetch(this.auxiliaryUrl, {
            headers: { 'Range': `bytes=${colMetaOffsetsStart}-${globalBuffOffsetsStart - 1}` }
        });
        if (!colMetaOffResp.ok) return;

        const colMetaOffData = new Uint8Array(await colMetaOffResp.arrayBuffer());
        // Parse column offset entries (16 bytes each: 8 byte pos + 8 byte len)
        // We have 2 columns: _rowid and __pq_code
        if (colMetaOffData.length >= 32) {
            const colView = new DataView(colMetaOffData.buffer, colMetaOffData.byteOffset);
            const col0Pos = Number(colView.getBigUint64(0, true));
            const col0Len = Number(colView.getBigUint64(8, true));
            console.log(`[IVFIndex] Column 0 (_rowid) metadata at ${col0Pos}, len=${col0Len}`);

            // Fetch column 0 metadata to get page info
            const col0MetaResp = await fetch(this.auxiliaryUrl, {
                headers: { 'Range': `bytes=${col0Pos}-${col0Pos + col0Len - 1}` }
            });
            if (col0MetaResp.ok) {
                const col0Meta = new Uint8Array(await col0MetaResp.arrayBuffer());
                this._parseColumnMetaForPartitions(col0Meta);
            }
        }
    }

    /**
     * Parse column metadata to extract partition (page) boundaries.
     * @private
     */
    _parseColumnMetaForPartitions(bytes) {
        let pos = 0;
        const pages = [];

        const readVarint = () => {
            let result = 0;
            let shift = 0;
            while (pos < bytes.length) {
                const byte = bytes[pos++];
                result |= (byte & 0x7F) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7;
            }
            return result;
        };

        // Parse protobuf to find pages
        while (pos < bytes.length) {
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (wireType === 2) {
                const len = readVarint();
                if (len > bytes.length - pos) break;
                const content = bytes.slice(pos, pos + len);
                pos += len;

                // Field 2 = pages (PageInfo)
                if (fieldNum === 2) {
                    const page = this._parsePageInfo(content);
                    if (page) pages.push(page);
                }
            } else if (wireType === 0) {
                readVarint();
            } else if (wireType === 5) {
                pos += 4;
            } else if (wireType === 1) {
                pos += 8;
            }
        }

        console.log(`[IVFIndex] Found ${pages.length} column pages`);

        // Store page info for row ID lookups
        // Note: partition info should come from index.idx, not column pages
        // Column pages are how data is stored, partitions are the IVF clusters
        this._columnPages = pages;

        // Calculate total rows for verification
        let totalRows = 0;
        for (const page of pages) {
            totalRows += page.numRows;
        }
        console.log(`[IVFIndex] Column has ${totalRows} total rows`);
    }

    /**
     * Parse PageInfo protobuf.
     * @private
     */
    _parsePageInfo(bytes) {
        let pos = 0;
        let numRows = 0;
        const bufferOffsets = [];
        const bufferSizes = [];

        const readVarint = () => {
            let result = 0;
            let shift = 0;
            while (pos < bytes.length) {
                const byte = bytes[pos++];
                result |= (byte & 0x7F) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7;
            }
            return result;
        };

        while (pos < bytes.length) {
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (wireType === 0) {
                const val = readVarint();
                if (fieldNum === 3) numRows = val;  // length field
            } else if (wireType === 2) {
                const len = readVarint();
                const content = bytes.slice(pos, pos + len);
                pos += len;

                // Field 1 = buffer_offsets (packed uint64)
                if (fieldNum === 1) {
                    let p = 0;
                    while (p < content.length) {
                        let val = 0n;
                        let shift = 0n;
                        while (p < content.length) {
                            const b = content[p++];
                            val |= BigInt(b & 0x7F) << shift;
                            if ((b & 0x80) === 0) break;
                            shift += 7n;
                        }
                        bufferOffsets.push(Number(val));
                    }
                }
                // Field 2 = buffer_sizes (packed uint64)
                if (fieldNum === 2) {
                    let p = 0;
                    while (p < content.length) {
                        let val = 0n;
                        let shift = 0n;
                        while (p < content.length) {
                            const b = content[p++];
                            val |= BigInt(b & 0x7F) << shift;
                            if ((b & 0x80) === 0) break;
                            shift += 7n;
                        }
                        bufferSizes.push(Number(val));
                    }
                }
            } else if (wireType === 5) {
                pos += 4;
            } else if (wireType === 1) {
                pos += 8;
            }
        }

        return { numRows, bufferOffsets, bufferSizes };
    }

    /**
     * Parse partition offsets and lengths from auxiliary.idx metadata.
     * @private
     */
    _parseAuxiliaryPartitionInfo(bytes) {
        let pos = 0;

        const readVarint = () => {
            let result = 0;
            let shift = 0;
            while (pos < bytes.length) {
                const byte = bytes[pos++];
                result |= (byte & 0x7F) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7;
            }
            return result;
        };

        // Parse protobuf structure
        while (pos < bytes.length - 4) {
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (wireType === 2) {
                const len = readVarint();
                if (len > bytes.length - pos) break;

                const content = bytes.slice(pos, pos + len);
                pos += len;

                if (fieldNum === 2 && len > 100 && len < 2000) {
                    // Partition offsets (varint-encoded)
                    const offsets = [];
                    let innerPos = 0;
                    while (innerPos < content.length) {
                        let val = 0, shift = 0;
                        while (innerPos < content.length) {
                            const byte = content[innerPos++];
                            val |= (byte & 0x7F) << shift;
                            if ((byte & 0x80) === 0) break;
                            shift += 7;
                        }
                        offsets.push(val);
                    }
                    if (offsets.length === this.numPartitions) {
                        this.partitionOffsets = offsets;
                        console.log(`[IVFIndex] Loaded ${offsets.length} partition offsets`);
                    }
                } else if (fieldNum === 3 && len > 100 && len < 2000) {
                    // Partition lengths (varint-encoded)
                    const lengths = [];
                    let innerPos = 0;
                    while (innerPos < content.length) {
                        let val = 0, shift = 0;
                        while (innerPos < content.length) {
                            const byte = content[innerPos++];
                            val |= (byte & 0x7F) << shift;
                            if ((byte & 0x80) === 0) break;
                            shift += 7;
                        }
                        lengths.push(val);
                    }
                    if (lengths.length === this.numPartitions) {
                        this.partitionLengths = lengths;
                        console.log(`[IVFIndex] Loaded ${lengths.length} partition lengths`);
                    }
                }
            } else if (wireType === 0) {
                readVarint();
            } else if (wireType === 1) {
                pos += 8;
            } else if (wireType === 5) {
                pos += 4;
            } else {
                break;
            }
        }
    }

    /**
     * Fetch row IDs for specified partitions from auxiliary.idx.
     * Returns array of decoded row IDs (as {fragId, rowOffset} pairs).
     *
     * The auxiliary.idx data region layout for each row:
     * - Column 0: _rowid (uint64) - 8 bytes per row
     * - Column 1: __pq_code (64 uint8s) - 64 bytes per row
     * Total: 72 bytes per row if stored contiguously
     *
     * However, Lance stores columns separately, so we need to read
     * just the _rowid column data.
     *
     * @param {number[]} partitionIndices - Partition indices to fetch
     * @returns {Promise<Array<{fragId: number, rowOffset: number}>>}
     */
    async fetchPartitionRowIds(partitionIndices) {
        if (!this.auxiliaryUrl || !this._auxBufferOffsets) {
            return null;
        }

        // Calculate total rows to fetch and their byte ranges
        const rowRanges = [];
        for (const p of partitionIndices) {
            if (p < this.partitionOffsets.length) {
                const startRow = this.partitionOffsets[p];
                const numRows = this.partitionLengths[p];
                rowRanges.push({ partition: p, startRow, numRows });
            }
        }

        if (rowRanges.length === 0) return [];

        // The data region starts at bufferOffsets[1]
        // auxiliary.idx stores _rowid as uint64 (8 bytes each)
        // Data is stored with _rowid column first, then __pq_code column
        // We only need _rowid values

        // First, get the _rowid column metadata from auxiliary.idx footer
        // For now, use a simpler approach: assume row IDs are stored at
        // (dataStart + rowIndex * 8) for each row in the partition order

        // Note: This is a simplification. Full implementation would parse
        // the column encoding from auxiliary.idx metadata.

        const results = [];
        const dataStart = this._auxBufferOffsets[1];

        // Fetch row IDs in batches
        for (const range of rowRanges) {
            // Calculate byte offset for this partition's row IDs
            // Row IDs are at the start of the data region
            const byteStart = dataStart + range.startRow * 8;
            const byteEnd = byteStart + range.numRows * 8 - 1;

            try {
                const resp = await fetch(this.auxiliaryUrl, {
                    headers: { 'Range': `bytes=${byteStart}-${byteEnd}` }
                });

                if (!resp.ok) {
                    console.warn(`[IVFIndex] Failed to fetch row IDs for partition ${range.partition}`);
                    continue;
                }

                const data = new Uint8Array(await resp.arrayBuffer());
                const view = new DataView(data.buffer, data.byteOffset);

                for (let i = 0; i < range.numRows; i++) {
                    const rowId = Number(view.getBigUint64(i * 8, true));
                    // Decode Lance row ID: fragId = rowId >> 32, rowOffset = rowId & 0xFFFFFFFF
                    const fragId = Math.floor(rowId / 0x100000000);
                    const rowOffset = rowId % 0x100000000;
                    results.push({ fragId, rowOffset, partition: range.partition });
                }
            } catch (e) {
                console.warn(`[IVFIndex] Error fetching partition ${range.partition}:`, e);
            }
        }

        return results;
    }

    /**
     * Get estimated number of rows to search for given partitions.
     */
    getPartitionRowCount(partitionIndices) {
        let total = 0;
        for (const p of partitionIndices) {
            if (p < this.partitionLengths.length) {
                total += this.partitionLengths[p];
            }
        }
        return total;
    }

    /**
     * Parse manifest to find vector index info.
     * @private
     */
    static _parseManifestForIndex(bytes) {
        // Manifest structure:
        // - Chunk 1: 4 bytes len + content (index metadata in field 1)
        // - Chunk 2: 4 bytes len + content (full manifest with schema + fragments)
        // - Footer (16 bytes)
        //
        // Index info is in CHUNK 1, field 1 (IndexMetadata repeated)

        const view = new DataView(bytes.buffer, bytes.byteOffset);
        const chunk1Len = view.getUint32(0, true);
        const chunk1Data = bytes.slice(4, 4 + chunk1Len);

        let pos = 0;
        let indexUuid = null;
        let indexFieldId = null;

        const readVarint = (data, startPos) => {
            let result = 0;
            let shift = 0;
            let p = startPos;
            while (p < data.length) {
                const byte = data[p++];
                result |= (byte & 0x7F) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7;
            }
            return { value: result, pos: p };
        };

        // Parse chunk 1 looking for index metadata (field 1)
        while (pos < chunk1Data.length) {
            const tagResult = readVarint(chunk1Data, pos);
            pos = tagResult.pos;
            const fieldNum = tagResult.value >> 3;
            const wireType = tagResult.value & 0x7;

            if (wireType === 2) {
                const lenResult = readVarint(chunk1Data, pos);
                pos = lenResult.pos;
                const content = chunk1Data.slice(pos, pos + lenResult.value);
                pos += lenResult.value;

                // Field 1 = IndexMetadata (contains UUID)
                if (fieldNum === 1) {
                    const parsed = IVFIndex._parseIndexMetadata(content);
                    if (parsed && parsed.uuid) {
                        indexUuid = parsed.uuid;
                        indexFieldId = parsed.fieldId;
                    }
                }
            } else if (wireType === 0) {
                const r = readVarint(chunk1Data, pos);
                pos = r.pos;
            } else if (wireType === 5) {
                pos += 4;
            } else if (wireType === 1) {
                pos += 8;
            }
        }

        return indexUuid ? { uuid: indexUuid, fieldId: indexFieldId } : null;
    }

    /**
     * Parse IndexMetadata protobuf message.
     * @private
     */
    static _parseIndexMetadata(bytes) {
        let pos = 0;
        let uuid = null;
        let fieldId = null;

        const readVarint = () => {
            let result = 0;
            let shift = 0;
            while (pos < bytes.length) {
                const byte = bytes[pos++];
                result |= (byte & 0x7F) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7;
            }
            return result;
        };

        while (pos < bytes.length) {
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (wireType === 2) {
                const len = readVarint();
                const content = bytes.slice(pos, pos + len);
                pos += len;

                if (fieldNum === 1) {
                    // UUID (nested message with bytes)
                    uuid = IVFIndex._parseUuid(content);
                }
            } else if (wireType === 0) {
                const val = readVarint();
                if (fieldNum === 2) {
                    // fields (repeated int32) - but packed, so single value here
                    fieldId = val;
                }
            } else if (wireType === 5) {
                pos += 4;
            } else if (wireType === 1) {
                pos += 8;
            }
        }

        return { uuid, fieldId };
    }

    /**
     * Parse UUID protobuf message.
     * @private
     */
    static _parseUuid(bytes) {
        // UUID message: field 1 = bytes (16 bytes)
        let pos = 0;
        while (pos < bytes.length) {
            const tag = bytes[pos++];
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (wireType === 2 && fieldNum === 1) {
                const len = bytes[pos++];
                const uuidBytes = bytes.slice(pos, pos + len);
                // Convert to hex string with dashes (UUID format)
                const hex = Array.from(uuidBytes).map(b => b.toString(16).padStart(2, '0')).join('');
                // Format as UUID: 8-4-4-4-12
                return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20,32)}`;
            } else if (wireType === 0) {
                while (pos < bytes.length && (bytes[pos++] & 0x80)) {}
            } else if (wireType === 5) {
                pos += 4;
            } else if (wireType === 1) {
                pos += 8;
            }
        }
        return null;
    }

    /**
     * Parse IVF index file.
     * Index file contains VectorIndex protobuf with IVF stage.
     * IVF message structure:
     *   field 1: repeated float centroids (deprecated)
     *   field 2: repeated uint64 offsets - byte offset of each partition
     *   field 3: repeated uint32 lengths - number of records per partition
     *   field 4: Tensor centroids_tensor - centroids as tensor
     *   field 5: optional double loss
     * @private
     */
    static _parseIndexFile(bytes, indexInfo) {
        const index = new IVFIndex();

        // Try to find and parse IVF message within the file
        // The file may have nested protobuf structures
        const ivfData = IVFIndex._findIVFMessage(bytes);

        if (ivfData) {
            if (ivfData.centroids) {
                index.centroids = ivfData.centroids.data;
                index.numPartitions = ivfData.centroids.numPartitions;
                index.dimension = ivfData.centroids.dimension;
            }
            if (ivfData.offsets && ivfData.offsets.length > 0) {
                index.partitionOffsets = ivfData.offsets;
                // Loaded partition offsets
            }
            if (ivfData.lengths && ivfData.lengths.length > 0) {
                index.partitionLengths = ivfData.lengths;
                // Loaded partition lengths
            }

            // Index centroids loaded successfully
        }

        // Fallback: try to find centroids in nested messages
        if (!index.centroids) {
            let pos = 0;
            const readVarint = () => {
                let result = 0;
                let shift = 0;
                while (pos < bytes.length) {
                    const byte = bytes[pos++];
                    result |= (byte & 0x7F) << shift;
                    if ((byte & 0x80) === 0) break;
                    shift += 7;
                }
                return result;
            };

            while (pos < bytes.length - 4) {
                const tag = readVarint();
                const fieldNum = tag >> 3;
                const wireType = tag & 0x7;

                if (wireType === 2) {
                    const len = readVarint();
                    if (len > bytes.length - pos) break;

                    const content = bytes.slice(pos, pos + len);
                    pos += len;

                    if (len > 100 && len < 100000000) {
                        const centroids = IVFIndex._tryParseCentroids(content);
                        if (centroids) {
                            index.centroids = centroids.data;
                            index.numPartitions = centroids.numPartitions;
                            index.dimension = centroids.dimension;
                            // Loaded IVF centroids via fallback parsing
                        }
                    }
                } else if (wireType === 0) {
                    readVarint();
                } else if (wireType === 5) {
                    pos += 4;
                } else if (wireType === 1) {
                    pos += 8;
                }
            }
        }

        return index.centroids ? index : null;
    }

    /**
     * Find and parse IVF message within index file bytes.
     * Recursively searches nested protobuf messages.
     * @private
     */
    static _findIVFMessage(bytes) {
        // IVF message fields:
        // field 2: repeated uint64 offsets (packed)
        // field 3: repeated uint32 lengths (packed)
        // field 4: Tensor centroids_tensor

        let pos = 0;
        let offsets = [];
        let lengths = [];
        let centroids = null;

        const readVarint = () => {
            let result = 0;
            let shift = 0;
            while (pos < bytes.length) {
                const byte = bytes[pos++];
                result |= (byte & 0x7F) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7;
            }
            return result;
        };

        const readFixed64 = () => {
            if (pos + 8 > bytes.length) return 0n;
            const view = new DataView(bytes.buffer, bytes.byteOffset + pos, 8);
            pos += 8;
            return view.getBigUint64(0, true);
        };

        const readFixed32 = () => {
            if (pos + 4 > bytes.length) return 0;
            const view = new DataView(bytes.buffer, bytes.byteOffset + pos, 4);
            pos += 4;
            return view.getUint32(0, true);
        };

        while (pos < bytes.length - 4) {
            const startPos = pos;
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (wireType === 2) {
                // Length-delimited field
                const len = readVarint();
                if (len > bytes.length - pos || len < 0) {
                    pos = startPos + 1;
                    continue;
                }

                const content = bytes.slice(pos, pos + len);
                pos += len;

                if (fieldNum === 2) {
                    // offsets - packed uint64
                    // Could be packed fixed64 or packed varint
                    if (len % 8 === 0 && len > 0) {
                        // Try as packed fixed64
                        const numOffsets = len / 8;
                        const view = new DataView(content.buffer, content.byteOffset, len);
                        for (let i = 0; i < numOffsets; i++) {
                            offsets.push(Number(view.getBigUint64(i * 8, true)));
                        }
                        // Parsed partition offsets
                    }
                } else if (fieldNum === 3) {
                    // lengths - packed uint32
                    if (len % 4 === 0 && len > 0) {
                        // Try as packed fixed32
                        const numLengths = len / 4;
                        const view = new DataView(content.buffer, content.byteOffset, len);
                        for (let i = 0; i < numLengths; i++) {
                            lengths.push(view.getUint32(i * 4, true));
                        }
                        // Parsed partition lengths (fixed32)
                    } else {
                        // Try as packed varint
                        let lpos = 0;
                        while (lpos < content.length) {
                            let val = 0, shift = 0;
                            while (lpos < content.length) {
                                const byte = content[lpos++];
                                val |= (byte & 0x7F) << shift;
                                if ((byte & 0x80) === 0) break;
                                shift += 7;
                            }
                            lengths.push(val);
                        }
                        // Parsed partition lengths (varint)
                    }
                } else if (fieldNum === 4) {
                    // centroids_tensor
                    centroids = IVFIndex._tryParseCentroids(content);
                } else if (len > 100) {
                    // Recursively search nested messages
                    const nested = IVFIndex._findIVFMessage(content);
                    if (nested && (nested.centroids || nested.offsets?.length > 0)) {
                        if (nested.centroids && !centroids) centroids = nested.centroids;
                        if (nested.offsets?.length > offsets.length) offsets = nested.offsets;
                        if (nested.lengths?.length > lengths.length) lengths = nested.lengths;
                    }
                }
            } else if (wireType === 0) {
                readVarint();
            } else if (wireType === 5) {
                pos += 4;
            } else if (wireType === 1) {
                pos += 8;
            } else {
                // Unknown wire type, skip byte
                pos = startPos + 1;
            }
        }

        if (centroids || offsets.length > 0 || lengths.length > 0) {
            return { centroids, offsets, lengths };
        }
        return null;
    }

    /**
     * Try to parse centroids from a Tensor message.
     * @private
     */
    static _tryParseCentroids(bytes) {
        let pos = 0;
        let shape = [];
        let dataBytes = null;
        let dataType = 2; // Default to float32

        const readVarint = () => {
            let result = 0;
            let shift = 0;
            while (pos < bytes.length) {
                const byte = bytes[pos++];
                result |= (byte & 0x7F) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7;
            }
            return result;
        };

        while (pos < bytes.length) {
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (wireType === 0) {
                const val = readVarint();
                if (fieldNum === 1) dataType = val;
            } else if (wireType === 2) {
                const len = readVarint();
                const content = bytes.slice(pos, pos + len);
                pos += len;

                if (fieldNum === 2) {
                    // shape (packed repeated uint32)
                    let shapePos = 0;
                    while (shapePos < content.length) {
                        let val = 0, shift = 0;
                        while (shapePos < content.length) {
                            const byte = content[shapePos++];
                            val |= (byte & 0x7F) << shift;
                            if ((byte & 0x80) === 0) break;
                            shift += 7;
                        }
                        shape.push(val);
                    }
                } else if (fieldNum === 3) {
                    dataBytes = content;
                }
            } else if (wireType === 5) {
                pos += 4;
            } else if (wireType === 1) {
                pos += 8;
            }
        }

        if (shape.length >= 2 && dataBytes && dataType === 2) {
            // float32 tensor with at least 2D shape
            const numPartitions = shape[0];
            const dimension = shape[1];

            if (dataBytes.length === numPartitions * dimension * 4) {
                const data = new Float32Array(dataBytes.buffer, dataBytes.byteOffset, numPartitions * dimension);
                return { data, numPartitions, dimension };
            }
        }

        return null;
    }

    /**
     * Find the nearest partitions to a query vector.
     * @param {Float32Array} queryVec - Query vector
     * @param {number} nprobe - Number of partitions to search
     * @returns {number[]} - Indices of nearest partitions
     */
    findNearestPartitions(queryVec, nprobe = 10) {
        if (!this.centroids || queryVec.length !== this.dimension) {
            return [];
        }

        nprobe = Math.min(nprobe, this.numPartitions);

        // Compute distance to each centroid
        const distances = new Array(this.numPartitions);

        for (let p = 0; p < this.numPartitions; p++) {
            const centroidStart = p * this.dimension;

            // Cosine similarity (or L2 distance based on metricType)
            let dot = 0, normA = 0, normB = 0;
            for (let i = 0; i < this.dimension; i++) {
                const a = queryVec[i];
                const b = this.centroids[centroidStart + i];
                dot += a * b;
                normA += a * a;
                normB += b * b;
            }

            const denom = Math.sqrt(normA) * Math.sqrt(normB);
            distances[p] = { idx: p, score: denom === 0 ? 0 : dot / denom };
        }

        // Sort by similarity (descending) and take top nprobe
        distances.sort((a, b) => b.score - a.score);
        return distances.slice(0, nprobe).map(d => d.idx);
    }
}

// ============================================================================
// SQL Parser and Executor
// ============================================================================

/**
 * SQL Token types
 */
const TokenType = {
    // Keywords
    SELECT: 'SELECT',
    DISTINCT: 'DISTINCT',
    FROM: 'FROM',
    WHERE: 'WHERE',
    AND: 'AND',
    OR: 'OR',
    NOT: 'NOT',
    ORDER: 'ORDER',
    BY: 'BY',
    ASC: 'ASC',
    DESC: 'DESC',
    LIMIT: 'LIMIT',
    OFFSET: 'OFFSET',
    AS: 'AS',
    NULL: 'NULL',
    IS: 'IS',
    IN: 'IN',
    BETWEEN: 'BETWEEN',
    LIKE: 'LIKE',
    TRUE: 'TRUE',
    FALSE: 'FALSE',
    GROUP: 'GROUP',
    HAVING: 'HAVING',
    COUNT: 'COUNT',
    SUM: 'SUM',
    AVG: 'AVG',
    MIN: 'MIN',
    MAX: 'MAX',
    // Vector search keywords
    NEAR: 'NEAR',
    TOPK: 'TOPK',
    // File reference
    FILE: 'FILE',
    // Join keywords
    JOIN: 'JOIN',
    INNER: 'INNER',
    LEFT: 'LEFT',
    RIGHT: 'RIGHT',
    FULL: 'FULL',
    OUTER: 'OUTER',
    CROSS: 'CROSS',
    ON: 'ON',
    // Write keywords
    CREATE: 'CREATE',
    TABLE: 'TABLE',
    INSERT: 'INSERT',
    INTO: 'INTO',
    VALUES: 'VALUES',
    UPDATE: 'UPDATE',
    SET: 'SET',
    DELETE: 'DELETE',
    DROP: 'DROP',
    // Data types
    INT: 'INT',
    INTEGER: 'INTEGER',
    BIGINT: 'BIGINT',
    FLOAT: 'FLOAT',
    DOUBLE: 'DOUBLE',
    TEXT: 'TEXT',
    VARCHAR: 'VARCHAR',
    BOOLEAN: 'BOOLEAN',
    BOOL: 'BOOL',
    VECTOR: 'VECTOR',
    PRIMARY: 'PRIMARY',
    KEY: 'KEY',

    // Literals
    IDENTIFIER: 'IDENTIFIER',
    NUMBER: 'NUMBER',
    STRING: 'STRING',

    // Operators
    STAR: 'STAR',
    COMMA: 'COMMA',
    DOT: 'DOT',
    LPAREN: 'LPAREN',
    RPAREN: 'RPAREN',
    EQ: 'EQ',
    NE: 'NE',
    LT: 'LT',
    LE: 'LE',
    GT: 'GT',
    GE: 'GE',
    PLUS: 'PLUS',
    MINUS: 'MINUS',
    SLASH: 'SLASH',

    // Special
    EOF: 'EOF',
};

const KEYWORDS = {
    'SELECT': TokenType.SELECT,
    'DISTINCT': TokenType.DISTINCT,
    'FROM': TokenType.FROM,
    'WHERE': TokenType.WHERE,
    'AND': TokenType.AND,
    'OR': TokenType.OR,
    'NOT': TokenType.NOT,
    'ORDER': TokenType.ORDER,
    'BY': TokenType.BY,
    'ASC': TokenType.ASC,
    'DESC': TokenType.DESC,
    'LIMIT': TokenType.LIMIT,
    'OFFSET': TokenType.OFFSET,
    'AS': TokenType.AS,
    'NULL': TokenType.NULL,
    'IS': TokenType.IS,
    'IN': TokenType.IN,
    'BETWEEN': TokenType.BETWEEN,
    'LIKE': TokenType.LIKE,
    'TRUE': TokenType.TRUE,
    'FALSE': TokenType.FALSE,
    'GROUP': TokenType.GROUP,
    'HAVING': TokenType.HAVING,
    'COUNT': TokenType.COUNT,
    'SUM': TokenType.SUM,
    'AVG': TokenType.AVG,
    'MIN': TokenType.MIN,
    'MAX': TokenType.MAX,
    'NEAR': TokenType.NEAR,
    'TOPK': TokenType.TOPK,
    'FILE': TokenType.FILE,
    // Join keywords
    'JOIN': TokenType.JOIN,
    'INNER': TokenType.INNER,
    'LEFT': TokenType.LEFT,
    'RIGHT': TokenType.RIGHT,
    'FULL': TokenType.FULL,
    'OUTER': TokenType.OUTER,
    'CROSS': TokenType.CROSS,
    'ON': TokenType.ON,
    // Write keywords
    'CREATE': TokenType.CREATE,
    'TABLE': TokenType.TABLE,
    'INSERT': TokenType.INSERT,
    'INTO': TokenType.INTO,
    'VALUES': TokenType.VALUES,
    'UPDATE': TokenType.UPDATE,
    'SET': TokenType.SET,
    'DELETE': TokenType.DELETE,
    'DROP': TokenType.DROP,
    // Data types
    'INT': TokenType.INT,
    'INTEGER': TokenType.INTEGER,
    'BIGINT': TokenType.BIGINT,
    'FLOAT': TokenType.FLOAT,
    'DOUBLE': TokenType.DOUBLE,
    'TEXT': TokenType.TEXT,
    'VARCHAR': TokenType.VARCHAR,
    'BOOLEAN': TokenType.BOOLEAN,
    'BOOL': TokenType.BOOL,
    'VECTOR': TokenType.VECTOR,
    'PRIMARY': TokenType.PRIMARY,
    'KEY': TokenType.KEY,
};

/**
 * SQL Lexer - tokenizes SQL input
 */
export class SQLLexer {
    constructor(sql) {
        this.sql = sql;
        this.pos = 0;
        this.length = sql.length;
    }

    peek() {
        if (this.pos >= this.length) return '\0';
        return this.sql[this.pos];
    }

    advance() {
        if (this.pos < this.length) {
            return this.sql[this.pos++];
        }
        return '\0';
    }

    skipWhitespace() {
        while (this.pos < this.length && /\s/.test(this.sql[this.pos])) {
            this.pos++;
        }
    }

    readIdentifier() {
        const start = this.pos;
        while (this.pos < this.length && /[a-zA-Z0-9_]/.test(this.sql[this.pos])) {
            this.pos++;
        }
        return this.sql.slice(start, this.pos);
    }

    readNumber() {
        const start = this.pos;
        let hasDecimal = false;

        while (this.pos < this.length) {
            const ch = this.sql[this.pos];
            if (ch === '.' && !hasDecimal) {
                hasDecimal = true;
                this.pos++;
            } else if (/\d/.test(ch)) {
                this.pos++;
            } else {
                break;
            }
        }
        return this.sql.slice(start, this.pos);
    }

    readString(quote) {
        const start = this.pos;
        this.advance(); // Skip opening quote

        while (this.pos < this.length) {
            const ch = this.sql[this.pos];
            if (ch === quote) {
                // Check for escaped quote
                if (this.pos + 1 < this.length && this.sql[this.pos + 1] === quote) {
                    this.pos += 2;
                    continue;
                }
                this.pos++; // Skip closing quote
                break;
            }
            this.pos++;
        }

        // Return string without quotes, handling escaped quotes
        const inner = this.sql.slice(start + 1, this.pos - 1);
        return inner.replace(new RegExp(quote + quote, 'g'), quote);
    }

    nextToken() {
        this.skipWhitespace();

        if (this.pos >= this.length) {
            return { type: TokenType.EOF, value: null };
        }

        const ch = this.peek();

        // Identifiers and keywords
        if (/[a-zA-Z_]/.test(ch)) {
            const value = this.readIdentifier();
            const upper = value.toUpperCase();
            const type = KEYWORDS[upper] || TokenType.IDENTIFIER;
            return { type, value: type === TokenType.IDENTIFIER ? value : upper };
        }

        // Numbers
        if (/\d/.test(ch)) {
            const value = this.readNumber();
            return { type: TokenType.NUMBER, value };
        }

        // Strings
        if (ch === "'" || ch === '"') {
            const value = this.readString(ch);
            return { type: TokenType.STRING, value };
        }

        // Operators
        this.advance();

        switch (ch) {
            case '*': return { type: TokenType.STAR, value: '*' };
            case ',': return { type: TokenType.COMMA, value: ',' };
            case '.': return { type: TokenType.DOT, value: '.' };
            case '(': return { type: TokenType.LPAREN, value: '(' };
            case ')': return { type: TokenType.RPAREN, value: ')' };
            case '+': return { type: TokenType.PLUS, value: '+' };
            case '-': return { type: TokenType.MINUS, value: '-' };
            case '/': return { type: TokenType.SLASH, value: '/' };
            case '=': return { type: TokenType.EQ, value: '=' };
            case '<':
                if (this.peek() === '=') {
                    this.advance();
                    return { type: TokenType.LE, value: '<=' };
                }
                if (this.peek() === '>') {
                    this.advance();
                    return { type: TokenType.NE, value: '<>' };
                }
                return { type: TokenType.LT, value: '<' };
            case '>':
                if (this.peek() === '=') {
                    this.advance();
                    return { type: TokenType.GE, value: '>=' };
                }
                return { type: TokenType.GT, value: '>' };
            case '!':
                if (this.peek() === '=') {
                    this.advance();
                    return { type: TokenType.NE, value: '!=' };
                }
                throw new Error(`Unexpected character: ${ch}`);
            default:
                throw new Error(`Unexpected character: ${ch}`);
        }
    }

    tokenize() {
        const tokens = [];
        let token;
        while ((token = this.nextToken()).type !== TokenType.EOF) {
            tokens.push(token);
        }
        tokens.push(token); // Include EOF
        return tokens;
    }
}

/**
 * SQL Parser - parses tokens into AST
 */
export class SQLParser {
    constructor(tokens) {
        this.tokens = tokens;
        this.pos = 0;
    }

    current() {
        return this.tokens[this.pos] || { type: TokenType.EOF };
    }

    advance() {
        if (this.pos < this.tokens.length) {
            return this.tokens[this.pos++];
        }
        return { type: TokenType.EOF };
    }

    expect(type) {
        const token = this.current();
        if (token.type !== type) {
            throw new Error(`Expected ${type}, got ${token.type} (${token.value})`);
        }
        return this.advance();
    }

    match(...types) {
        if (types.includes(this.current().type)) {
            return this.advance();
        }
        return null;
    }

    check(...types) {
        return types.includes(this.current().type);
    }

    /**
     * Parse SQL statement (SELECT, INSERT, UPDATE, DELETE, CREATE TABLE, DROP TABLE)
     */
    parse() {
        // Dispatch based on first keyword
        if (this.check(TokenType.SELECT)) {
            return this.parseSelect();
        } else if (this.check(TokenType.INSERT)) {
            return this.parseInsert();
        } else if (this.check(TokenType.UPDATE)) {
            return this.parseUpdate();
        } else if (this.check(TokenType.DELETE)) {
            return this.parseDelete();
        } else if (this.check(TokenType.CREATE)) {
            return this.parseCreateTable();
        } else if (this.check(TokenType.DROP)) {
            return this.parseDropTable();
        } else {
            throw new Error(`Unexpected token: ${this.current().type}. Expected SELECT, INSERT, UPDATE, DELETE, CREATE, or DROP`);
        }
    }

    /**
     * Parse SELECT statement
     */
    parseSelect() {
        this.expect(TokenType.SELECT);

        // DISTINCT
        const distinct = !!this.match(TokenType.DISTINCT);

        // Select list
        const columns = this.parseSelectList();

        // FROM - supports: table_name, read_lance('url'), 'url.lance'
        let from = null;
        if (this.match(TokenType.FROM)) {
            from = this.parseFromClause();
        }

        // JOIN clauses (one or more)
        const joins = [];
        while (this.check(TokenType.JOIN) || this.check(TokenType.INNER) ||
               this.check(TokenType.LEFT) || this.check(TokenType.RIGHT) ||
               this.check(TokenType.FULL) || this.check(TokenType.CROSS)) {
            joins.push(this.parseJoinClause());
        }

        // WHERE
        let where = null;
        if (this.match(TokenType.WHERE)) {
            where = this.parseExpr();
        }

        // GROUP BY
        let groupBy = [];
        if (this.match(TokenType.GROUP)) {
            this.expect(TokenType.BY);
            groupBy = this.parseColumnList();
        }

        // HAVING
        let having = null;
        if (this.match(TokenType.HAVING)) {
            having = this.parseExpr();
        }

        // NEAR - vector similarity search
        // Syntax: NEAR [column] <'text'|row_num> [TOPK n]
        let search = null;
        if (this.match(TokenType.NEAR)) {
            let column = null;
            let query = null;
            let searchRow = null;
            let topK = 20; // default
            let encoder = 'minilm'; // default

            // First token after NEAR: could be column name, string, or number
            if (this.check(TokenType.IDENTIFIER)) {
                // Could be column name - peek ahead
                const ident = this.advance().value;
                if (this.check(TokenType.STRING) || this.check(TokenType.NUMBER)) {
                    // It was a column name
                    column = ident;
                } else {
                    // It was a search term without quotes (error)
                    throw new Error(`NEAR requires quoted text or row number. Did you mean: NEAR '${ident}'?`);
                }
            }

            // Now expect string (text search) or number (row search)
            if (this.check(TokenType.STRING)) {
                query = this.advance().value;
            } else if (this.check(TokenType.NUMBER)) {
                searchRow = parseInt(this.advance().value, 10);
            } else {
                throw new Error('NEAR requires a quoted text string or row number');
            }

            // Optional TOPK
            if (this.match(TokenType.TOPK)) {
                topK = parseInt(this.expect(TokenType.NUMBER).value, 10);
            }

            search = { query, searchRow, column, topK, encoder };
        }

        // ORDER BY and LIMIT can appear in either order
        let orderBy = [];
        let limit = null;
        let offset = null;

        // First pass: check for ORDER BY or LIMIT
        if (this.match(TokenType.ORDER)) {
            this.expect(TokenType.BY);
            orderBy = this.parseOrderByList();
        }
        if (this.match(TokenType.LIMIT)) {
            limit = parseInt(this.expect(TokenType.NUMBER).value, 10);
        }

        // Second pass: allow ORDER BY after LIMIT (non-standard but common)
        if (orderBy.length === 0 && this.match(TokenType.ORDER)) {
            this.expect(TokenType.BY);
            orderBy = this.parseOrderByList();
        }

        // OFFSET (can come after LIMIT)
        if (this.match(TokenType.OFFSET)) {
            offset = parseInt(this.expect(TokenType.NUMBER).value, 10);
        }

        // Check that we've consumed all tokens
        if (this.current().type !== TokenType.EOF) {
            throw new Error(`Unexpected token after query: ${this.current().type} (${this.current().value}). Check your SQL syntax.`);
        }

        return {
            type: 'SELECT',
            distinct,
            columns,
            from,
            joins,
            where,
            groupBy,
            having,
            search,
            orderBy,
            limit,
            offset,
        };
    }

    /**
     * Parse INSERT statement
     * Syntax: INSERT INTO table_name [(col1, col2, ...)] VALUES (val1, val2, ...), ...
     */
    parseInsert() {
        this.expect(TokenType.INSERT);
        this.expect(TokenType.INTO);

        // Table name
        const table = this.expect(TokenType.IDENTIFIER).value;

        // Optional column list
        let columns = null;
        if (this.match(TokenType.LPAREN)) {
            columns = [];
            columns.push(this.expect(TokenType.IDENTIFIER).value);
            while (this.match(TokenType.COMMA)) {
                columns.push(this.expect(TokenType.IDENTIFIER).value);
            }
            this.expect(TokenType.RPAREN);
        }

        // VALUES clause
        this.expect(TokenType.VALUES);

        // Parse value rows
        const rows = [];
        do {
            this.expect(TokenType.LPAREN);
            const values = [];
            values.push(this.parseValue());
            while (this.match(TokenType.COMMA)) {
                values.push(this.parseValue());
            }
            this.expect(TokenType.RPAREN);
            rows.push(values);
        } while (this.match(TokenType.COMMA));

        return {
            type: 'INSERT',
            table,
            columns,
            rows,
        };
    }

    /**
     * Parse a single value (number, string, null, true, false)
     */
    parseValue() {
        if (this.match(TokenType.NULL)) {
            return { type: 'null', value: null };
        }
        if (this.match(TokenType.TRUE)) {
            return { type: 'boolean', value: true };
        }
        if (this.match(TokenType.FALSE)) {
            return { type: 'boolean', value: false };
        }
        if (this.check(TokenType.NUMBER)) {
            const token = this.advance();
            const value = token.value.includes('.') ? parseFloat(token.value) : parseInt(token.value, 10);
            return { type: 'number', value };
        }
        if (this.check(TokenType.STRING)) {
            const token = this.advance();
            return { type: 'string', value: token.value };
        }
        if (this.check(TokenType.MINUS)) {
            this.advance();
            const token = this.expect(TokenType.NUMBER);
            const value = token.value.includes('.') ? -parseFloat(token.value) : -parseInt(token.value, 10);
            return { type: 'number', value };
        }
        // Vector literal: [1.0, 2.0, 3.0]
        if (this.check(TokenType.LBRACKET)) {
            return this.parseVectorLiteral();
        }

        throw new Error(`Expected value, got ${this.current().type}`);
    }

    /**
     * Parse vector literal: [1.0, 2.0, 3.0]
     */
    parseVectorLiteral() {
        // Note: This requires adding LBRACKET/RBRACKET tokens
        // For now, we'll handle arrays as strings that start with '['
        throw new Error('Vector literals not yet supported. Use INSERT with individual columns.');
    }

    /**
     * Parse UPDATE statement
     * Syntax: UPDATE table_name SET col1 = val1, col2 = val2 [WHERE condition]
     */
    parseUpdate() {
        this.expect(TokenType.UPDATE);

        // Table name
        const table = this.expect(TokenType.IDENTIFIER).value;

        // SET clause
        this.expect(TokenType.SET);

        const assignments = [];
        do {
            const column = this.expect(TokenType.IDENTIFIER).value;
            this.expect(TokenType.EQ);
            const value = this.parseValue();
            assignments.push({ column, value });
        } while (this.match(TokenType.COMMA));

        // Optional WHERE
        let where = null;
        if (this.match(TokenType.WHERE)) {
            where = this.parseExpr();
        }

        return {
            type: 'UPDATE',
            table,
            assignments,
            where,
        };
    }

    /**
     * Parse DELETE statement
     * Syntax: DELETE FROM table_name [WHERE condition]
     */
    parseDelete() {
        this.expect(TokenType.DELETE);
        this.expect(TokenType.FROM);

        // Table name
        const table = this.expect(TokenType.IDENTIFIER).value;

        // Optional WHERE
        let where = null;
        if (this.match(TokenType.WHERE)) {
            where = this.parseExpr();
        }

        return {
            type: 'DELETE',
            table,
            where,
        };
    }

    /**
     * Parse CREATE TABLE statement
     * Syntax: CREATE TABLE table_name (col1 TYPE, col2 TYPE, ...)
     */
    parseCreateTable() {
        this.expect(TokenType.CREATE);
        this.expect(TokenType.TABLE);

        // Table name
        const table = this.expect(TokenType.IDENTIFIER).value;

        // Column definitions
        this.expect(TokenType.LPAREN);

        const columns = [];
        do {
            const name = this.expect(TokenType.IDENTIFIER).value;

            // Data type
            let dataType = 'TEXT'; // default
            let primaryKey = false;
            let vectorDim = null;

            if (this.check(TokenType.INT) || this.check(TokenType.INTEGER) || this.check(TokenType.BIGINT)) {
                this.advance();
                dataType = 'INT64';
            } else if (this.check(TokenType.FLOAT) || this.check(TokenType.DOUBLE)) {
                this.advance();
                dataType = 'FLOAT64';
            } else if (this.check(TokenType.TEXT) || this.check(TokenType.VARCHAR)) {
                this.advance();
                dataType = 'STRING';
            } else if (this.check(TokenType.BOOLEAN) || this.check(TokenType.BOOL)) {
                this.advance();
                dataType = 'BOOL';
            } else if (this.check(TokenType.VECTOR)) {
                this.advance();
                dataType = 'VECTOR';
                // Optional dimension: VECTOR(384)
                if (this.match(TokenType.LPAREN)) {
                    vectorDim = parseInt(this.expect(TokenType.NUMBER).value, 10);
                    this.expect(TokenType.RPAREN);
                }
            }

            // Optional PRIMARY KEY
            if (this.match(TokenType.PRIMARY)) {
                this.expect(TokenType.KEY);
                primaryKey = true;
            }

            columns.push({ name, dataType, primaryKey, vectorDim });
        } while (this.match(TokenType.COMMA));

        this.expect(TokenType.RPAREN);

        return {
            type: 'CREATE_TABLE',
            table,
            columns,
        };
    }

    /**
     * Parse DROP TABLE statement
     * Syntax: DROP TABLE table_name
     */
    parseDropTable() {
        this.expect(TokenType.DROP);
        this.expect(TokenType.TABLE);

        // Table name
        const table = this.expect(TokenType.IDENTIFIER).value;

        return {
            type: 'DROP_TABLE',
            table,
        };
    }

    parseSelectList() {
        const items = [this.parseSelectItem()];

        while (this.match(TokenType.COMMA)) {
            items.push(this.parseSelectItem());
        }

        return items;
    }

    parseSelectItem() {
        // Check for *
        if (this.match(TokenType.STAR)) {
            return { type: 'star' };
        }

        // Expression
        const expr = this.parseExpr();

        // Optional AS alias
        let alias = null;
        if (this.match(TokenType.AS)) {
            alias = this.expect(TokenType.IDENTIFIER).value;
        } else if (this.check(TokenType.IDENTIFIER) && !this.check(TokenType.FROM, TokenType.WHERE, TokenType.ORDER, TokenType.LIMIT, TokenType.GROUP, TokenType.JOIN, TokenType.INNER, TokenType.LEFT, TokenType.RIGHT, TokenType.COMMA)) {
            // Implicit alias (but not if next token is a keyword or comma)
            alias = this.advance().value;
        }

        return { type: 'expr', expr, alias };
    }

    /**
     * Parse FROM clause - supports:
     * - table_name (identifier)
     * - read_lance('url') (function call)
     * - 'url.lance' (string literal, auto-detect)
     */
    parseFromClause() {
        let from = null;

        // Check for string literal (direct URL/path)
        if (this.check(TokenType.STRING)) {
            const url = this.advance().value;
            from = { type: 'url', url };
        }
        // Check for function call like read_lance(), read_lance(24), read_lance('url'), read_lance('url', 24)
        else if (this.check(TokenType.IDENTIFIER)) {
            const name = this.advance().value;

            // If followed by (, it's a function call
            if (this.match(TokenType.LPAREN)) {
                const funcName = name.toLowerCase();
                if (funcName === 'read_lance') {
                    // read_lance(FILE) - local uploaded file
                    // read_lance(FILE, 24) - local file with version
                    // read_lance('url') - remote url
                    // read_lance('url', 24) - remote url with version
                    from = { type: 'url', function: 'read_lance' };

                    if (!this.check(TokenType.RPAREN)) {
                        // First arg: FILE keyword, string (url)
                        if (this.match(TokenType.FILE)) {
                            // Local file - mark as file reference
                            from.isFile = true;
                            // Check for second arg (version)
                            if (this.match(TokenType.COMMA)) {
                                from.version = parseInt(this.expect(TokenType.NUMBER).value, 10);
                            }
                        } else if (this.check(TokenType.STRING)) {
                            from.url = this.advance().value;
                            // Check for second arg (version)
                            if (this.match(TokenType.COMMA)) {
                                from.version = parseInt(this.expect(TokenType.NUMBER).value, 10);
                            }
                        }
                    }
                    this.expect(TokenType.RPAREN);
                } else {
                    throw new Error(`Unknown table function: ${name}. Supported: read_lance()`);
                }
            } else {
                // Just an identifier (table name - for future use)
                from = { type: 'table', name };
            }
        } else {
            throw new Error('Expected table name, URL string, or read_lance() after FROM');
        }

        // Parse optional alias (e.g., FROM images i or FROM images AS i)
        if (from) {
            if (this.match(TokenType.AS)) {
                from.alias = this.expect(TokenType.IDENTIFIER).value;
            } else if (this.check(TokenType.IDENTIFIER) && !this.check(TokenType.WHERE, TokenType.ORDER, TokenType.LIMIT, TokenType.GROUP, TokenType.NEAR, TokenType.JOIN, TokenType.INNER, TokenType.LEFT, TokenType.RIGHT, TokenType.COMMA)) {
                // Implicit alias (not followed by a keyword)
                from.alias = this.advance().value;
            }
        }

        return from;
    }

    /**
     * Parse JOIN clause - supports:
     * - JOIN table ON condition
     * - INNER JOIN table ON condition
     * - LEFT JOIN table ON condition
     * - RIGHT JOIN table ON condition
     * - FULL OUTER JOIN table ON condition
     * - CROSS JOIN table
     */
    parseJoinClause() {
        // Parse join type
        let joinType = 'INNER'; // default

        if (this.match(TokenType.INNER)) {
            this.expect(TokenType.JOIN);
            joinType = 'INNER';
        } else if (this.match(TokenType.LEFT)) {
            this.match(TokenType.OUTER); // optional
            this.expect(TokenType.JOIN);
            joinType = 'LEFT';
        } else if (this.match(TokenType.RIGHT)) {
            this.match(TokenType.OUTER); // optional
            this.expect(TokenType.JOIN);
            joinType = 'RIGHT';
        } else if (this.match(TokenType.FULL)) {
            this.match(TokenType.OUTER); // optional
            this.expect(TokenType.JOIN);
            joinType = 'FULL';
        } else if (this.match(TokenType.CROSS)) {
            this.expect(TokenType.JOIN);
            joinType = 'CROSS';
        } else {
            this.expect(TokenType.JOIN); // plain JOIN defaults to INNER
        }

        // Parse table reference (same as FROM clause) - includes alias parsing
        const table = this.parseFromClause();

        // Alias is already parsed by parseFromClause and stored in table.alias
        const alias = table.alias || null;

        // Parse ON condition (except for CROSS JOIN)
        let on = null;
        if (joinType !== 'CROSS') {
            this.expect(TokenType.ON);
            on = this.parseExpr();
        }

        return {
            type: joinType,
            table,
            alias,
            on
        };
    }

    parseColumnList() {
        const columns = [this.expect(TokenType.IDENTIFIER).value];

        while (this.match(TokenType.COMMA)) {
            columns.push(this.expect(TokenType.IDENTIFIER).value);
        }

        return columns;
    }

    parseOrderByList() {
        const items = [this.parseOrderByItem()];

        while (this.match(TokenType.COMMA)) {
            items.push(this.parseOrderByItem());
        }

        return items;
    }

    parseOrderByItem() {
        const column = this.expect(TokenType.IDENTIFIER).value;

        let descending = false;
        if (this.match(TokenType.DESC)) {
            descending = true;
        } else {
            this.match(TokenType.ASC);
        }

        return { column, descending };
    }

    // Expression parsing with precedence
    parseExpr() {
        return this.parseOrExpr();
    }

    parseOrExpr() {
        let left = this.parseAndExpr();

        while (this.match(TokenType.OR)) {
            const right = this.parseAndExpr();
            left = { type: 'binary', op: 'OR', left, right };
        }

        return left;
    }

    parseAndExpr() {
        let left = this.parseNotExpr();

        while (this.match(TokenType.AND)) {
            const right = this.parseNotExpr();
            left = { type: 'binary', op: 'AND', left, right };
        }

        return left;
    }

    parseNotExpr() {
        if (this.match(TokenType.NOT)) {
            const operand = this.parseNotExpr();
            return { type: 'unary', op: 'NOT', operand };
        }
        return this.parseCmpExpr();
    }

    parseCmpExpr() {
        let left = this.parseAddExpr();

        // IS NULL / IS NOT NULL
        if (this.match(TokenType.IS)) {
            const negated = !!this.match(TokenType.NOT);
            this.expect(TokenType.NULL);
            return {
                type: 'binary',
                op: negated ? '!=' : '==',
                left,
                right: { type: 'literal', value: null }
            };
        }

        // IN
        if (this.match(TokenType.IN)) {
            this.expect(TokenType.LPAREN);
            const values = [];
            values.push(this.parsePrimary());
            while (this.match(TokenType.COMMA)) {
                values.push(this.parsePrimary());
            }
            this.expect(TokenType.RPAREN);
            return { type: 'in', expr: left, values };
        }

        // BETWEEN
        if (this.match(TokenType.BETWEEN)) {
            const low = this.parseAddExpr();
            this.expect(TokenType.AND);
            const high = this.parseAddExpr();
            return { type: 'between', expr: left, low, high };
        }

        // LIKE
        if (this.match(TokenType.LIKE)) {
            const pattern = this.parsePrimary();
            return { type: 'like', expr: left, pattern };
        }

        // Comparison operators
        const opMap = {
            [TokenType.EQ]: '==',
            [TokenType.NE]: '!=',
            [TokenType.LT]: '<',
            [TokenType.LE]: '<=',
            [TokenType.GT]: '>',
            [TokenType.GE]: '>=',
        };

        const opToken = this.match(TokenType.EQ, TokenType.NE, TokenType.LT, TokenType.LE, TokenType.GT, TokenType.GE);
        if (opToken) {
            const right = this.parseAddExpr();
            return { type: 'binary', op: opMap[opToken.type], left, right };
        }

        return left;
    }

    parseAddExpr() {
        let left = this.parseMulExpr();

        while (true) {
            const opToken = this.match(TokenType.PLUS, TokenType.MINUS);
            if (!opToken) break;
            const right = this.parseMulExpr();
            left = { type: 'binary', op: opToken.value, left, right };
        }

        return left;
    }

    parseMulExpr() {
        let left = this.parseUnaryExpr();

        while (true) {
            const opToken = this.match(TokenType.STAR, TokenType.SLASH);
            if (!opToken) break;
            const right = this.parseUnaryExpr();
            left = { type: 'binary', op: opToken.value, left, right };
        }

        return left;
    }

    parseUnaryExpr() {
        if (this.match(TokenType.MINUS)) {
            const operand = this.parseUnaryExpr();
            return { type: 'unary', op: '-', operand };
        }
        return this.parsePrimary();
    }

    parsePrimary() {
        // NULL
        if (this.match(TokenType.NULL)) {
            return { type: 'literal', value: null };
        }

        // TRUE/FALSE
        if (this.match(TokenType.TRUE)) {
            return { type: 'literal', value: true };
        }
        if (this.match(TokenType.FALSE)) {
            return { type: 'literal', value: false };
        }

        // Number
        if (this.check(TokenType.NUMBER)) {
            const value = this.advance().value;
            return { type: 'literal', value: parseFloat(value) };
        }

        // String
        if (this.check(TokenType.STRING)) {
            const value = this.advance().value;
            return { type: 'literal', value };
        }

        // Function call or column reference
        if (this.check(TokenType.IDENTIFIER) || this.check(TokenType.COUNT, TokenType.SUM, TokenType.AVG, TokenType.MIN, TokenType.MAX)) {
            const name = this.advance().value;

            // Function call
            if (this.match(TokenType.LPAREN)) {
                let distinct = !!this.match(TokenType.DISTINCT);
                const args = [];

                if (!this.check(TokenType.RPAREN)) {
                    // Handle COUNT(*)
                    if (this.check(TokenType.STAR)) {
                        this.advance();
                        args.push({ type: 'star' });
                    } else {
                        args.push(this.parseExpr());
                        while (this.match(TokenType.COMMA)) {
                            args.push(this.parseExpr());
                        }
                    }
                }

                this.expect(TokenType.RPAREN);
                return { type: 'call', name: name.toUpperCase(), args, distinct };
            }

            // Column reference - check for table.column syntax
            if (this.match(TokenType.DOT)) {
                // table.column (column can be a keyword like "text")
                const table = name;
                const token = this.advance();
                // Allow keywords as column names (e.g., c.text where TEXT is a keyword)
                const column = token.value || token.type.toLowerCase();
                return { type: 'column', table, column };
            }

            // Simple column reference
            return { type: 'column', column: name };
        }

        // Parenthesized expression
        if (this.match(TokenType.LPAREN)) {
            const expr = this.parseExpr();
            this.expect(TokenType.RPAREN);
            return expr;
        }

        // Star (for SELECT *)
        if (this.match(TokenType.STAR)) {
            return { type: 'star' };
        }

        throw new Error(`Unexpected token: ${this.current().type} (${this.current().value})`);
    }
}

/**
 * SQL Executor - executes parsed SQL against a LanceFile
 */
export class SQLExecutor {
    constructor(file) {
        this.file = file;
        this.columnMap = {};
        this.columnTypes = [];

        // Build column name -> index map
        if (file.columnNames) {
            file.columnNames.forEach((name, idx) => {
                this.columnMap[name.toLowerCase()] = idx;
            });
        }
    }

    /**
     * Execute a SQL query
     * @param {string} sql - SQL query string
     * @param {function} onProgress - Optional progress callback
     * @returns {Promise<{columns: string[], rows: any[][], total: number}>}
     */
    async execute(sql, onProgress = null) {
        // Tokenize and parse
        const lexer = new SQLLexer(sql);
        const tokens = lexer.tokenize();
        const parser = new SQLParser(tokens);
        const ast = parser.parse();

        // Debug: console.log('Parsed SQL AST:', ast);

        // Detect column types if not already done
        if (this.columnTypes.length === 0) {
            if (this.file._isRemote && this.file.detectColumnTypes) {
                this.columnTypes = await this.file.detectColumnTypes();
            } else if (this.file._columnTypes) {
                this.columnTypes = this.file._columnTypes;
            } else {
                // Default to unknown for all columns
                this.columnTypes = Array(this.file.numColumns || 0).fill('unknown');
            }
        }

        // Get total row count
        const totalRows = this.file._isRemote
            ? await this.file.getRowCount(0)
            : Number(this.file.getRowCount(0));

        // Determine which columns to read
        const neededColumns = this.collectNeededColumns(ast);
        // Debug: console.log('Needed columns:', neededColumns);

        // Determine output columns
        const outputColumns = this.resolveOutputColumns(ast);
        // Debug: console.log('Output columns:', outputColumns);

        // Check if this is an aggregation query
        const hasAggregates = this.hasAggregates(ast);
        if (hasAggregates) {
            // Special case: COUNT(*) without WHERE/SEARCH returns metadata row count (free)
            if (this.isSimpleCountStar(ast) && !ast.where && !ast.search) {
                return {
                    columns: ['COUNT(*)'],
                    rows: [[totalRows]],
                    total: 1,
                    aggregationStats: {
                        scannedRows: 0,
                        totalRows,
                        coveragePercent: '100.00',
                        isPartialScan: false,
                        fromMetadata: true,
                    },
                };
            }
            // For aggregations with SEARCH, we need to run search first
            if (ast.search) {
                return await this.executeAggregateWithSearch(ast, totalRows, onProgress);
            }
            return await this.executeAggregateQuery(ast, totalRows, onProgress);
        }

        // Calculate indices to fetch
        let indices;
        const limit = ast.limit || 100;
        const offset = ast.offset || 0;

        // For queries without WHERE, we can just fetch the needed indices directly
        // For queries with WHERE, we need to fetch more data and filter
        if (!ast.where) {
            // Simple case: no filtering needed
            indices = [];
            const endIdx = Math.min(offset + limit, totalRows);
            for (let i = offset; i < endIdx; i++) {
                indices.push(i);
            }
        } else {
            // Complex case: need to evaluate WHERE clause
            // Fetch data in batches and filter
            indices = await this.evaluateWhere(ast.where, totalRows, onProgress);

            // Apply OFFSET and LIMIT to filtered results
            indices = indices.slice(offset, offset + limit);
        }

        if (onProgress) {
            onProgress('Fetching column data...', 0, outputColumns.length);
        }

        // Fetch data for output columns
        const columnData = {};
        for (let i = 0; i < neededColumns.length; i++) {
            const colName = neededColumns[i];
            const colIdx = this.columnMap[colName.toLowerCase()];
            if (colIdx === undefined) continue;

            if (onProgress) {
                onProgress(`Fetching ${colName}...`, i, neededColumns.length);
            }

            columnData[colName.toLowerCase()] = await this.readColumnData(colIdx, indices);
        }

        // Build result rows
        const rows = [];
        for (let i = 0; i < indices.length; i++) {
            const row = [];
            for (const col of outputColumns) {
                if (col.type === 'star') {
                    // Expand all columns
                    for (const name of this.file.columnNames || []) {
                        const data = columnData[name.toLowerCase()];
                        row.push(data ? data[i] : null);
                    }
                } else {
                    const value = this.evaluateExpr(col.expr, columnData, i);
                    row.push(value);
                }
            }
            rows.push(row);
        }

        // Apply ORDER BY
        if (ast.orderBy && ast.orderBy.length > 0) {
            this.applyOrderBy(rows, ast.orderBy, outputColumns);
        }

        // Build column names for output
        const colNames = [];
        for (const col of outputColumns) {
            if (col.type === 'star') {
                colNames.push(...(this.file.columnNames || []));
            } else {
                colNames.push(col.alias || this.exprToName(col.expr));
            }
        }

        // When LIMIT is specified, total should reflect the limited count, not full dataset
        // This ensures infinite scroll respects the LIMIT clause
        const effectiveTotal = ast.limit ? rows.length : totalRows;

        // Track if ORDER BY was applied on a subset (honest about sorting limitations)
        const orderByOnSubset = ast.orderBy && ast.orderBy.length > 0 && rows.length < totalRows;

        return {
            columns: colNames,
            rows,
            total: effectiveTotal,
            orderByOnSubset,
            orderByColumns: ast.orderBy ? ast.orderBy.map(ob => `${ob.column} ${ob.direction}`) : [],
        };
    }

    collectNeededColumns(ast) {
        const columns = new Set();

        // From SELECT
        for (const item of ast.columns) {
            if (item.type === 'star') {
                (this.file.columnNames || []).forEach(n => columns.add(n.toLowerCase()));
            } else {
                this.collectColumnsFromExpr(item.expr, columns);
            }
        }

        // From WHERE
        if (ast.where) {
            this.collectColumnsFromExpr(ast.where, columns);
        }

        // From ORDER BY
        for (const ob of ast.orderBy || []) {
            columns.add(ob.column.toLowerCase());
        }

        return Array.from(columns);
    }

    collectColumnsFromExpr(expr, columns) {
        if (!expr) return;

        switch (expr.type) {
            case 'column':
                columns.add(expr.name.toLowerCase());
                break;
            case 'binary':
                this.collectColumnsFromExpr(expr.left, columns);
                this.collectColumnsFromExpr(expr.right, columns);
                break;
            case 'unary':
                this.collectColumnsFromExpr(expr.operand, columns);
                break;
            case 'call':
                for (const arg of expr.args || []) {
                    this.collectColumnsFromExpr(arg, columns);
                }
                break;
            case 'in':
                this.collectColumnsFromExpr(expr.expr, columns);
                break;
            case 'between':
                this.collectColumnsFromExpr(expr.expr, columns);
                break;
            case 'like':
                this.collectColumnsFromExpr(expr.expr, columns);
                break;
        }
    }

    resolveOutputColumns(ast) {
        return ast.columns;
    }

    async readColumnData(colIdx, indices) {
        const type = this.columnTypes[colIdx] || 'unknown';

        try {
            if (type === 'string') {
                const data = await this.file.readStringsAtIndices(colIdx, indices);
                // readStringsAtIndices returns array of strings
                return Array.isArray(data) ? data : Array.from(data);
            } else if (type === 'int64') {
                const data = await this.file.readInt64AtIndices(colIdx, indices);
                // Convert BigInt64Array to regular array of Numbers
                const result = [];
                for (let i = 0; i < data.length; i++) {
                    result.push(Number(data[i]));
                }
                return result;
            } else if (type === 'float64') {
                const data = await this.file.readFloat64AtIndices(colIdx, indices);
                // Convert Float64Array to regular array
                return Array.from(data);
            } else if (type === 'int32') {
                const data = await this.file.readInt32AtIndices(colIdx, indices);
                return Array.from(data);
            } else if (type === 'float32') {
                const data = await this.file.readFloat32AtIndices(colIdx, indices);
                return Array.from(data);
            } else if (type === 'vector') {
                // Return placeholder for vectors
                return indices.map(() => '[vector]');
            } else {
                // Try string as fallback
                try {
                    return await this.file.readStringsAtIndices(colIdx, indices);
                } catch (e) {
                    return indices.map(() => null);
                }
            }
        } catch (e) {
            // Failed to read column, returning nulls
            return indices.map(() => null);
        }
    }

    async evaluateWhere(whereExpr, totalRows, onProgress) {
        // Optimization: For simple conditions on a single numeric column,
        // fetch only the filter column first, then fetch other columns only for matches
        const simpleFilter = this._detectSimpleFilter(whereExpr);

        if (simpleFilter) {
            return await this._evaluateSimpleFilter(simpleFilter, totalRows, onProgress);
        }

        // Complex conditions: fetch all needed columns in batches
        return await this._evaluateComplexFilter(whereExpr, totalRows, onProgress);
    }

    /**
     * Detect if WHERE clause is a simple comparison (column op value).
     * @private
     */
    _detectSimpleFilter(expr) {
        if (expr.type !== 'binary') return null;
        if (!['==', '!=', '<', '<=', '>', '>='].includes(expr.op)) return null;

        // Check if it's (column op literal) or (literal op column)
        let column = null;
        let value = null;
        let op = expr.op;

        if (expr.left.type === 'column' && expr.right.type === 'literal') {
            column = expr.left.name;
            value = expr.right.value;
        } else if (expr.left.type === 'literal' && expr.right.type === 'column') {
            column = expr.right.name;
            value = expr.left.value;
            // Reverse the operator for (literal op column)
            if (op === '<') op = '>';
            else if (op === '>') op = '<';
            else if (op === '<=') op = '>=';
            else if (op === '>=') op = '<=';
        }

        if (!column || value === null) return null;

        const colIdx = this.columnMap[column.toLowerCase()];
        if (colIdx === undefined) return null;

        const colType = this.columnTypes[colIdx];
        if (!['int64', 'int32', 'float64', 'float32'].includes(colType)) return null;

        return { column, colIdx, op, value, colType };
    }

    /**
     * Optimized evaluation for simple column comparisons.
     * Fetches only the filter column in large batches.
     * @private
     */
    async _evaluateSimpleFilter(filter, totalRows, onProgress) {
        const matchingIndices = [];
        // Use larger batch size for single-column filtering
        const batchSize = 5000;

        // Using optimized simple filter path

        for (let batchStart = 0; batchStart < totalRows; batchStart += batchSize) {
            if (onProgress) {
                const pct = Math.round((batchStart / totalRows) * 100);
                onProgress(`Filtering ${filter.column}... ${pct}%`, batchStart, totalRows);
            }

            const batchEnd = Math.min(batchStart + batchSize, totalRows);
            const batchIndices = [];
            for (let i = batchStart; i < batchEnd; i++) {
                batchIndices.push(i);
            }

            // Fetch only the filter column
            const colData = await this.readColumnData(filter.colIdx, batchIndices);

            // Apply filter
            for (let i = 0; i < batchIndices.length; i++) {
                const val = colData[i];
                let matches = false;

                switch (filter.op) {
                    case '==': matches = val === filter.value; break;
                    case '!=': matches = val !== filter.value; break;
                    case '<': matches = val < filter.value; break;
                    case '<=': matches = val <= filter.value; break;
                    case '>': matches = val > filter.value; break;
                    case '>=': matches = val >= filter.value; break;
                }

                if (matches) {
                    matchingIndices.push(batchIndices[i]);
                }
            }

            // Early exit if we have enough results
            if (matchingIndices.length >= 10000) {
                // Early exit: found enough matches
                break;
            }
        }

        return matchingIndices;
    }

    /**
     * General evaluation for complex WHERE clauses.
     * @private
     */
    async _evaluateComplexFilter(whereExpr, totalRows, onProgress) {
        const matchingIndices = [];
        const batchSize = 1000;

        // Pre-compute needed columns
        const neededCols = new Set();
        this.collectColumnsFromExpr(whereExpr, neededCols);

        for (let batchStart = 0; batchStart < totalRows; batchStart += batchSize) {
            if (onProgress) {
                onProgress(`Filtering rows...`, batchStart, totalRows);
            }

            const batchEnd = Math.min(batchStart + batchSize, totalRows);
            const batchIndices = [];
            for (let i = batchStart; i < batchEnd; i++) {
                batchIndices.push(i);
            }

            // Fetch needed column data for this batch
            const batchData = {};
            for (const colName of neededCols) {
                const colIdx = this.columnMap[colName.toLowerCase()];
                if (colIdx !== undefined) {
                    batchData[colName.toLowerCase()] = await this.readColumnData(colIdx, batchIndices);
                }
            }

            // Evaluate WHERE for each row in batch
            for (let i = 0; i < batchIndices.length; i++) {
                const result = this.evaluateExpr(whereExpr, batchData, i);
                if (result) {
                    matchingIndices.push(batchIndices[i]);
                }
            }

            // Early exit if we have enough results
            if (matchingIndices.length >= 10000) {
                break;
            }
        }

        return matchingIndices;
    }

    evaluateExpr(expr, columnData, rowIdx) {
        if (!expr) return null;

        switch (expr.type) {
            case 'literal':
                return expr.value;

            case 'column': {
                const data = columnData[expr.name.toLowerCase()];
                return data ? data[rowIdx] : null;
            }

            case 'star':
                return '*';

            case 'binary': {
                const left = this.evaluateExpr(expr.left, columnData, rowIdx);
                const right = this.evaluateExpr(expr.right, columnData, rowIdx);

                switch (expr.op) {
                    case '+': return (left || 0) + (right || 0);
                    case '-': return (left || 0) - (right || 0);
                    case '*': return (left || 0) * (right || 0);
                    case '/': return right !== 0 ? (left || 0) / right : null;
                    case '==': return left === right;
                    case '!=': return left !== right;
                    case '<': return left < right;
                    case '<=': return left <= right;
                    case '>': return left > right;
                    case '>=': return left >= right;
                    case 'AND': return left && right;
                    case 'OR': return left || right;
                    default: return null;
                }
            }

            case 'unary': {
                const operand = this.evaluateExpr(expr.operand, columnData, rowIdx);
                switch (expr.op) {
                    case '-': return -operand;
                    case 'NOT': return !operand;
                    default: return null;
                }
            }

            case 'in': {
                const value = this.evaluateExpr(expr.expr, columnData, rowIdx);
                const values = expr.values.map(v => this.evaluateExpr(v, columnData, rowIdx));
                return values.includes(value);
            }

            case 'between': {
                const value = this.evaluateExpr(expr.expr, columnData, rowIdx);
                const low = this.evaluateExpr(expr.low, columnData, rowIdx);
                const high = this.evaluateExpr(expr.high, columnData, rowIdx);
                return value >= low && value <= high;
            }

            case 'like': {
                const value = this.evaluateExpr(expr.expr, columnData, rowIdx);
                const pattern = this.evaluateExpr(expr.pattern, columnData, rowIdx);
                if (typeof value !== 'string' || typeof pattern !== 'string') return false;
                // Convert SQL LIKE pattern to regex
                const regex = new RegExp('^' + pattern.replace(/%/g, '.*').replace(/_/g, '.') + '$', 'i');
                return regex.test(value);
            }

            case 'call':
                // Aggregate functions not supported in row-level evaluation
                return null;

            default:
                return null;
        }
    }

    applyOrderBy(rows, orderBy, outputColumns) {
        // Build column index map
        const colIdxMap = {};
        let idx = 0;
        for (const col of outputColumns) {
            if (col.type === 'star') {
                for (const name of this.file.columnNames || []) {
                    colIdxMap[name.toLowerCase()] = idx++;
                }
            } else {
                const name = col.alias || this.exprToName(col.expr);
                colIdxMap[name.toLowerCase()] = idx++;
            }
        }

        rows.sort((a, b) => {
            for (const ob of orderBy) {
                const colIdx = colIdxMap[ob.column.toLowerCase()];
                if (colIdx === undefined) continue;

                const valA = a[colIdx];
                const valB = b[colIdx];

                let cmp = 0;
                if (valA == null && valB == null) cmp = 0;
                else if (valA == null) cmp = 1;
                else if (valB == null) cmp = -1;
                else if (valA < valB) cmp = -1;
                else if (valA > valB) cmp = 1;

                if (cmp !== 0) {
                    return ob.descending ? -cmp : cmp;
                }
            }
            return 0;
        });
    }

    exprToName(expr) {
        if (!expr) return '?';
        switch (expr.type) {
            case 'column': return expr.name;
            case 'call': {
                const argStr = expr.args.map(a => {
                    if (a.type === 'star') return '*';
                    if (a.type === 'column') return a.name;
                    return '?';
                }).join(', ');
                return `${expr.name}(${argStr})`;
            }
            case 'literal': return String(expr.value);
            default: return '?';
        }
    }

    /**
     * Check if query is just SELECT COUNT(*) with no other columns
     */
    isSimpleCountStar(ast) {
        if (ast.columns.length !== 1) return false;
        const col = ast.columns[0];
        if (col.type === 'star') return true; // COUNT(*) parsed as star
        if (col.type === 'expr' && col.expr.type === 'call') {
            const name = col.expr.name.toUpperCase();
            if (name === 'COUNT') {
                const arg = col.expr.args[0];
                return arg?.type === 'star';
            }
        }
        return false;
    }

    /**
     * Execute aggregation query after running vector search
     */
    async executeAggregateWithSearch(ast, totalRows, onProgress) {
        // This is a simplified version - aggregate over search results
        // For now, just return an error/notice that this combination isn't fully supported
        return {
            columns: ['error'],
            rows: [['Aggregations with SEARCH not yet supported. Use SEARCH without aggregations, or aggregations without SEARCH.']],
            total: 1,
            aggregationStats: null,
        };
    }

    /**
     * Check if the query contains aggregate functions
     */
    hasAggregates(ast) {
        const aggFunctions = ['COUNT', 'SUM', 'AVG', 'MIN', 'MAX'];
        for (const col of ast.columns) {
            if (col.type === 'expr' && col.expr.type === 'call') {
                if (aggFunctions.includes(col.expr.name.toUpperCase())) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Execute an aggregation query
     */
    async executeAggregateQuery(ast, totalRows, onProgress) {
        const aggFunctions = ['COUNT', 'SUM', 'AVG', 'MIN', 'MAX'];

        // Initialize aggregators for each column
        const aggregators = [];
        const colNames = [];

        for (const col of ast.columns) {
            if (col.type === 'star') {
                // COUNT(*) case
                aggregators.push({ type: 'COUNT', column: null, isStar: true });
                colNames.push('COUNT(*)');
            } else if (col.expr.type === 'call' && aggFunctions.includes(col.expr.name.toUpperCase())) {
                const aggType = col.expr.name.toUpperCase();
                const argExpr = col.expr.args[0];
                const colName = argExpr?.type === 'column' ? argExpr.name : null;
                const isStar = argExpr?.type === 'star';

                aggregators.push({
                    type: aggType,
                    column: colName,
                    isStar,
                    sum: 0,
                    count: 0,
                    min: null,
                    max: null,
                });

                const displayName = col.alias || this.exprToName(col.expr);
                colNames.push(displayName);
            } else {
                // Non-aggregate column - just take first value (or could error)
                aggregators.push({
                    type: 'FIRST',
                    column: col.expr.type === 'column' ? col.expr.name : null,
                    value: null,
                });
                colNames.push(col.alias || this.exprToName(col.expr));
            }
        }

        // Determine which columns we need to read
        const neededCols = new Set();
        for (const agg of aggregators) {
            if (agg.column) {
                neededCols.add(agg.column.toLowerCase());
            }
        }

        // Also need columns from WHERE clause
        if (ast.where) {
            this.collectColumnsFromExpr(ast.where, neededCols);
        }

        // Process data in batches
        // Respect LIMIT - only scan up to LIMIT rows for aggregation
        const scanLimit = ast.limit || totalRows; // If no LIMIT, scan all (could be slow)
        const maxRowsToScan = Math.min(scanLimit, totalRows);
        const batchSize = 1000;
        let processedRows = 0;
        let scannedRows = 0;

        for (let batchStart = 0; batchStart < maxRowsToScan; batchStart += batchSize) {
            if (onProgress) {
                onProgress(`Aggregating...`, batchStart, maxRowsToScan);
            }

            const batchEnd = Math.min(batchStart + batchSize, maxRowsToScan);
            const batchIndices = Array.from({ length: batchEnd - batchStart }, (_, i) => batchStart + i);
            scannedRows += batchIndices.length;

            // Fetch needed column data for this batch
            const batchData = {};
            for (const colName of neededCols) {
                const colIdx = this.columnMap[colName.toLowerCase()];
                if (colIdx !== undefined) {
                    batchData[colName.toLowerCase()] = await this.readColumnData(colIdx, batchIndices);
                }
            }

            // Process each row in the batch
            for (let i = 0; i < batchIndices.length; i++) {
                // Apply WHERE filter if present
                if (ast.where) {
                    const matches = this.evaluateExpr(ast.where, batchData, i);
                    if (!matches) continue;
                }

                processedRows++;

                // Update aggregators
                for (const agg of aggregators) {
                    if (agg.type === 'COUNT') {
                        agg.count++;
                    } else if (agg.type === 'FIRST') {
                        if (agg.value === null && agg.column) {
                            const data = batchData[agg.column.toLowerCase()];
                            if (data) agg.value = data[i];
                        }
                    } else {
                        // SUM, AVG, MIN, MAX need column value
                        const data = agg.column ? batchData[agg.column.toLowerCase()] : null;
                        const val = data ? data[i] : null;

                        if (val !== null && val !== undefined && !isNaN(val)) {
                            agg.count++;
                            if (agg.type === 'SUM' || agg.type === 'AVG') {
                                agg.sum += val;
                            }
                            if (agg.type === 'MIN') {
                                agg.min = agg.min === null ? val : Math.min(agg.min, val);
                            }
                            if (agg.type === 'MAX') {
                                agg.max = agg.max === null ? val : Math.max(agg.max, val);
                            }
                        }
                    }
                }
            }
        }

        // Build result row
        const resultRow = [];
        for (const agg of aggregators) {
            switch (agg.type) {
                case 'COUNT':
                    resultRow.push(agg.count);
                    break;
                case 'SUM':
                    resultRow.push(agg.sum);
                    break;
                case 'AVG':
                    resultRow.push(agg.count > 0 ? agg.sum / agg.count : null);
                    break;
                case 'MIN':
                    resultRow.push(agg.min);
                    break;
                case 'MAX':
                    resultRow.push(agg.max);
                    break;
                case 'FIRST':
                    resultRow.push(agg.value);
                    break;
                default:
                    resultRow.push(null);
            }
        }

        // Calculate coverage stats
        const coveragePercent = totalRows > 0 ? ((scannedRows / totalRows) * 100).toFixed(2) : 100;
        const isPartialScan = scannedRows < totalRows;

        return {
            columns: colNames,
            rows: [resultRow],
            total: 1,
            aggregationStats: {
                scannedRows,
                totalRows,
                coveragePercent,
                isPartialScan,
            },
        };
    }
}

/**
 * Parse a SQL string and return the AST
 * @param {string} sql - SQL query string
 * @returns {object} - Parsed AST
 */
export function parseSQL(sql) {
    const lexer = new SQLLexer(sql);
    const tokens = lexer.tokenize();
    const parser = new SQLParser(tokens);
    return parser.parse();
}

/**
 * Represents a remote Lance dataset with multiple fragments.
 * Loads manifest to discover fragments and fetches data in parallel.
 */
export class RemoteLanceDataset {
    constructor(lanceql, baseUrl) {
        this.lanceql = lanceql;
        this.baseUrl = baseUrl.replace(/\/$/, ''); // Remove trailing slash
        this._fragments = [];
        this._schema = null;
        this._totalRows = 0;
        this._numColumns = 0;
        this._onFetch = null;
        this._fragmentFiles = new Map(); // Cache of opened RemoteLanceFile per fragment
        this._isRemote = true;
        this._ivfIndex = null; // IVF index for ANN search
        this._deletedRows = new Map(); // Cache of deleted row Sets per fragment index
    }

    /**
     * Open a remote Lance dataset.
     * @param {LanceQL} lanceql - LanceQL instance
     * @param {string} baseUrl - Base URL to the dataset
     * @param {object} [options] - Options
     * @param {number} [options.version] - Specific version to load (time-travel)
     * @param {boolean} [options.prefetch] - Prefetch fragment metadata (default: true for small datasets)
     * @returns {Promise<RemoteLanceDataset>}
     */
    static async open(lanceql, baseUrl, options = {}) {
        const dataset = new RemoteLanceDataset(lanceql, baseUrl);
        dataset._requestedVersion = options.version || null;

        // Try to load from cache first (unless skipCache is true)
        const cacheKey = options.version ? `${baseUrl}@v${options.version}` : baseUrl;
        if (!options.skipCache) {
            const cached = await metadataCache.get(cacheKey);
            if (cached && cached.schema && cached.fragments) {
                console.log(`[LanceQL Dataset] Using cached metadata for ${baseUrl}`);
                dataset._schema = cached.schema;
                dataset._fragments = cached.fragments;
                dataset._numColumns = cached.schema.length;
                dataset._totalRows = cached.fragments.reduce((sum, f) => sum + f.numRows, 0);
                dataset._version = cached.version;
                dataset._columnTypes = cached.columnTypes || null;
                dataset._fromCache = true;
            }
        }

        // If not cached, try sidecar first, then manifest
        if (!dataset._fromCache) {
            // Try to load .meta.json sidecar (faster, pre-calculated)
            const sidecarLoaded = await dataset._tryLoadSidecar();

            if (!sidecarLoaded) {
                // Fall back to parsing manifest
                await dataset._loadManifest();
            }

            // Cache the metadata for next time
            metadataCache.set(cacheKey, {
                schema: dataset._schema,
                fragments: dataset._fragments,
                version: dataset._version,
                columnTypes: dataset._columnTypes || null
            }).catch(() => {}); // Don't block on cache errors
        }

        await dataset._tryLoadIndex();

        // Prefetch fragment metadata for faster first query
        // Default: prefetch if <= 5 fragments
        const shouldPrefetch = options.prefetch ?? (dataset._fragments.length <= 5);
        if (shouldPrefetch && dataset._fragments.length > 0) {
            dataset._prefetchFragments();
        }

        return dataset;
    }

    /**
     * Try to load sidecar manifest (.meta.json) for faster startup.
     * @returns {Promise<boolean>} True if sidecar was loaded successfully
     * @private
     */
    async _tryLoadSidecar() {
        try {
            const sidecarUrl = `${this.baseUrl}/.meta.json`;
            const response = await fetch(sidecarUrl);

            if (!response.ok) {
                return false;
            }

            const sidecar = await response.json();

            // Validate sidecar format
            if (!sidecar.schema || !sidecar.fragments) {
                console.warn('[LanceQL Dataset] Invalid sidecar format');
                return false;
            }

            console.log(`[LanceQL Dataset] Loaded sidecar manifest`);

            // Convert sidecar schema to internal format
            this._schema = sidecar.schema.map(col => ({
                name: col.name,
                id: col.index,
                type: col.type
            }));

            // Convert sidecar fragments to internal format
            this._fragments = sidecar.fragments.map(frag => ({
                id: frag.id,
                path: frag.data_files?.[0] || `${frag.id}.lance`,
                numRows: frag.num_rows,
                physicalRows: frag.physical_rows || frag.num_rows,
                url: `${this.baseUrl}/data/${frag.data_files?.[0] || frag.id + '.lance'}`,
                deletionFile: frag.has_deletions ? { numDeletedRows: frag.deleted_rows || 0 } : null
            }));

            this._numColumns = sidecar.num_columns;
            this._totalRows = sidecar.total_rows;
            this._version = sidecar.lance_version;

            // Extract column types from sidecar schema
            this._columnTypes = sidecar.schema.map(col => {
                const type = col.type;
                if (type.startsWith('vector[')) return 'vector';
                if (type === 'float64' || type === 'double') return 'float64';
                if (type === 'float32') return 'float32';
                if (type.includes('int')) return type;
                if (type === 'string') return 'string';
                return 'unknown';
            });

            return true;
        } catch (e) {
            // Sidecar not available or invalid - fall back to manifest
            return false;
        }
    }

    /**
     * Prefetch fragment metadata (footers) in parallel.
     * Does not block - runs in background.
     * @private
     */
    _prefetchFragments() {
        const prefetchPromises = this._fragments.map((_, idx) =>
            this.openFragment(idx).catch(() => null)
        );
        // Run in background, don't await
        Promise.all(prefetchPromises).then(() => {
            console.log(`[LanceQL Dataset] Prefetched ${this._fragments.length} fragment(s)`);
        });
    }

    /**
     * Check if dataset has an IVF index loaded.
     */
    hasIndex() {
        return this._ivfIndex !== null && this._ivfIndex.centroids !== null;
    }

    /**
     * Try to load IVF index from _indices folder.
     * @private
     */
    async _tryLoadIndex() {
        try {
            console.log(`[LanceQL Dataset] Trying to load IVF index from ${this.baseUrl}`);
            this._ivfIndex = await IVFIndex.tryLoad(this.baseUrl);
            if (this._ivfIndex) {
                console.log(`[LanceQL Dataset] IVF index loaded: ${this._ivfIndex.numPartitions} partitions, dim=${this._ivfIndex.dimension}`);
            } else {
                console.log('[LanceQL Dataset] IVF index not found or failed to parse');
            }
        } catch (e) {
            console.log('[LanceQL Dataset] No IVF index found:', e.message);
            this._ivfIndex = null;
        }
    }

    /**
     * Load and parse the manifest to discover fragments.
     * @private
     */
    async _loadManifest() {
        let manifestData = null;
        let manifestVersion = 0;

        // If specific version requested (time-travel), use that
        if (this._requestedVersion) {
            manifestVersion = this._requestedVersion;
            const manifestUrl = `${this.baseUrl}/_versions/${manifestVersion}.manifest`;
            const response = await fetch(manifestUrl);
            if (!response.ok) {
                throw new Error(`Version ${manifestVersion} not found (${response.status})`);
            }
            manifestData = new Uint8Array(await response.arrayBuffer());
        } else {
            // Find the latest manifest version using binary search approach
            // First check common versions in parallel
            const checkVersions = [1, 5, 10, 20, 50, 100];
            const checks = await Promise.all(
                checkVersions.map(async v => {
                    try {
                        const url = `${this.baseUrl}/_versions/${v}.manifest`;
                        const response = await fetch(url, { method: 'HEAD' });
                        return response.ok ? v : 0;
                    } catch {
                        return 0;
                    }
                })
            );

            // Find highest existing version from quick check
            let highestFound = Math.max(...checks);

            // If we found a high version, scan forward from there
            if (highestFound > 0) {
                for (let v = highestFound + 1; v <= highestFound + 50; v++) {
                    try {
                        const url = `${this.baseUrl}/_versions/${v}.manifest`;
                        const response = await fetch(url, { method: 'HEAD' });
                        if (response.ok) {
                            highestFound = v;
                        } else {
                            break;
                        }
                    } catch {
                        break;
                    }
                }
            }

            manifestVersion = highestFound;

            if (manifestVersion === 0) {
                throw new Error('No manifest found in dataset');
            }

            // Fetch the latest manifest
            const manifestUrl = `${this.baseUrl}/_versions/${manifestVersion}.manifest`;
            const response = await fetch(manifestUrl);
            if (!response.ok) {
                throw new Error(`Failed to fetch manifest: ${response.status}`);
            }
            manifestData = new Uint8Array(await response.arrayBuffer());
        }

        // Store the version we loaded
        this._version = manifestVersion;
        this._latestVersion = this._requestedVersion ? null : manifestVersion;

        console.log(`[LanceQL Dataset] Loading manifest v${manifestVersion}${this._requestedVersion ? ' (time-travel)' : ''}...`);
        this._parseManifest(manifestData);

        console.log(`[LanceQL Dataset] Loaded: ${this._fragments.length} fragments, ${this._totalRows.toLocaleString()} rows, ${this._numColumns} columns`);
    }

    /**
     * Get list of available versions.
     * @returns {Promise<number[]>}
     */
    async listVersions() {
        const versions = [];
        // Scan for versions 1 to latestVersion (or 100 if unknown)
        const maxVersion = this._latestVersion || 100;

        const checks = await Promise.all(
            Array.from({ length: maxVersion }, (_, i) => i + 1).map(async v => {
                try {
                    const url = `${this.baseUrl}/_versions/${v}.manifest`;
                    const response = await fetch(url, { method: 'HEAD' });
                    return response.ok ? v : 0;
                } catch {
                    return 0;
                }
            })
        );

        return checks.filter(v => v > 0);
    }

    /**
     * Get current loaded version.
     */
    get version() {
        return this._version;
    }

    /**
     * Parse manifest protobuf to extract schema and fragment info.
     *
     * Lance manifest file structure:
     * - Chunk 1 (len-prefixed): Transaction metadata (may be small/incremental)
     * - Chunk 2 (len-prefixed): Full manifest with schema + fragments
     * - Footer (16 bytes): Offsets + "LANC" magic
     *
     * @private
     */
    _parseManifest(bytes) {
        const view = new DataView(bytes.buffer, bytes.byteOffset);

        // Read chunk 1 length
        const chunk1Len = view.getUint32(0, true);

        // Check if there's a chunk 2 (full manifest data)
        // Chunk 2 starts at offset (4 + chunk1Len)
        const chunk2Start = 4 + chunk1Len;
        let protoData;

        if (chunk2Start + 4 < bytes.length) {
            const chunk2Len = view.getUint32(chunk2Start, true);
            // Verify chunk 2 exists and has reasonable size
            if (chunk2Len > 0 && chunk2Start + 4 + chunk2Len <= bytes.length) {
                // Use chunk 2 (full manifest)
                protoData = bytes.slice(chunk2Start + 4, chunk2Start + 4 + chunk2Len);
            } else {
                // Fall back to chunk 1
                protoData = bytes.slice(4, 4 + chunk1Len);
            }
        } else {
            // Only chunk 1 exists
            protoData = bytes.slice(4, 4 + chunk1Len);
        }

        let pos = 0;
        const fields = [];
        const fragments = [];

        const readVarint = () => {
            let result = 0;
            let shift = 0;
            while (pos < protoData.length) {
                const byte = protoData[pos++];
                result |= (byte & 0x7F) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7;
            }
            return result;
        };

        const skipField = (wireType) => {
            if (wireType === 0) {
                readVarint();
            } else if (wireType === 2) {
                const len = readVarint();
                pos += len;
            } else if (wireType === 5) {
                pos += 4;
            } else if (wireType === 1) {
                pos += 8;
            }
        };

        // Parse top-level Manifest message
        while (pos < protoData.length) {
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (fieldNum === 1 && wireType === 2) {
                // Field 1 = schema (repeated Field message)
                const fieldLen = readVarint();
                const fieldEnd = pos + fieldLen;

                let name = null;
                let id = null;
                let logicalType = null;

                while (pos < fieldEnd) {
                    const fTag = readVarint();
                    const fNum = fTag >> 3;
                    const fWire = fTag & 0x7;

                    if (fWire === 0) {
                        const val = readVarint();
                        if (fNum === 3) id = val;
                    } else if (fWire === 2) {
                        const len = readVarint();
                        const content = protoData.slice(pos, pos + len);
                        pos += len;

                        if (fNum === 2) {
                            name = new TextDecoder().decode(content);
                        } else if (fNum === 5) {
                            logicalType = new TextDecoder().decode(content);
                        }
                    } else {
                        skipField(fWire);
                    }
                }

                if (name) {
                    fields.push({ name, id, type: logicalType });
                }
            } else if (fieldNum === 2 && wireType === 2) {
                // Field 2 = fragments (repeated Fragment message)
                const fragLen = readVarint();
                const fragEnd = pos + fragLen;

                let fragId = null;
                let filePath = null;
                let numRows = 0;
                let deletionFile = null;  // Track deletion info

                while (pos < fragEnd) {
                    const fTag = readVarint();
                    const fNum = fTag >> 3;
                    const fWire = fTag & 0x7;

                    if (fWire === 0) {
                        const val = readVarint();
                        if (fNum === 1) fragId = val;  // Fragment.id
                        else if (fNum === 4) numRows = val;  // Fragment.physical_rows
                    } else if (fWire === 2) {
                        const len = readVarint();
                        const content = protoData.slice(pos, pos + len);
                        pos += len;

                        if (fNum === 2) {
                            // Fragment.files - parse DataFile message
                            let innerPos = 0;
                            while (innerPos < content.length) {
                                const iTag = content[innerPos++];
                                const iNum = iTag >> 3;
                                const iWire = iTag & 0x7;

                                if (iWire === 2) {
                                    // Length-delimited
                                    let iLen = 0;
                                    let iShift = 0;
                                    while (innerPos < content.length) {
                                        const b = content[innerPos++];
                                        iLen |= (b & 0x7F) << iShift;
                                        if ((b & 0x80) === 0) break;
                                        iShift += 7;
                                    }
                                    const iContent = content.slice(innerPos, innerPos + iLen);
                                    innerPos += iLen;

                                    if (iNum === 1) {
                                        // DataFile.path
                                        filePath = new TextDecoder().decode(iContent);
                                    }
                                } else if (iWire === 0) {
                                    // Varint - skip
                                    while (innerPos < content.length && (content[innerPos++] & 0x80) !== 0);
                                } else if (iWire === 5) {
                                    innerPos += 4;
                                } else if (iWire === 1) {
                                    innerPos += 8;
                                }
                            }
                        } else if (fNum === 3) {
                            // Fragment.deletion_file - parse DeletionFile message
                            deletionFile = this._parseDeletionFile(content, fragId);
                        }
                    } else {
                        skipField(fWire);
                    }
                }

                if (filePath) {
                    const logicalRows = deletionFile ? numRows - deletionFile.numDeletedRows : numRows;
                    fragments.push({
                        id: fragId,
                        path: filePath,
                        numRows: logicalRows,  // Logical rows (excluding deleted)
                        physicalRows: numRows, // Physical rows (including deleted)
                        deletionFile: deletionFile,
                        url: `${this.baseUrl}/data/${filePath}`
                    });
                }
            } else {
                skipField(wireType);
            }
        }

        this._schema = fields;
        this._fragments = fragments;
        this._numColumns = fields.length;
        this._totalRows = fragments.reduce((sum, f) => sum + f.numRows, 0);

        // Track if any fragment has deletions
        const deletedCount = fragments.reduce((sum, f) => sum + (f.deletionFile?.numDeletedRows || 0), 0);
        if (deletedCount > 0) {
            console.log(`[LanceQL Dataset] Has ${deletedCount} deleted rows across fragments`);
        }
    }

    /**
     * Parse DeletionFile protobuf message.
     * @param {Uint8Array} data - Raw protobuf bytes
     * @param {number} fragId - Fragment ID for path construction
     * @returns {Object|null} Deletion file info
     * @private
     */
    _parseDeletionFile(data, fragId) {
        let fileType = 0;  // 0 = ARROW_ARRAY, 1 = BITMAP
        let readVersion = 0;
        let id = 0;
        let numDeletedRows = 0;

        let pos = 0;
        const readVarint = () => {
            let result = 0;
            let shift = 0;
            while (pos < data.length) {
                const b = data[pos++];
                result |= (b & 0x7F) << shift;
                if ((b & 0x80) === 0) break;
                shift += 7;
            }
            return result;
        };

        while (pos < data.length) {
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (wireType === 0) {
                const val = readVarint();
                if (fieldNum === 1) fileType = val;       // DeletionFile.file_type
                else if (fieldNum === 2) readVersion = val; // DeletionFile.read_version
                else if (fieldNum === 3) id = val;        // DeletionFile.id
                else if (fieldNum === 4) numDeletedRows = val; // DeletionFile.num_deleted_rows
            } else if (wireType === 2) {
                const len = readVarint();
                pos += len; // Skip length-delimited fields
            } else if (wireType === 5) {
                pos += 4;
            } else if (wireType === 1) {
                pos += 8;
            }
        }

        if (numDeletedRows === 0) return null;

        const ext = fileType === 0 ? 'arrow' : 'bin';
        const path = `_deletions/${fragId}-${readVersion}-${id}.${ext}`;

        return {
            fileType: fileType === 0 ? 'arrow' : 'bitmap',
            readVersion,
            id,
            numDeletedRows,
            path,
            url: `${this.baseUrl}/${path}`
        };
    }

    /**
     * Load deleted row indices for a fragment.
     * @param {number} fragmentIndex - Fragment index
     * @returns {Promise<Set<number>>} Set of deleted row indices (local to fragment)
     * @private
     */
    async _loadDeletedRows(fragmentIndex) {
        // Check cache
        if (this._deletedRows.has(fragmentIndex)) {
            return this._deletedRows.get(fragmentIndex);
        }

        const frag = this._fragments[fragmentIndex];
        if (!frag?.deletionFile) {
            const emptySet = new Set();
            this._deletedRows.set(fragmentIndex, emptySet);
            return emptySet;
        }

        const { url, fileType, numDeletedRows } = frag.deletionFile;
        console.log(`[LanceQL] Loading ${numDeletedRows} deletions from ${url} (${fileType})`);

        try {
            const response = await fetch(url);
            if (!response.ok) {
                console.warn(`[LanceQL] Failed to load deletion file: ${response.status}`);
                const emptySet = new Set();
                this._deletedRows.set(fragmentIndex, emptySet);
                return emptySet;
            }

            const buffer = await response.arrayBuffer();
            const data = new Uint8Array(buffer);
            let deletedSet;

            if (fileType === 'arrow') {
                deletedSet = this._parseArrowDeletions(data);
            } else {
                deletedSet = this._parseRoaringBitmap(data);
            }

            console.log(`[LanceQL] Loaded ${deletedSet.size} deleted rows for fragment ${fragmentIndex}`);
            this._deletedRows.set(fragmentIndex, deletedSet);
            return deletedSet;
        } catch (e) {
            console.error(`[LanceQL] Error loading deletion file:`, e);
            const emptySet = new Set();
            this._deletedRows.set(fragmentIndex, emptySet);
            return emptySet;
        }
    }

    /**
     * Parse Arrow IPC deletion file (Int32Array of deleted indices).
     * @param {Uint8Array} data - Raw Arrow IPC bytes
     * @returns {Set<number>} Set of deleted row indices
     * @private
     */
    _parseArrowDeletions(data) {
        // Arrow IPC format: Magic (ARROW1) + schema + record batch
        // For simplicity, we look for the Int32 data after the schema
        const deletedSet = new Set();

        // Find continuation marker (-1 as int32 LE = 0xFFFFFFFF)
        // Then record batch metadata length, then metadata, then body (Int32 array)
        let pos = 0;

        // Skip magic "ARROW1" + padding
        if (data.length >= 8 && String.fromCharCode(...data.slice(0, 6)) === 'ARROW1') {
            pos = 8;
        }

        // Look for continuation markers and skip metadata
        const view = new DataView(data.buffer, data.byteOffset, data.byteLength);

        while (pos < data.length - 4) {
            const marker = view.getInt32(pos, true);
            if (marker === -1) {
                // Continuation marker found
                pos += 4;
                if (pos + 4 > data.length) break;
                const metaLen = view.getInt32(pos, true);
                pos += 4 + metaLen; // Skip metadata

                // The body follows - for deletion vectors it's just Int32 array
                // We need to read until end or next message
                while (pos + 4 <= data.length) {
                    // Check if this looks like the start of data (not another marker)
                    const nextMarker = view.getInt32(pos, true);
                    if (nextMarker === -1) break; // Another message starts

                    // Read Int32 values until we hit something that looks like a marker
                    // or reach expected count
                    const val = view.getInt32(pos, true);
                    if (val >= 0 && val < 10000000) { // Sanity check
                        deletedSet.add(val);
                    }
                    pos += 4;
                }
            } else {
                pos++;
            }
        }

        return deletedSet;
    }

    /**
     * Parse Roaring Bitmap deletion file.
     * @param {Uint8Array} data - Raw Roaring Bitmap bytes
     * @returns {Set<number>} Set of deleted row indices
     * @private
     */
    _parseRoaringBitmap(data) {
        // Roaring bitmap format: header + containers
        // This is a simplified parser for common cases
        const deletedSet = new Set();
        const view = new DataView(data.buffer, data.byteOffset, data.byteLength);

        if (data.length < 8) return deletedSet;

        // Read cookie (first 4 bytes indicate format)
        const cookie = view.getUint32(0, true);

        // Standard roaring format: cookie = 12346 or 12347
        // Portable format: first 8 bytes are magic
        if (cookie === 12346 || cookie === 12347) {
            // Standard format
            const isRunContainer = (cookie === 12347);
            let pos = 4;

            // Number of containers
            const numContainers = view.getUint16(pos, true);
            pos += 2;

            // Skip to container data
            // Each key is 2 bytes, each cardinality is 2 bytes
            const keysStart = pos;
            pos += numContainers * 4; // keys + cardinalities

            for (let i = 0; i < numContainers && pos < data.length; i++) {
                const key = view.getUint16(keysStart + i * 4, true);
                const card = view.getUint16(keysStart + i * 4 + 2, true) + 1;
                const baseValue = key << 16;

                // Read container values (simplified - assumes array container)
                for (let j = 0; j < card && pos + 2 <= data.length; j++) {
                    const lowBits = view.getUint16(pos, true);
                    deletedSet.add(baseValue | lowBits);
                    pos += 2;
                }
            }
        }

        return deletedSet;
    }

    /**
     * Check if a row is deleted in a fragment.
     * @param {number} fragmentIndex - Fragment index
     * @param {number} localRowIndex - Row index within the fragment
     * @returns {Promise<boolean>} True if row is deleted
     */
    async isRowDeleted(fragmentIndex, localRowIndex) {
        const deletedSet = await this._loadDeletedRows(fragmentIndex);
        return deletedSet.has(localRowIndex);
    }

    /**
     * Get number of columns.
     */
    get numColumns() {
        return this._numColumns;
    }

    /**
     * Get total row count across all fragments.
     */
    get rowCount() {
        return this._totalRows;
    }

    /**
     * Get row count for a column (for API compatibility with RemoteLanceFile).
     * @param {number} columnIndex - Column index (ignored, all columns have same row count)
     * @returns {Promise<number>}
     */
    async getRowCount(columnIndex = 0) {
        return this._totalRows;
    }

    /**
     * Read a single vector at a global row index.
     * Delegates to the correct fragment based on row index.
     * @param {number} colIdx - Column index
     * @param {number} rowIdx - Global row index
     * @returns {Promise<Float32Array>}
     */
    async readVectorAt(colIdx, rowIdx) {
        const loc = this._getFragmentForRow(rowIdx);
        if (!loc) return new Float32Array(0);
        const file = await this.openFragment(loc.fragmentIndex);
        return await file.readVectorAt(colIdx, loc.localIndex);
    }

    /**
     * Get vector info for a column by querying first fragment.
     * @param {number} colIdx - Column index
     * @returns {Promise<{rows: number, dimension: number}>}
     */
    async getVectorInfo(colIdx) {
        if (this._fragments.length === 0) {
            return { rows: 0, dimension: 0 };
        }

        // Get vector info from first fragment
        const file = await this.openFragment(0);
        const fragInfo = await file.getVectorInfo(colIdx);

        if (fragInfo.dimension === 0) {
            return { rows: 0, dimension: 0 };
        }

        // Return total rows across all fragments, dimension from first fragment
        return {
            rows: this._totalRows,
            dimension: fragInfo.dimension
        };
    }

    /**
     * Get column names from schema.
     */
    get columnNames() {
        return this._schema ? this._schema.map(f => f.name) : [];
    }

    /**
     * Get full schema.
     */
    get schema() {
        return this._schema;
    }

    /**
     * Get fragment list.
     */
    get fragments() {
        return this._fragments;
    }

    /**
     * Get total size (sum of all fragment files).
     */
    get size() {
        // Estimate based on fragments
        return this._fragments.length * 100 * 1024 * 1024; // ~100MB per fragment estimate
    }

    /**
     * Set callback for network fetch events.
     */
    onFetch(callback) {
        this._onFetch = callback;
    }

    /**
     * Open a specific fragment as RemoteLanceFile.
     * @param {number} fragmentIndex - Index of fragment to open
     * @returns {Promise<RemoteLanceFile>}
     */
    async openFragment(fragmentIndex) {
        if (fragmentIndex < 0 || fragmentIndex >= this._fragments.length) {
            throw new Error(`Invalid fragment index: ${fragmentIndex}`);
        }

        // Check cache
        if (this._fragmentFiles.has(fragmentIndex)) {
            return this._fragmentFiles.get(fragmentIndex);
        }

        const fragment = this._fragments[fragmentIndex];
        const file = await RemoteLanceFile.open(this.lanceql, fragment.url);

        // Propagate fetch callback
        if (this._onFetch) {
            file.onFetch(this._onFetch);
        }

        this._fragmentFiles.set(fragmentIndex, file);
        return file;
    }

    /**
     * Read rows from the dataset with pagination.
     * Fetches from multiple fragments in parallel.
     * @param {Object} options - Query options
     * @param {number} options.offset - Starting row offset
     * @param {number} options.limit - Maximum rows to return
     * @param {number[]} options.columns - Column indices to read (optional)
     * @param {boolean} options._isPrefetch - Internal flag to prevent recursive prefetch
     * @returns {Promise<{columns: Array[], columnNames: string[], total: number}>}
     */
    async readRows({ offset = 0, limit = 50, columns = null, _isPrefetch = false } = {}) {
        // Determine which fragments contain the requested rows
        const fragmentRanges = [];
        let currentOffset = 0;

        for (let i = 0; i < this._fragments.length; i++) {
            const frag = this._fragments[i];
            const fragStart = currentOffset;
            const fragEnd = currentOffset + frag.numRows;

            // Check if this fragment overlaps with requested range
            if (fragEnd > offset && fragStart < offset + limit) {
                const localStart = Math.max(0, offset - fragStart);
                const localEnd = Math.min(frag.numRows, offset + limit - fragStart);

                fragmentRanges.push({
                    fragmentIndex: i,
                    localOffset: localStart,
                    localLimit: localEnd - localStart,
                    globalStart: fragStart + localStart
                });
            }

            currentOffset = fragEnd;
            if (currentOffset >= offset + limit) break;
        }

        if (fragmentRanges.length === 0) {
            return { columns: [], columnNames: this.columnNames, total: this._totalRows };
        }

        // Fetch from fragments in parallel
        const fetchPromises = fragmentRanges.map(async (range) => {
            const file = await this.openFragment(range.fragmentIndex);
            const result = await file.readRows({
                offset: range.localOffset,
                limit: range.localLimit,
                columns: columns
            });
            return { ...range, result };
        });

        const results = await Promise.all(fetchPromises);

        // Merge results in order
        results.sort((a, b) => a.globalStart - b.globalStart);

        const mergedColumns = [];
        const colNames = results[0]?.result.columnNames || this.columnNames;
        const numCols = columns ? columns.length : this._numColumns;

        for (let c = 0; c < numCols; c++) {
            const colData = [];
            for (const r of results) {
                if (r.result.columns[c]) {
                    colData.push(...r.result.columns[c]);
                }
            }
            mergedColumns.push(colData);
        }

        const result = {
            columns: mergedColumns,
            columnNames: colNames,
            total: this._totalRows
        };

        // Speculative prefetch: if there are more rows, prefetch next page in background
        // Only prefetch if: not already a prefetch, limit is reasonable, more rows exist
        const nextOffset = offset + limit;
        if (!_isPrefetch && nextOffset < this._totalRows && limit <= 100) {
            this._prefetchNextPage(nextOffset, limit, columns);
        }

        return result;
    }

    /**
     * Prefetch next page of rows in background.
     * @private
     */
    _prefetchNextPage(offset, limit, columns) {
        // Use a cache key to avoid duplicate prefetches
        const cacheKey = `${offset}-${limit}-${columns?.join(',') || 'all'}`;
        if (this._prefetchCache?.has(cacheKey)) {
            return; // Already prefetching or prefetched
        }

        if (!this._prefetchCache) {
            this._prefetchCache = new Map();
        }

        // Start prefetch in background (don't await)
        const prefetchPromise = this.readRows({ offset, limit, columns, _isPrefetch: true })
            .then(result => {
                this._prefetchCache.set(cacheKey, result);
                console.log(`[LanceQL] Prefetched rows ${offset}-${offset + limit}`);
            })
            .catch(() => {
                // Ignore prefetch errors
            });

        this._prefetchCache.set(cacheKey, prefetchPromise);
    }

    /**
     * Detect column types by sampling from first fragment.
     * @returns {Promise<string[]>}
     */
    async detectColumnTypes() {
        // Return cached types if available
        if (this._columnTypes && this._columnTypes.length > 0) {
            return this._columnTypes;
        }

        if (this._fragments.length === 0) {
            return [];
        }
        const file = await this.openFragment(0);
        const types = await file.detectColumnTypes();
        this._columnTypes = types;

        // Update cache with column types
        const cacheKey = this._requestedVersion ? `${this.baseUrl}@v${this._requestedVersion}` : this.baseUrl;
        metadataCache.get(cacheKey).then(cached => {
            if (cached) {
                cached.columnTypes = types;
                metadataCache.set(cacheKey, cached).catch(() => {});
            }
        }).catch(() => {});

        return types;
    }

    /**
     * Helper to determine which fragment contains a given row index.
     * @private
     */
    _getFragmentForRow(rowIdx) {
        let offset = 0;
        for (let i = 0; i < this._fragments.length; i++) {
            const frag = this._fragments[i];
            if (rowIdx < offset + frag.numRows) {
                return { fragmentIndex: i, localIndex: rowIdx - offset };
            }
            offset += frag.numRows;
        }
        return null;
    }

    /**
     * Group indices by fragment for efficient batch reading.
     * @private
     */
    _groupIndicesByFragment(indices) {
        const groups = new Map();
        for (const globalIdx of indices) {
            const loc = this._getFragmentForRow(globalIdx);
            if (!loc) continue;

            if (!groups.has(loc.fragmentIndex)) {
                groups.set(loc.fragmentIndex, { localIndices: [], globalIndices: [] });
            }
            groups.get(loc.fragmentIndex).localIndices.push(loc.localIndex);
            groups.get(loc.fragmentIndex).globalIndices.push(globalIdx);
        }
        return groups;
    }

    /**
     * Read strings at specific indices across fragments.
     */
    async readStringsAtIndices(colIdx, indices) {
        const groups = this._groupIndicesByFragment(indices);
        const results = new Map();

        console.log(`[ReadStrings] Reading ${indices.length} strings from col ${colIdx}`);
        console.log(`[ReadStrings] First 5 indices: ${indices.slice(0, 5)}`);
        console.log(`[ReadStrings] Fragment groups: ${Array.from(groups.keys())}`);

        // Fetch from each fragment in parallel
        const fetchPromises = [];
        for (const [fragIdx, group] of groups) {
            fetchPromises.push((async () => {
                const file = await this.openFragment(fragIdx);
                console.log(`[ReadStrings] Fragment ${fragIdx}: reading ${group.localIndices.length} strings, first local indices: ${group.localIndices.slice(0, 3)}`);
                const data = await file.readStringsAtIndices(colIdx, group.localIndices);
                console.log(`[ReadStrings] Fragment ${fragIdx}: got ${data.length} strings, first 3: ${data.slice(0, 3).map(s => s?.slice(0, 20) + '...')}`);
                for (let i = 0; i < group.globalIndices.length; i++) {
                    results.set(group.globalIndices[i], data[i]);
                }
            })());
        }
        await Promise.all(fetchPromises);

        // Return in original order
        return indices.map(idx => results.get(idx) || null);
    }

    /**
     * Read int64 values at specific indices across fragments.
     */
    async readInt64AtIndices(colIdx, indices) {
        const groups = this._groupIndicesByFragment(indices);
        const results = new Map();

        const fetchPromises = [];
        for (const [fragIdx, group] of groups) {
            fetchPromises.push((async () => {
                const file = await this.openFragment(fragIdx);
                const data = await file.readInt64AtIndices(colIdx, group.localIndices);
                for (let i = 0; i < group.globalIndices.length; i++) {
                    results.set(group.globalIndices[i], data[i]);
                }
            })());
        }
        await Promise.all(fetchPromises);

        return new BigInt64Array(indices.map(idx => results.get(idx) || 0n));
    }

    /**
     * Read float64 values at specific indices across fragments.
     */
    async readFloat64AtIndices(colIdx, indices) {
        const groups = this._groupIndicesByFragment(indices);
        const results = new Map();

        const fetchPromises = [];
        for (const [fragIdx, group] of groups) {
            fetchPromises.push((async () => {
                const file = await this.openFragment(fragIdx);
                const data = await file.readFloat64AtIndices(colIdx, group.localIndices);
                for (let i = 0; i < group.globalIndices.length; i++) {
                    results.set(group.globalIndices[i], data[i]);
                }
            })());
        }
        await Promise.all(fetchPromises);

        return new Float64Array(indices.map(idx => results.get(idx) || 0));
    }

    /**
     * Read int32 values at specific indices across fragments.
     */
    async readInt32AtIndices(colIdx, indices) {
        const groups = this._groupIndicesByFragment(indices);
        const results = new Map();

        const fetchPromises = [];
        for (const [fragIdx, group] of groups) {
            fetchPromises.push((async () => {
                const file = await this.openFragment(fragIdx);
                const data = await file.readInt32AtIndices(colIdx, group.localIndices);
                for (let i = 0; i < group.globalIndices.length; i++) {
                    results.set(group.globalIndices[i], data[i]);
                }
            })());
        }
        await Promise.all(fetchPromises);

        return new Int32Array(indices.map(idx => results.get(idx) || 0));
    }

    /**
     * Read float32 values at specific indices across fragments.
     */
    async readFloat32AtIndices(colIdx, indices) {
        const groups = this._groupIndicesByFragment(indices);
        const results = new Map();

        const fetchPromises = [];
        for (const [fragIdx, group] of groups) {
            fetchPromises.push((async () => {
                const file = await this.openFragment(fragIdx);
                const data = await file.readFloat32AtIndices(colIdx, group.localIndices);
                for (let i = 0; i < group.globalIndices.length; i++) {
                    results.set(group.globalIndices[i], data[i]);
                }
            })());
        }
        await Promise.all(fetchPromises);

        return new Float32Array(indices.map(idx => results.get(idx) || 0));
    }

    /**
     * Vector search across all fragments.
     * API compatible with RemoteLanceFile.vectorSearch.
     *
     * @param {number} colIdx - Vector column index
     * @param {Float32Array} queryVec - Query vector
     * @param {number} topK - Number of results to return
     * @param {Function} onProgress - Progress callback (current, total)
     * @param {Object} options - Search options
     * @returns {Promise<{indices: number[], scores: number[], usedIndex: boolean}>}
     */
    async vectorSearch(colIdx, queryVec, topK = 10, onProgress = null, options = {}) {
        const {
            normalized = true,
            workerPool = null,
            useIndex = true,
            nprobe = 20
        } = options;

        const vectorColIdx = colIdx;

        if (vectorColIdx < 0) {
            throw new Error('No vector column found in dataset');
        }

        const dim = queryVec.length;
        console.log(`[VectorSearch] Query dim=${dim}, topK=${topK}, fragments=${this._fragments.length}, hasIndex=${this.hasIndex()}`);

        // Require IVF index for efficient search - no brute force fallback
        if (!this.hasIndex()) {
            throw new Error('No IVF index found. Vector search requires an IVF index for efficient querying.');
        }

        if (this._ivfIndex.dimension !== dim) {
            throw new Error(`Query dimension (${dim}) does not match index dimension (${this._ivfIndex.dimension}).`);
        }

        if (!this._ivfIndex.hasPartitionIndex) {
            throw new Error('IVF partition index (ivf_partitions.bin) not found. Required for efficient search.');
        }

        console.log(`[VectorSearch] Using IVF index (nprobe=${nprobe})`);
        return await this._ivfIndexSearch(queryVec, topK, vectorColIdx, nprobe, onProgress);
    }

    /**
     * IVF index-based ANN search.
     * Fetches partition data (row IDs + vectors) directly from ivf_vectors.bin.
     * This is much faster than fetching scattered vectors from Lance files.
     * @private
     */
    async _ivfIndexSearch(queryVec, topK, vectorColIdx, nprobe, onProgress) {
        // Find nearest partitions using centroids
        const partitions = this._ivfIndex.findNearestPartitions(queryVec, nprobe);
        console.log(`[VectorSearch] Searching ${partitions.length} partitions:`, partitions);

        // Fetch partition data (row IDs + vectors) directly
        const partitionData = await this._ivfIndex.fetchPartitionData(
            partitions,
            this._ivfIndex.dimension,
            (loaded, total) => {
                if (onProgress) {
                    const pct = total > 0 ? loaded / total : 0;
                    onProgress(Math.floor(pct * 100), 100);
                }
            }
        );

        if (!partitionData || partitionData.rowIds.length === 0) {
            throw new Error('IVF index not available. This dataset requires ivf_vectors.bin for efficient search.');
        }

        const { rowIds, vectors } = partitionData;
        console.log(`[VectorSearch] Computing similarities for ${rowIds.length.toLocaleString()} vectors`);

        // Compute similarities - vectors are already loaded, no more network requests!
        const allResults = [];
        for (let i = 0; i < rowIds.length; i++) {
            const vec = vectors[i];
            if (!vec || vec.length !== queryVec.length) continue;

            // Cosine similarity (vectors should be normalized)
            let dot = 0;
            for (let k = 0; k < queryVec.length; k++) {
                dot += queryVec[k] * vec[k];
            }
            allResults.push({ index: rowIds[i], score: dot });
        }

        // Sort and take top-k
        allResults.sort((a, b) => b.score - a.score);
        const finalK = Math.min(topK, allResults.length);

        if (onProgress) onProgress(100, 100);

        return {
            indices: allResults.slice(0, finalK).map(r => r.index),
            scores: allResults.slice(0, finalK).map(r => r.score),
            usedIndex: true,
            searchedRows: rowIds.length
        };
    }

    /**
     * Find the vector column index by looking at schema.
     * @private
     */
    _findVectorColumn() {
        if (!this._schema) return -1;

        for (let i = 0; i < this._schema.length; i++) {
            const field = this._schema[i];
            if (field.name === 'embedding' || field.name === 'vector' ||
                field.type === 'fixed_size_list' || field.type === 'list') {
                return i;
            }
        }

        // Assume last column is vector if schema unclear
        return this._schema.length - 1;
    }

    /**
     * Parallel vector search using WorkerPool.
     * @private
     */
    async _parallelVectorSearch(query, topK, vectorColIdx, normalized, workerPool) {
        const dim = query.length;

        // Load vectors from each fragment in parallel
        const chunkPromises = this._fragments.map(async (frag, idx) => {
            const file = await this.openFragment(idx);

            // Get vector data for this fragment
            const vectors = await file.readVectorColumn(vectorColIdx);
            if (!vectors || vectors.length === 0) {
                return null;
            }

            // Calculate start index for this fragment
            let startIndex = 0;
            for (let i = 0; i < idx; i++) {
                startIndex += this._fragments[i].numRows;
            }

            return {
                vectors: new Float32Array(vectors),
                startIndex,
                numVectors: vectors.length / dim
            };
        });

        const chunks = (await Promise.all(chunkPromises)).filter(c => c !== null);

        if (chunks.length === 0) {
            return { indices: new Uint32Array(0), scores: new Float32Array(0), rows: [] };
        }

        // Perform parallel search
        const { indices, scores } = await workerPool.parallelVectorSearch(
            query, chunks, dim, topK, normalized
        );

        // Fetch row data for results
        const rows = await this._fetchResultRows(indices);

        return { indices, scores, rows };
    }

    /**
     * Fetch full row data for result indices.
     * @private
     */
    async _fetchResultRows(indices) {
        if (indices.length === 0) return [];

        const rows = [];

        // Group indices by fragment for efficient fetching
        const groups = this._groupIndicesByFragment(Array.from(indices));

        for (const [fragIdx, group] of groups) {
            const file = await this.openFragment(fragIdx);

            // Read string columns for display
            for (const localIdx of group.localIndices) {
                const row = {};

                // Try to read text/url columns
                for (let colIdx = 0; colIdx < this._numColumns; colIdx++) {
                    const colName = this.columnNames[colIdx];
                    if (colName === 'text' || colName === 'url' || colName === 'caption') {
                        try {
                            const values = await file.readStringsAtIndices(colIdx, [localIdx]);
                            row[colName] = values[0];
                        } catch (e) {
                            // Column might not be string type
                        }
                    }
                }

                rows.push(row);
            }
        }

        return rows;
    }

    /**
     * Execute SQL query across all fragments in parallel.
     * @param {string} sql - SQL query
     * @returns {Promise<{columns: Array[], columnNames: string[], total: number}>}
     */
    async executeSQL(sql) {
        // Parse the SQL to understand what's needed
        const ast = parseSQL(sql);

        // For simple SELECT * with LIMIT, use readRows
        if (ast.type === 'SELECT' && ast.columns === '*' && !ast.where) {
            const limit = ast.limit || 50;
            const offset = ast.offset || 0;
            return await this.readRows({ offset, limit });
        }

        // For queries with WHERE or complex operations, execute on each fragment in parallel
        const fetchPromises = this._fragments.map(async (frag, idx) => {
            const file = await this.openFragment(idx);
            try {
                return await file.executeSQL(sql);
            } catch (e) {
                console.warn(`Fragment ${idx} query failed:`, e);
                return { columns: [], columnNames: [], total: 0 };
            }
        });

        const results = await Promise.all(fetchPromises);

        // Merge results
        if (results.length === 0 || results.every(r => r.columns.length === 0)) {
            return { columns: [], columnNames: this.columnNames, total: 0 };
        }

        const firstValid = results.find(r => r.columns.length > 0);
        if (!firstValid) {
            return { columns: [], columnNames: this.columnNames, total: 0 };
        }

        const numCols = firstValid.columns.length;
        const colNames = firstValid.columnNames;
        const mergedColumns = Array.from({ length: numCols }, () => []);

        let totalRows = 0;
        for (const r of results) {
            for (let c = 0; c < numCols && c < r.columns.length; c++) {
                mergedColumns[c].push(...r.columns[c]);
            }
            totalRows += r.total;
        }

        // Apply LIMIT if present (after merging)
        if (ast.limit) {
            const offset = ast.offset || 0;
            for (let c = 0; c < numCols; c++) {
                mergedColumns[c] = mergedColumns[c].slice(offset, offset + ast.limit);
            }
        }

        return {
            columns: mergedColumns,
            columnNames: colNames,
            total: totalRows
        };
    }

    /**
     * Close all cached fragment files.
     */
    close() {
        for (const file of this._fragmentFiles.values()) {
            if (file.close) file.close();
        }
        this._fragmentFiles.clear();
    }
}

// ============================================================================
// QueryPlanner - Query execution planning and optimization
// ============================================================================

/**
 * QueryPlanner generates optimized physical execution plans from logical query ASTs.
 *
 * Key optimizations:
 * - Column pruning: Only fetch columns actually needed
 * - Filter pushdown: Apply filters as early as possible
 * - Fetch size estimation: Minimize data transfer over HTTP
 * - Deduplication: Avoid fetching same column multiple times
 *
 * Example:
 *   SELECT a.url, b.text
 *   FROM images a
 *   JOIN captions b ON a.id = b.image_id
 *   WHERE a.aesthetic > 7.0 AND b.language = 'zh'
 *   LIMIT 20
 *
 * Physical Plan:
 *   1. SCAN left: fetch [id, url, aesthetic], filter aesthetic > 7.0, limit ~50
 *   2. BUILD_HASH: index by id, keep [id, url]
 *   3. SCAN right: fetch [image_id, text], filter image_id IN (...) AND language = 'zh'
 *   4. HASH_JOIN: join on id = image_id
 *   5. PROJECT: select [url, text]
 *   6. LIMIT: 20
 */
export class QueryPlanner {
    constructor() {
        this.debug = true; // Enable query plan logging
    }

    /**
     * Generate physical execution plan from logical AST
     * @param {Object} ast - Parsed SQL AST
     * @param {Object} context - Table names and aliases
     * @returns {Object} Physical execution plan
     */
    plan(ast, context) {
        const { leftTableName, leftAlias, rightTableName, rightAlias } = context;

        // Analyze what columns are needed from each table
        const columnAnalysis = this._analyzeColumns(ast, context);

        // Separate filters by table (pushdown optimization)
        const filterAnalysis = this._analyzeFilters(ast, context);

        // Estimate how many rows to fetch (over-fetch for safety)
        const fetchEstimate = this._estimateFetchSize(ast, filterAnalysis);

        // Build physical plan
        const plan = {
            // Step 1: Scan left table
            leftScan: {
                table: leftTableName,
                alias: leftAlias,
                columns: columnAnalysis.left.all,  // Deduplicated list
                filters: filterAnalysis.left,
                limit: fetchEstimate.left,
                purpose: {
                    join: columnAnalysis.left.join,
                    where: columnAnalysis.left.where,
                    result: columnAnalysis.left.result
                }
            },

            // Step 2: Scan right table
            rightScan: {
                table: rightTableName,
                alias: rightAlias,
                columns: columnAnalysis.right.all,
                filters: filterAnalysis.right,
                filterByJoinKeys: true,  // Will add IN clause dynamically
                purpose: {
                    join: columnAnalysis.right.join,
                    where: columnAnalysis.right.where,
                    result: columnAnalysis.right.result
                }
            },

            // Step 3: Join strategy
            join: {
                type: ast.joins[0].type,
                leftKey: columnAnalysis.joinKeys.left,
                rightKey: columnAnalysis.joinKeys.right,
                algorithm: 'HASH_JOIN'  // Could be SORT_MERGE or NESTED_LOOP in future
            },

            // Step 4: Final projection
            projection: columnAnalysis.resultColumns,

            // Step 5: Limit
            limit: ast.limit || null,
            offset: ast.offset || 0
        };

        if (this.debug) {
            this._logPlan(plan, ast);
        }

        return plan;
    }

    /**
     * Analyze which columns are needed from each table
     */
    _analyzeColumns(ast, context) {
        const { leftAlias, rightAlias } = context;

        const left = {
            join: new Set(),    // Columns needed for JOIN key
            where: new Set(),   // Columns needed for WHERE filter
            result: new Set(),  // Columns needed in final result
            all: []             // Deduplicated union of above
        };

        const right = {
            join: new Set(),
            where: new Set(),
            result: new Set(),
            all: []
        };

        // 1. Analyze SELECT columns (result set)
        for (const item of ast.columns) {
            if (item.type === 'star') {
                // SELECT * - need all columns (can't optimize this easily)
                left.result.add('*');
                right.result.add('*');
            } else if (item.type === 'expr' && item.expr.type === 'column') {
                const col = item.expr;
                const table = col.table || null;
                const column = col.column;

                if (!table || table === leftAlias) {
                    left.result.add(column);
                }
                if (!table || table === rightAlias) {
                    right.result.add(column);
                }
            }
        }

        // 2. Analyze JOIN ON condition (join keys)
        const join = ast.joins[0];
        const joinKeys = this._extractJoinKeys(join.on, leftAlias, rightAlias);

        if (joinKeys.left) {
            left.join.add(joinKeys.left);
        }
        if (joinKeys.right) {
            right.join.add(joinKeys.right);
        }

        // 3. Analyze WHERE clause (filter columns)
        if (ast.where) {
            this._extractWhereColumns(ast.where, leftAlias, rightAlias, left.where, right.where);
        }

        // 4. Deduplicate: merge join, where, result
        left.all = [...new Set([...left.join, ...left.where, ...left.result])];
        right.all = [...new Set([...right.join, ...right.where, ...right.result])];

        // 5. Handle SELECT *
        if (left.result.has('*')) {
            left.all = ['*'];
        }
        if (right.result.has('*')) {
            right.all = ['*'];
        }

        // 6. Determine final result columns (for projection after join)
        const resultColumns = [];
        for (const item of ast.columns) {
            if (item.type === 'star') {
                resultColumns.push('*');
            } else if (item.type === 'expr' && item.expr.type === 'column') {
                const col = item.expr;
                const alias = item.alias || `${col.table || ''}.${col.column}`.replace(/^\./, '');
                resultColumns.push({
                    table: col.table,
                    column: col.column,
                    alias: alias
                });
            }
        }

        return {
            left,
            right,
            joinKeys,
            resultColumns
        };
    }

    /**
     * Extract join keys from ON condition
     */
    _extractJoinKeys(onExpr, leftAlias, rightAlias) {
        if (!onExpr || onExpr.type !== 'binary') {
            return { left: null, right: null };
        }

        const leftCol = onExpr.left;
        const rightCol = onExpr.right;

        let leftKey = null;
        let rightKey = null;

        // Left side of equality
        if (leftCol.type === 'column') {
            if (!leftCol.table || leftCol.table === leftAlias) {
                leftKey = leftCol.column;
            } else if (leftCol.table === rightAlias) {
                rightKey = leftCol.column;
            }
        }

        // Right side of equality
        if (rightCol.type === 'column') {
            if (!rightCol.table || rightCol.table === leftAlias) {
                leftKey = rightCol.column;
            } else if (rightCol.table === rightAlias) {
                rightKey = rightCol.column;
            }
        }

        return { left: leftKey, right: rightKey };
    }

    /**
     * Extract columns referenced in WHERE clause
     */
    _extractWhereColumns(expr, leftAlias, rightAlias, leftCols, rightCols) {
        if (!expr) return;

        if (expr.type === 'column') {
            const table = expr.table;
            const column = expr.column;

            if (!table || table === leftAlias) {
                leftCols.add(column);
            } else if (table === rightAlias) {
                rightCols.add(column);
            }
        } else if (expr.type === 'binary') {
            this._extractWhereColumns(expr.left, leftAlias, rightAlias, leftCols, rightCols);
            this._extractWhereColumns(expr.right, leftAlias, rightAlias, leftCols, rightCols);
        } else if (expr.type === 'unary') {
            this._extractWhereColumns(expr.expr, leftAlias, rightAlias, leftCols, rightCols);
        }
    }

    /**
     * Analyze and separate filters by table (for pushdown)
     */
    _analyzeFilters(ast, context) {
        const { leftAlias, rightAlias } = context;

        const left = [];   // Filters that can be pushed to left table
        const right = [];  // Filters that can be pushed to right table
        const join = [];   // Filters that must be applied after join

        if (ast.where) {
            this._separateFilters(ast.where, leftAlias, rightAlias, left, right, join);
        }

        return { left, right, join };
    }

    /**
     * Separate WHERE filters by which table they reference
     */
    _separateFilters(expr, leftAlias, rightAlias, leftFilters, rightFilters, joinFilters) {
        if (!expr) return;

        // For AND expressions, recursively separate each side
        if (expr.type === 'binary' && expr.op === 'AND') {
            this._separateFilters(expr.left, leftAlias, rightAlias, leftFilters, rightFilters, joinFilters);
            this._separateFilters(expr.right, leftAlias, rightAlias, leftFilters, rightFilters, joinFilters);
            return;
        }

        // For other expressions, check which table(s) they reference
        const tables = this._getReferencedTables(expr, leftAlias, rightAlias);

        if (tables.size === 1) {
            // Filter references only one table - can push down
            if (tables.has(leftAlias)) {
                leftFilters.push(expr);
            } else if (tables.has(rightAlias)) {
                rightFilters.push(expr);
            }
        } else if (tables.size > 1) {
            // Filter references multiple tables - must apply after join
            joinFilters.push(expr);
        }
        // If tables.size === 0, it's a constant expression (ignore for now)
    }

    /**
     * Get which tables an expression references
     */
    _getReferencedTables(expr, leftAlias, rightAlias) {
        const tables = new Set();

        const walk = (e) => {
            if (!e) return;

            if (e.type === 'column') {
                const table = e.table;
                if (!table) {
                    // Ambiguous - could be either table (conservative: don't push down)
                    tables.add(leftAlias);
                    tables.add(rightAlias);
                } else if (table === leftAlias) {
                    tables.add(leftAlias);
                } else if (table === rightAlias) {
                    tables.add(rightAlias);
                }
            } else if (e.type === 'binary') {
                walk(e.left);
                walk(e.right);
            } else if (e.type === 'unary') {
                walk(e.expr);
            } else if (e.type === 'call') {
                for (const arg of e.args || []) {
                    walk(arg);
                }
            }
        };

        walk(expr);
        return tables;
    }

    /**
     * Estimate how many rows to fetch from each table
     *
     * Need to over-fetch because:
     * - WHERE filters reduce rows
     * - JOIN reduces rows
     * - Want to ensure we get LIMIT rows after all filtering
     */
    _estimateFetchSize(ast, filterAnalysis) {
        const requestedLimit = ast.limit || 1000;

        // Estimate selectivity (how many rows pass filters)
        // This is a simple heuristic - could be improved with statistics
        const leftSelectivity = filterAnalysis.left.length > 0 ? 0.5 : 1.0;  // 50% if filtered
        const rightSelectivity = filterAnalysis.right.length > 0 ? 0.5 : 1.0;

        // Join selectivity (how many rows match)
        const joinSelectivity = 0.7;  // Assume 70% of left rows find a match

        // Over-fetch multiplier
        const safetyFactor = 2.5;

        // Estimate left fetch size
        // Want: requestedLimit = leftFetch * leftSelectivity * joinSelectivity
        // So: leftFetch = requestedLimit / (leftSelectivity * joinSelectivity) * safetyFactor
        const leftFetch = Math.ceil(
            requestedLimit / (leftSelectivity * joinSelectivity) * safetyFactor
        );

        // Right table: fetch only what's needed based on left join keys
        // This will be dynamic (added in executor)
        const rightFetch = null;  // Determined by left join keys

        return {
            left: Math.min(leftFetch, 10000),  // Cap at 10K for safety
            right: rightFetch
        };
    }

    /**
     * Log the query plan for debugging
     */
    _logPlan(plan, ast) {
        console.log('\n' + '='.repeat(60));
        console.log('📋 QUERY EXECUTION PLAN');
        console.log('='.repeat(60));

        console.log('\n🔍 Original Query:');
        console.log(`  SELECT: ${ast.columns.length} columns`);
        console.log(`  FROM: ${plan.leftScan.table} AS ${plan.leftScan.alias}`);
        console.log(`  JOIN: ${plan.rightScan.table} AS ${plan.rightScan.alias}`);
        console.log(`  WHERE: ${ast.where ? 'yes' : 'no'}`);
        console.log(`  LIMIT: ${ast.limit || 'none'}`);

        console.log('\n📊 Physical Plan:');

        console.log('\n  Step 1: SCAN LEFT TABLE');
        console.log(`    Table: ${plan.leftScan.table}`);
        console.log(`    Columns: [${plan.leftScan.columns.join(', ')}]`);
        console.log(`      - Join keys: [${[...plan.leftScan.purpose.join].join(', ')}]`);
        console.log(`      - Filter cols: [${[...plan.leftScan.purpose.where].join(', ')}]`);
        console.log(`      - Result cols: [${[...plan.leftScan.purpose.result].join(', ')}]`);
        console.log(`    Filters: ${plan.leftScan.filters.length} pushed down`);
        plan.leftScan.filters.forEach((f, i) => {
            console.log(`      ${i + 1}. ${this._formatFilter(f)}`);
        });
        console.log(`    Limit: ${plan.leftScan.limit} rows (over-fetch for safety)`);

        console.log('\n  Step 2: BUILD HASH TABLE');
        console.log(`    Index by: ${plan.join.leftKey}`);
        console.log(`    Keep: [${plan.leftScan.columns.join(', ')}]`);

        console.log('\n  Step 3: SCAN RIGHT TABLE');
        console.log(`    Table: ${plan.rightScan.table}`);
        console.log(`    Columns: [${plan.rightScan.columns.join(', ')}]`);
        console.log(`      - Join keys: [${[...plan.rightScan.purpose.join].join(', ')}]`);
        console.log(`      - Filter cols: [${[...plan.rightScan.purpose.where].join(', ')}]`);
        console.log(`      - Result cols: [${[...plan.rightScan.purpose.result].join(', ')}]`);
        console.log(`    Filters: ${plan.rightScan.filters.length} pushed down`);
        plan.rightScan.filters.forEach((f, i) => {
            console.log(`      ${i + 1}. ${this._formatFilter(f)}`);
        });
        console.log(`    Dynamic filter: ${plan.join.rightKey} IN (keys from left)`);

        console.log('\n  Step 4: HASH JOIN');
        console.log(`    Algorithm: ${plan.join.algorithm}`);
        console.log(`    Condition: ${plan.join.leftKey} = ${plan.join.rightKey}`);

        console.log('\n  Step 5: PROJECT');
        console.log(`    Result columns: ${plan.projection.length}`);
        plan.projection.forEach((col, i) => {
            if (col === '*') {
                console.log(`      ${i + 1}. *`);
            } else {
                console.log(`      ${i + 1}. ${col.table}.${col.column} AS ${col.alias}`);
            }
        });

        console.log('\n  Step 6: LIMIT');
        console.log(`    Rows: ${plan.limit || 'none'}`);

        console.log('\n💡 Optimization Summary:');
        const leftTotal = plan.leftScan.columns.length;
        const rightTotal = plan.rightScan.columns.length;
        console.log(`  - Fetch ${leftTotal} cols from left (not all columns)`);
        console.log(`  - Fetch ${rightTotal} cols from right (not all columns)`);
        console.log(`  - Push down ${plan.leftScan.filters.length + plan.rightScan.filters.length} filters`);
        console.log(`  - Over-fetch left by ${(plan.leftScan.limit / (ast.limit || 1)).toFixed(1)}x for safety`);

        console.log('\n' + '='.repeat(60) + '\n');
    }

    /**
     * Format filter expression for logging
     */
    _formatFilter(expr) {
        if (!expr) return 'null';

        if (expr.type === 'binary') {
            const left = this._formatFilter(expr.left);
            const right = this._formatFilter(expr.right);
            return `${left} ${expr.op} ${right}`;
        } else if (expr.type === 'column') {
            return expr.table ? `${expr.table}.${expr.column}` : expr.column;
        } else if (expr.type === 'literal') {
            return JSON.stringify(expr.value);
        } else if (expr.type === 'call') {
            const args = (expr.args || []).map(a => this._formatFilter(a)).join(', ');
            return `${expr.name}(${args})`;
        }

        return JSON.stringify(expr);
    }
}

// ============================================================================
// LanceDatabase - Multi-table query execution with JOINs
// ============================================================================

/**
 * LanceDatabase manages multiple Lance datasets and executes multi-table queries.
 * Supports SQL JOINs across remote datasets with smart byte-range fetching.
 *
 * Features:
 * - Multi-table JOIN support (INNER, LEFT, RIGHT, FULL, CROSS)
 * - Hash join algorithm for efficient execution
 * - Smart column fetching (only fetch needed columns)
 * - Works with static files on CDN
 *
 * Usage:
 *   const db = await LanceQL.createDatabase();
 *   await db.registerRemote('images', 'https://cdn.example.com/images.lance');
 *   await db.registerRemote('captions', 'https://cdn.example.com/captions.lance');
 *   const results = await db.executeSQL(`
 *     SELECT i.url, c.text
 *     FROM images i
 *     JOIN captions c ON i.id = c.image_id
 *     WHERE i.aesthetic > 7.0
 *     LIMIT 20
 *   `);
 */
export class LanceDatabase {
    constructor() {
        this.tables = new Map(); // name -> RemoteLanceDataset
        this.aliases = new Map(); // alias -> table name
    }

    /**
     * Register a table with a name
     * @param {string} name - Table name
     * @param {RemoteLanceDataset} dataset - Dataset instance
     */
    register(name, dataset) {
        this.tables.set(name, dataset);
    }

    /**
     * Register a remote dataset by URL
     * @param {string} name - Table name
     * @param {string} url - Dataset URL
     * @param {Object} options - Dataset options (version, etc.)
     */
    async registerRemote(name, url, options = {}) {
        // Assume LanceQL is globally available or passed as parameter
        const lanceql = window.lanceql || globalThis.lanceql;
        if (!lanceql) {
            throw new Error('LanceQL WASM module not loaded. Call LanceQL.load() first.');
        }

        const dataset = await lanceql.openDataset(url, options);
        this.register(name, dataset);
        return dataset;
    }

    /**
     * Get a table by name or alias
     */
    getTable(name) {
        // Check aliases first
        const actualName = this.aliases.get(name) || name;
        const table = this.tables.get(actualName);
        if (!table) {
            throw new Error(`Table '${name}' not found. Did you forget to register it?`);
        }
        return table;
    }

    /**
     * Execute SQL query (supports SELECT with JOINs)
     */
    async executeSQL(sql) {
        // Parse SQL
        const lexer = new SQLLexer(sql);
        const tokens = lexer.tokenize();
        const parser = new SQLParser(tokens);
        const ast = parser.parse();

        if (ast.type !== 'SELECT') {
            throw new Error('Only SELECT queries are supported in LanceDatabase');
        }

        // No joins - simple single-table query
        if (!ast.joins || ast.joins.length === 0) {
            return this._executeSingleTable(ast);
        }

        // Multi-table query with JOINs
        return this._executeJoin(ast);
    }

    /**
     * Execute single-table query (no joins)
     */
    async _executeSingleTable(ast) {
        if (!ast.from) {
            throw new Error('FROM clause required');
        }

        // Get table
        let tableName = ast.from.name || ast.from.table;
        if (!tableName && ast.from.url) {
            throw new Error('Single-table queries must use registered table names, not URLs');
        }

        const dataset = this.getTable(tableName);

        // Build SQL and execute
        const executor = new SQLExecutor(dataset);
        return executor.execute(ast);
    }

    /**
     * Execute multi-table query with JOINs
     */
    async _executeJoin(ast) {
        console.log('[LanceDatabase] Executing JOIN query:', ast);

        // Extract table references
        const leftTableName = ast.from.name || ast.from.table;
        const leftAlias = ast.from.alias || leftTableName;

        // Register alias
        if (ast.from.alias) {
            this.aliases.set(ast.from.alias, leftTableName);
        }

        // For now, support only single JOIN (can extend later)
        if (ast.joins.length > 1) {
            throw new Error('Multiple JOINs not yet supported. Coming soon!');
        }

        const join = ast.joins[0];
        const rightTableName = join.table.name || join.table.table;
        const rightAlias = join.alias || rightTableName;

        // Register right table alias
        if (join.alias) {
            this.aliases.set(join.alias, rightTableName);
        }

        console.log(`[LanceDatabase] JOIN: ${leftTableName} (${leftAlias}) ${join.type} ${rightTableName} (${rightAlias})`);

        // Get datasets
        const leftDataset = this.getTable(leftTableName);
        const rightDataset = this.getTable(rightTableName);

        // Execute hash join
        return this._hashJoin(
            leftDataset,
            rightDataset,
            ast,
            { leftAlias, rightAlias, leftTableName, rightTableName }
        );
    }

    /**
     * Execute hash join between two datasets using QueryPlanner
     */
    async _hashJoin(leftDataset, rightDataset, ast, context) {
        const { leftAlias, rightAlias, leftTableName, rightTableName } = context;
        const join = ast.joins[0];

        // Parse JOIN ON condition (e.g., i.id = c.image_id)
        const joinCondition = join.on;
        if (!joinCondition || joinCondition.type !== 'binary' || joinCondition.op !== '=') {
            throw new Error('JOIN ON condition must be an equality (e.g., table1.col1 = table2.col2)');
        }

        // Use QueryPlanner to generate optimized execution plan
        const planner = new QueryPlanner();
        const plan = planner.plan(ast, context);

        // Extract columns and keys from the plan
        const leftKey = plan.join.leftKey;
        const rightKey = plan.join.rightKey;
        const leftColumns = plan.leftScan.columns;
        const rightColumns = plan.rightScan.columns;
        const leftFilters = plan.leftScan.filters;
        const rightFilters = plan.rightScan.filters;
        const leftLimit = plan.leftScan.limit;

        // Build left SQL with filter pushdown
        let leftWhereClause = '';
        if (leftFilters.length > 0) {
            const filterStr = leftFilters.map(f => this._filterToSQL(f)).join(' AND ');
            leftWhereClause = ` WHERE ${filterStr}`;
        }

        // Ensure join key is included in columns
        const leftColsWithKey = leftColumns.includes('*')
            ? ['*']
            : [...new Set([leftKey, ...leftColumns])];

        const leftSQL = `SELECT ${leftColsWithKey.join(', ')} FROM ${leftTableName}${leftWhereClause} LIMIT ${leftLimit}`;
        console.log('[LanceDatabase] Left query:', leftSQL);

        const leftExecutor = new SQLExecutor(leftDataset);
        const leftData = await leftExecutor.executeSQL(leftSQL);

        if (!leftData.rows || leftData.rows.length === 0) {
            return { columns: [], rows: [], total: 0 };
        }

        console.log(`[LanceDatabase] Fetched ${leftData.rows.length} rows from left table`);

        // Build hash map on left side
        const hashMap = new Map();
        const joinKeyIndex = leftData.columns.indexOf(leftKey);

        for (const row of leftData.rows) {
            const key = row[joinKeyIndex];
            if (key !== null && key !== undefined) {
                if (!hashMap.has(key)) {
                    hashMap.set(key, []);
                }
                hashMap.get(key).push(row);
            }
        }

        console.log(`[LanceDatabase] Built hash map with ${hashMap.size} unique keys`);

        // Get unique join keys for right side
        const joinKeys = Array.from(hashMap.keys());

        if (joinKeys.length === 0) {
            return { columns: [], rows: [], total: 0 };
        }

        // Build right SQL with filter pushdown AND join key filter
        const rightColsWithKey = rightColumns.includes('*')
            ? ['*']
            : [...new Set([rightKey, ...rightColumns])];

        // Combine pushed-down filters with join key IN clause
        const rightFilterParts = [];
        if (rightFilters.length > 0) {
            rightFilterParts.push(rightFilters.map(f => this._filterToSQL(f)).join(' AND '));
        }

        // Add join key filter
        const joinKeyValues = joinKeys.map(k => typeof k === 'string' ? `'${k}'` : k).join(',');
        rightFilterParts.push(`${rightKey} IN (${joinKeyValues})`);

        const rightWhereClause = ` WHERE ${rightFilterParts.join(' AND ')}`;

        const rightSQL = `SELECT ${rightColsWithKey.join(', ')} FROM ${rightTableName}${rightWhereClause}`;
        console.log('[LanceDatabase] Right query:', rightSQL);

        const rightExecutor = new SQLExecutor(rightDataset);
        const rightData = await rightExecutor.executeSQL(rightSQL);

        console.log(`[LanceDatabase] Fetched ${rightData.rows.length} rows from right table`);

        // Perform hash join
        const results = [];
        const rightJoinKeyIndex = rightData.columns.indexOf(rightKey);

        for (const rightRow of rightData.rows) {
            const key = rightRow[rightJoinKeyIndex];
            const leftRows = hashMap.get(key);

            if (leftRows) {
                for (const leftRow of leftRows) {
                    // Merge rows
                    results.push([...leftRow, ...rightRow]);
                }
            }
        }

        console.log(`[LanceDatabase] Joined ${results.length} rows`);

        // Build result columns
        const resultColumns = [...leftData.columns, ...rightData.columns];

        // Apply projection to select only the requested columns
        const projectedResults = this._applyProjection(results, resultColumns, plan.projection, leftAlias, rightAlias);

        // Apply LIMIT
        const limitedResults = ast.limit ? projectedResults.rows.slice(0, ast.limit) : projectedResults.rows;

        return {
            columns: projectedResults.columns,
            rows: limitedResults,
            total: limitedResults.length
        };
    }

    /**
     * Convert filter expression to SQL WHERE clause
     */
    _filterToSQL(expr) {
        if (!expr) return '';

        if (expr.type === 'binary') {
            const left = this._filterToSQL(expr.left);
            const right = this._filterToSQL(expr.right);
            return `${left} ${expr.op} ${right}`;
        } else if (expr.type === 'column') {
            return expr.table ? `${expr.table}.${expr.column}` : expr.column;
        } else if (expr.type === 'literal') {
            if (typeof expr.value === 'string') {
                return `'${expr.value}'`;
            }
            return String(expr.value);
        } else if (expr.type === 'call') {
            const args = (expr.args || []).map(a => this._filterToSQL(a)).join(', ');
            return `${expr.name}(${args})`;
        }

        return '';
    }

    /**
     * Apply projection to select only requested columns from joined result
     */
    _applyProjection(rows, allColumns, projection, leftAlias, rightAlias) {
        // Handle SELECT *
        if (projection.includes('*')) {
            return { columns: allColumns, rows };
        }

        // Build column mapping
        const projectedColumns = [];
        const columnIndices = [];

        for (const col of projection) {
            if (col === '*') {
                // Already handled above
                continue;
            }

            const targetCol = col.table
                ? `${col.column}`  // Use just column name for matching
                : col.column;

            // Find column in result set
            let idx = allColumns.indexOf(targetCol);
            if (idx === -1) {
                // Try with table prefix
                idx = allColumns.indexOf(`${col.table}.${col.column}`);
            }

            if (idx !== -1) {
                projectedColumns.push(col.alias || targetCol);
                columnIndices.push(idx);
            }
        }

        // Apply projection
        const projectedRows = rows.map(row =>
            columnIndices.map(idx => row[idx])
        );

        return { columns: projectedColumns, rows: projectedRows };
    }

    /**
     * Extract column name from expression
     */
    _extractColumnFromExpr(expr, expectedTable) {
        if (expr.type === 'column') {
            // Handle table.column syntax
            if (expr.table && expr.table !== expectedTable) {
                // Column belongs to different table
                return null;
            }
            return expr.column;
        }
        throw new Error(`Invalid join condition expression: ${JSON.stringify(expr)}`);
    }

    /**
     * Get columns needed for a specific table from SELECT list
     */
    _getColumnsForTable(selectColumns, tableAlias) {
        const columns = [];

        for (const item of selectColumns) {
            if (item.type === 'star') {
                // SELECT * - need to fetch all columns (TODO: get schema)
                return ['*'];
            }

            if (item.type === 'expr' && item.expr.type === 'column') {
                const col = item.expr;
                if (!col.table || col.table === tableAlias) {
                    columns.push(col.column);
                }
            }
        }

        return columns.length > 0 ? columns : ['*'];
    }
}

// ============================================================================
// WorkerPool - Parallel WASM execution across Web Workers
// ============================================================================

/**
 * WorkerPool manages a pool of Web Workers, each running their own WASM instance.
 * Enables true parallel processing across CPU cores.
 *
 * Features:
 * - Automatic worker scaling based on hardware concurrency
 * - Task queue with load balancing
 * - Support for SharedArrayBuffer (zero-copy) when available
 * - Graceful degradation to transferable ArrayBuffers
 */
export class WorkerPool {
    /**
     * Create a new worker pool.
     * @param {number} size - Number of workers (default: navigator.hardwareConcurrency)
     * @param {string} workerPath - Path to worker.js
     */
    constructor(size = null, workerPath = './worker.js') {
        this.size = size || navigator.hardwareConcurrency || 4;
        this.workerPath = workerPath;
        this.workers = [];
        this.taskQueue = [];
        this.pendingTasks = new Map();
        this.nextTaskId = 0;
        this.idleWorkers = [];
        this.initialized = false;

        // Check for SharedArrayBuffer support
        this.hasSharedArrayBuffer = typeof SharedArrayBuffer !== 'undefined';
    }

    /**
     * Initialize all workers.
     * @returns {Promise<void>}
     */
    async init() {
        if (this.initialized) return;

        const initPromises = [];

        for (let i = 0; i < this.size; i++) {
            const worker = new Worker(this.workerPath, { type: 'module' });
            this.workers.push(worker);

            // Set up message handling
            worker.onmessage = (e) => this._handleMessage(i, e.data);
            worker.onerror = (e) => this._handleError(i, e);

            // Initialize worker with WASM
            initPromises.push(this._initWorker(i));
        }

        await Promise.all(initPromises);
        this.initialized = true;

        console.log(`[WorkerPool] Initialized ${this.size} workers (SharedArrayBuffer: ${this.hasSharedArrayBuffer})`);
    }

    /**
     * Initialize a single worker.
     * @private
     */
    _initWorker(workerId) {
        return new Promise((resolve, reject) => {
            const taskId = this.nextTaskId++;

            this.pendingTasks.set(taskId, {
                resolve: (result) => {
                    this.idleWorkers.push(workerId);
                    resolve(result);
                },
                reject
            });

            this.workers[workerId].postMessage({
                type: 'init',
                id: taskId,
                params: { workerId }
            });
        });
    }

    /**
     * Handle message from worker.
     * @private
     */
    _handleMessage(workerId, data) {
        // Handle ready message (initial worker startup)
        if (data.type === 'ready') {
            return;
        }

        const { id, success, result, error } = data;
        const task = this.pendingTasks.get(id);

        if (!task) {
            console.warn(`[WorkerPool] Unknown task ID: ${id}`);
            return;
        }

        this.pendingTasks.delete(id);

        if (success) {
            task.resolve(result);
        } else {
            task.reject(new Error(error));
        }

        // Worker is now idle
        this.idleWorkers.push(workerId);

        // Process next task in queue
        this._processQueue();
    }

    /**
     * Handle worker error.
     * @private
     */
    _handleError(workerId, error) {
        console.error(`[WorkerPool] Worker ${workerId} error:`, error);
    }

    /**
     * Process next task in queue.
     * @private
     */
    _processQueue() {
        while (this.taskQueue.length > 0 && this.idleWorkers.length > 0) {
            const task = this.taskQueue.shift();
            const workerId = this.idleWorkers.shift();
            this._sendTask(workerId, task);
        }
    }

    /**
     * Send task to worker.
     * @private
     */
    _sendTask(workerId, task) {
        const worker = this.workers[workerId];
        const transfer = task.transfer || [];

        worker.postMessage({
            type: task.type,
            id: task.id,
            params: task.params
        }, transfer);
    }

    /**
     * Submit a task to the pool.
     * @param {string} type - Task type
     * @param {Object} params - Task parameters
     * @param {Array} transfer - Transferable objects
     * @returns {Promise<any>}
     */
    submit(type, params, transfer = []) {
        return new Promise((resolve, reject) => {
            const taskId = this.nextTaskId++;

            this.pendingTasks.set(taskId, { resolve, reject });

            const task = { type, params, transfer, id: taskId };

            if (this.idleWorkers.length > 0) {
                const workerId = this.idleWorkers.shift();
                this._sendTask(workerId, task);
            } else {
                this.taskQueue.push(task);
            }
        });
    }

    /**
     * Parallel vector search across multiple data chunks.
     *
     * @param {Float32Array} query - Query vector
     * @param {Array<{vectors: Float32Array, startIndex: number}>} chunks - Data chunks
     * @param {number} dim - Vector dimension
     * @param {number} topK - Number of results per chunk
     * @param {boolean} normalized - Whether vectors are L2-normalized
     * @returns {Promise<{indices: Uint32Array, scores: Float32Array}>}
     */
    async parallelVectorSearch(query, chunks, dim, topK, normalized = false) {
        if (!this.initialized) {
            await this.init();
        }

        // Submit search task to each worker
        const searchPromises = chunks.map((chunk, i) => {
            // Copy query for each worker (will be transferred)
            const queryCopy = new Float32Array(query);

            return this.submit('vectorSearch', {
                vectors: chunk.vectors,
                query: queryCopy,
                dim,
                numVectors: chunk.vectors.length / dim,
                topK,
                startIndex: chunk.startIndex,
                normalized
            }, [chunk.vectors.buffer, queryCopy.buffer]);
        });

        // Wait for all workers
        const results = await Promise.all(searchPromises);

        // Merge results from all workers
        return this._mergeTopK(results, topK);
    }

    /**
     * Merge top-k results from multiple workers.
     * @private
     */
    _mergeTopK(results, topK) {
        // Collect all results
        const allResults = [];

        for (const result of results) {
            for (let i = 0; i < result.count; i++) {
                allResults.push({
                    index: result.indices[i],
                    score: result.scores[i]
                });
            }
        }

        // Sort by score descending
        allResults.sort((a, b) => b.score - a.score);

        // Take top-k
        const finalK = Math.min(topK, allResults.length);
        const indices = new Uint32Array(finalK);
        const scores = new Float32Array(finalK);

        for (let i = 0; i < finalK; i++) {
            indices[i] = allResults[i].index;
            scores[i] = allResults[i].score;
        }

        return { indices, scores };
    }

    /**
     * Parallel batch similarity computation.
     *
     * @param {Float32Array} query - Query vector
     * @param {Array<Float32Array>} vectorChunks - Chunks of vectors
     * @param {number} dim - Vector dimension
     * @param {boolean} normalized - Whether vectors are L2-normalized
     * @returns {Promise<Float32Array>} - All similarity scores
     */
    async parallelBatchSimilarity(query, vectorChunks, dim, normalized = false) {
        if (!this.initialized) {
            await this.init();
        }

        const similarityPromises = vectorChunks.map(chunk => {
            const queryCopy = new Float32Array(query);
            return this.submit('batchSimilarity', {
                query: queryCopy,
                vectors: chunk,
                dim,
                numVectors: chunk.length / dim,
                normalized
            }, [chunk.buffer, queryCopy.buffer]);
        });

        const results = await Promise.all(similarityPromises);

        // Concatenate all scores
        const totalLength = results.reduce((sum, r) => sum + r.scores.length, 0);
        const allScores = new Float32Array(totalLength);

        let offset = 0;
        for (const result of results) {
            allScores.set(result.scores, offset);
            offset += result.scores.length;
        }

        return allScores;
    }

    /**
     * Terminate all workers.
     */
    terminate() {
        for (const worker of this.workers) {
            worker.terminate();
        }
        this.workers = [];
        this.idleWorkers = [];
        this.initialized = false;
    }
}

// ============================================================================
// SharedArrayBuffer Vector Store - Zero-copy data sharing
// ============================================================================

/**
 * SharedVectorStore provides zero-copy data sharing between main thread and workers.
 * Requires Cross-Origin-Isolation (COOP/COEP headers).
 */
export class SharedVectorStore {
    constructor() {
        this.buffer = null;
        this.vectors = null;
        this.dim = 0;
        this.numVectors = 0;

        if (typeof SharedArrayBuffer === 'undefined') {
            console.warn('[SharedVectorStore] SharedArrayBuffer not available. Using regular ArrayBuffer.');
        }
    }

    /**
     * Check if SharedArrayBuffer is available.
     */
    static isAvailable() {
        return typeof SharedArrayBuffer !== 'undefined' &&
               typeof Atomics !== 'undefined';
    }

    /**
     * Allocate shared memory for vectors.
     *
     * @param {number} numVectors - Number of vectors to store
     * @param {number} dim - Vector dimension
     */
    allocate(numVectors, dim) {
        this.numVectors = numVectors;
        this.dim = dim;

        const byteLength = numVectors * dim * 4; // float32

        if (SharedVectorStore.isAvailable()) {
            this.buffer = new SharedArrayBuffer(byteLength);
        } else {
            // Fallback to regular ArrayBuffer
            this.buffer = new ArrayBuffer(byteLength);
        }

        this.vectors = new Float32Array(this.buffer);
    }

    /**
     * Copy vectors into shared memory.
     *
     * @param {Float32Array} source - Source vectors
     * @param {number} startIndex - Starting index in store
     */
    set(source, startIndex = 0) {
        this.vectors.set(source, startIndex * this.dim);
    }

    /**
     * Get a slice of vectors (view, not copy).
     *
     * @param {number} start - Start vector index
     * @param {number} count - Number of vectors
     * @returns {Float32Array}
     */
    slice(start, count) {
        const startOffset = start * this.dim;
        const length = count * this.dim;
        return new Float32Array(this.buffer, startOffset * 4, length);
    }

    /**
     * Get chunk boundaries for parallel processing.
     *
     * @param {number} numChunks - Number of chunks
     * @returns {Array<{start: number, count: number}>}
     */
    getChunks(numChunks) {
        const chunks = [];
        const chunkSize = Math.ceil(this.numVectors / numChunks);

        for (let i = 0; i < numChunks; i++) {
            const start = i * chunkSize;
            const count = Math.min(chunkSize, this.numVectors - start);
            if (count > 0) {
                chunks.push({ start, count });
            }
        }

        return chunks;
    }
}

// ============================================================================
// CSS-Driven Query Engine - Zero JavaScript Data Binding
// ============================================================================

/**
 * LanceData provides CSS-driven data binding for Lance datasets.
 *
 * TRULY CSS-DRIVEN: No JavaScript initialization required!
 * Just add lq-* attributes to any element.
 *
 * Usage (pure HTML/CSS, zero JavaScript):
 * ```html
 * <div lq-query="SELECT url, text FROM read_lance('https://data.metal0.dev/laion-1m/images.lance') LIMIT 10"
 *      lq-render="table">
 * </div>
 * ```
 *
 * Attributes (supports both lq-* and data-* prefixes):
 * - lq-src / data-dataset: Dataset URL (optional if URL is in query)
 * - lq-query / data-query: SQL query string (required)
 * - lq-render / data-render: Renderer type - table, list, value, images, json (default: table)
 * - lq-columns / data-columns: Comma-separated column names to display
 * - lq-bind / data-bind: Input element selector for reactive binding
 *
 * The system auto-initializes when the script loads.
 */
export class LanceData {
    static _initialized = false;
    static _observer = null;
    static _wasm = null;
    static _datasets = new Map(); // Cache datasets by URL
    static _renderers = {};
    static _bindings = new Map();
    static _queryCache = new Map();
    static _defaultDataset = null;

    /**
     * Auto-initialize when DOM is ready.
     * Called automatically - no user action needed.
     */
    static _autoInit() {
        if (LanceData._initialized) return;
        LanceData._initialized = true;

        // Register built-in renderers
        LanceData._registerBuiltinRenderers();

        // Inject trigger styles
        LanceData._injectTriggerStyles();

        // Set up observer for lance-data elements
        LanceData._setupObserver();

        // Process any existing elements
        LanceData._processExisting();
    }

    /**
     * Get or load a dataset (cached).
     */
    static async _getDataset(url) {
        if (!url) {
            if (LanceData._defaultDataset) return LanceData._datasets.get(LanceData._defaultDataset);
            throw new Error('No dataset URL. Add data-dataset="https://..." to your element.');
        }

        if (LanceData._datasets.has(url)) {
            return LanceData._datasets.get(url);
        }

        // Load WASM if needed
        if (!LanceData._wasm) {
            // Try to find wasm URL from script tag or use default
            const wasmUrl = document.querySelector('script[data-lanceql-wasm]')?.dataset.lanceqlWasm
                || './lanceql.wasm';
            LanceData._wasm = await LanceQL.load(wasmUrl);
        }

        const dataset = await RemoteLanceDataset.open(LanceData._wasm, url);
        LanceData._datasets.set(url, dataset);

        // First dataset becomes default
        if (!LanceData._defaultDataset) {
            LanceData._defaultDataset = url;
        }

        return dataset;
    }

    /**
     * Manual init (optional) - for advanced configuration.
     */
    static async init(options = {}) {
        LanceData._autoInit();

        if (options.wasmUrl) {
            LanceData._wasm = await LanceQL.load(options.wasmUrl);
        }
        if (options.dataset) {
            await LanceData._getDataset(options.dataset);
        }
    }

    /**
     * Inject CSS that triggers JavaScript via animation events.
     */
    static _injectTriggerStyles() {
        if (document.getElementById('lance-data-triggers')) return;

        const style = document.createElement('style');
        style.id = 'lance-data-triggers';
        style.textContent = `
            /* Lance Data CSS Trigger System */
            @keyframes lance-query-trigger {
                from { --lance-trigger: 0; }
                to { --lance-trigger: 1; }
            }

            /* Elements with lance-data class trigger on insertion */
            .lance-data {
                animation: lance-query-trigger 0.001s;
            }

            /* Re-trigger on data attribute changes */
            .lance-data[data-refresh] {
                animation: lance-query-trigger 0.001s;
            }

            /* Loading state */
            .lance-data[data-loading]::before {
                content: '';
                display: block;
                width: 20px;
                height: 20px;
                border: 2px solid #3b82f6;
                border-top-color: transparent;
                border-radius: 50%;
                animation: lance-spin 0.8s linear infinite;
            }

            @keyframes lance-spin {
                to { transform: rotate(360deg); }
            }

            /* Error state */
            .lance-data[data-error]::before {
                content: attr(data-error);
                color: #ef4444;
                font-size: 12px;
            }

            /* Result container styling */
            .lance-data table {
                width: 100%;
                border-collapse: collapse;
                font-size: 13px;
            }

            .lance-data th, .lance-data td {
                padding: 8px 12px;
                text-align: left;
                border-bottom: 1px solid #334155;
            }

            .lance-data th {
                background: #1e293b;
                font-weight: 500;
                color: #94a3b8;
            }

            .lance-data tr:hover td {
                background: rgba(59, 130, 246, 0.05);
            }

            /* Value renderer */
            .lance-data[style*="--render: value"] .lance-value,
            .lance-data[style*="--render:'value'"] .lance-value,
            .lance-data[style*='--render:"value"'] .lance-value {
                font-size: 24px;
                font-weight: 600;
                color: #3b82f6;
            }

            /* List renderer */
            .lance-data .lance-list {
                list-style: none;
                padding: 0;
                margin: 0;
            }

            .lance-data .lance-list li {
                padding: 8px 0;
                border-bottom: 1px solid #334155;
            }

            /* JSON renderer */
            .lance-data .lance-json {
                background: #0f172a;
                padding: 12px;
                border-radius: 8px;
                font-family: 'SF Mono', Monaco, monospace;
                font-size: 12px;
                white-space: pre-wrap;
                overflow-x: auto;
            }

            /* Image grid renderer */
            .lance-data .lance-images {
                display: grid;
                grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
                gap: 16px;
            }

            .lance-data .lance-images .image-card {
                background: #1e293b;
                border-radius: 8px;
                overflow: hidden;
            }

            .lance-data .lance-images img {
                width: 100%;
                aspect-ratio: 1;
                object-fit: cover;
            }

            .lance-data .lance-images .image-meta {
                padding: 8px;
                font-size: 12px;
                color: #94a3b8;
            }
        `;
        document.head.appendChild(style);
    }

    /**
     * Set up MutationObserver for dynamic elements.
     */
    static _setupObserver() {
        if (LanceData._observer) return;

        // Helper to check if element has lq-* attributes
        const hasLqAttrs = (el) => {
            return el.hasAttribute?.('lq-query') || el.hasAttribute?.('lq-src') ||
                   el.classList?.contains('lance-data');
        };

        LanceData._observer = new MutationObserver((mutations) => {
            for (const mutation of mutations) {
                // New nodes added
                for (const node of mutation.addedNodes) {
                    if (node.nodeType === Node.ELEMENT_NODE) {
                        if (hasLqAttrs(node)) {
                            LanceData._processElement(node);
                        }
                        // Check descendants
                        node.querySelectorAll?.('[lq-query], [lq-src], .lance-data')?.forEach(el => {
                            LanceData._processElement(el);
                        });
                    }
                }

                // Attribute changes
                if (mutation.type === 'attributes' && hasLqAttrs(mutation.target)) {
                    LanceData._processElement(mutation.target);
                }
            }
        });

        LanceData._observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['lq-query', 'lq-src', 'lq-render', 'lq-bind', 'data-query', 'data-dataset', 'data-render', 'data-refresh']
        });

        // Also listen for animation events (CSS trigger)
        document.body.addEventListener('animationstart', (e) => {
            if (e.animationName === 'lance-query-trigger' && hasLqAttrs(e.target)) {
                LanceData._processElement(e.target);
            }
        });
    }

    /**
     * Process existing lance-data elements.
     */
    static _processExisting() {
        document.querySelectorAll('[lq-query], [lq-src], .lance-data').forEach(el => {
            LanceData._processElement(el);
        });
    }

    /**
     * Parse config from attributes (supports both lq-* and data-* prefixes).
     */
    static _parseConfig(el) {
        // Helper to get attribute value with fallback (lq-* takes precedence)
        const getAttr = (lqName, dataName) => {
            return el.getAttribute(lqName) || el.dataset[dataName] || null;
        };

        return {
            dataset: getAttr('lq-src', 'dataset'),
            query: getAttr('lq-query', 'query'),
            render: getAttr('lq-render', 'render') || 'table',
            columns: (getAttr('lq-columns', 'columns') || '')
                .split(',')
                .map(c => c.trim())
                .filter(Boolean),
            bind: getAttr('lq-bind', 'bind'),
        };
    }

    /**
     * Render pre-computed results to an element (CSS-driven from JS).
     * Use this when you already have query results and just want CSS-driven rendering.
     * @param {HTMLElement|string} el - Element or selector
     * @param {Object} results - Query results {columns, rows, total}
     * @param {Object} [options] - Render options
     * @param {string} [options.render] - Renderer type (table, images, json, etc.)
     */
    static render(el, results, options = {}) {
        const element = typeof el === 'string' ? document.querySelector(el) : el;
        if (!element) {
            console.error('[LanceData] Element not found:', el);
            return;
        }

        try {
            // Dispatch start event
            element.dispatchEvent(new CustomEvent('lq-start', {
                detail: { query: options.query || null }
            }));

            const renderType = options.render || element.dataset.render || 'table';
            const renderer = LanceData._renderers[renderType] || LanceData._renderers.table;

            // Store results in cache for potential re-renders
            if (element.id) {
                LanceData._queryCache.set(`rendered:${element.id}`, results);
            }

            element.innerHTML = renderer(results, { render: renderType, ...options });

            // Dispatch complete event
            element.dispatchEvent(new CustomEvent('lq-complete', {
                detail: {
                    query: options.query || null,
                    columns: results.columns || [],
                    total: results.total || results.rows?.length || 0
                }
            }));
        } catch (error) {
            // Dispatch error event
            element.dispatchEvent(new CustomEvent('lq-error', {
                detail: {
                    query: options.query || null,
                    message: error.message,
                    error: error
                }
            }));
            throw error;
        }
    }

    /**
     * Extract dataset URL from SQL query (e.g., read_lance('https://...'))
     */
    static _extractUrlFromQuery(sql) {
        const match = sql.match(/read_lance\s*\(\s*['"]([^'"]+)['"]/i);
        return match ? match[1] : null;
    }

    /**
     * Process a single lance-data element.
     */
    static async _processElement(el) {
        // Prevent double processing
        if (el.dataset.processing === 'true') return;
        el.dataset.processing = 'true';

        try {
            const config = LanceData._parseConfig(el);

            if (!config.query) {
                el.dataset.processing = 'false';
                return;
            }

            // Set up input binding if specified
            if (config.bind) {
                LanceData._setupBinding(el, config);
            }

            el.dataset.loading = 'true';
            delete el.dataset.error;

            // Dispatch start event (for Alpine.js integration)
            el.dispatchEvent(new CustomEvent('lq-start', {
                detail: { query: config.query }
            }));

            // Extract dataset URL from query if not specified
            const datasetUrl = config.dataset || LanceData._extractUrlFromQuery(config.query);

            // Get dataset (auto-loads and caches)
            const dataset = await LanceData._getDataset(datasetUrl);

            // Check cache
            const cacheKey = `${datasetUrl || 'default'}:${config.query}`;
            let results = LanceData._queryCache.get(cacheKey);

            if (!results) {
                // Execute query
                results = await dataset.executeSQL(config.query);
                LanceData._queryCache.set(cacheKey, results);
            }

            // Render results
            const renderer = LanceData._renderers[config.render] || LanceData._renderers.table;
            el.innerHTML = renderer(results, config);

            delete el.dataset.loading;

            // Dispatch complete event (for Alpine.js integration)
            el.dispatchEvent(new CustomEvent('lq-complete', {
                detail: {
                    query: config.query,
                    columns: results.columns || [],
                    total: results.total || results.rows?.length || 0
                }
            }));
        } catch (error) {
            delete el.dataset.loading;
            el.dataset.error = error.message;
            console.error('[LanceData]', error);

            // Dispatch error event (for Alpine.js integration)
            el.dispatchEvent(new CustomEvent('lq-error', {
                detail: {
                    query: config.query,
                    message: error.message,
                    error: error
                }
            }));
        } finally {
            el.dataset.processing = 'false';
        }
    }

    /**
     * Set up reactive binding to an input element.
     */
    static _setupBinding(el, config) {
        const input = document.querySelector(config.bind);
        if (!input) return;

        // Store binding reference
        const bindingKey = config.bind;
        if (LanceData._bindings.has(bindingKey)) return;

        const handler = () => {
            // Replace $value in query with input value
            const value = input.value;
            const newQuery = config.query.replace(/\$value/g, value);

            // Set via both attribute types
            if (el.hasAttribute('lq-query')) {
                el.setAttribute('lq-query', newQuery);
            } else {
                el.dataset.query = newQuery;
            }

            // Trigger refresh
            el.dataset.refresh = Date.now();
        };

        input.addEventListener('input', handler);
        input.addEventListener('change', handler);

        LanceData._bindings.set(bindingKey, { input, handler, element: el });
    }

    /**
     * Register a custom renderer.
     * @param {string} name - Renderer name
     * @param {Function} fn - Renderer function (results, config) => html
     */
    static registerRenderer(name, fn) {
        LanceData._renderers[name] = fn;
    }

    /**
     * Register built-in renderers.
     */
    static _registerBuiltinRenderers() {
        // Table renderer - handles both {columns, rows} and array-of-objects formats
        LanceData._renderers.table = (results, config) => {
            if (!results) {
                return '<div class="lance-empty">No results</div>';
            }

            // Detect format: {columns, rows} vs array of objects
            let columns, rows;
            if (results.columns && results.rows) {
                // SQLExecutor format: {columns: ['col1', 'col2'], rows: [[val1, val2], ...]}
                columns = config.columns || results.columns.filter(k =>
                    !k.startsWith('_') && k !== 'embedding'
                );
                rows = results.rows;
            } else if (Array.isArray(results)) {
                // Array of objects format: [{col1: val1, col2: val2}, ...]
                if (results.length === 0) {
                    return '<div class="lance-empty">No results</div>';
                }
                columns = config.columns || Object.keys(results[0]).filter(k =>
                    !k.startsWith('_') && k !== 'embedding'
                );
                rows = results.map(row => columns.map(col => row[col]));
            } else {
                return '<div class="lance-empty">No results</div>';
            }

            if (rows.length === 0) {
                return '<div class="lance-empty">No results</div>';
            }

            let html = '<table><thead><tr>';
            for (const col of columns) {
                html += `<th>${LanceData._escapeHtml(String(col))}</th>`;
            }
            html += '</tr></thead><tbody>';

            for (const row of rows) {
                html += '<tr>';
                for (let i = 0; i < columns.length; i++) {
                    const value = row[i];
                    html += `<td>${LanceData._formatValue(value)}</td>`;
                }
                html += '</tr>';
            }

            html += '</tbody></table>';
            return html;
        };

        // List renderer
        LanceData._renderers.list = (results, config) => {
            if (!results || results.length === 0) {
                return '<div class="lance-empty">No results</div>';
            }

            const displayCol = config.columns?.[0] || Object.keys(results[0])[0];

            let html = '<ul class="lance-list">';
            for (const row of results) {
                html += `<li>${LanceData._formatValue(row[displayCol])}</li>`;
            }
            html += '</ul>';
            return html;
        };

        // Single value renderer
        LanceData._renderers.value = (results, config) => {
            if (!results || results.length === 0) {
                return '<div class="lance-empty">-</div>';
            }

            const firstRow = results[0];
            const firstKey = Object.keys(firstRow)[0];
            const value = firstRow[firstKey];

            return `<div class="lance-value">${LanceData._formatValue(value)}</div>`;
        };

        // JSON renderer
        LanceData._renderers.json = (results, config) => {
            return `<pre class="lance-json">${LanceData._escapeHtml(JSON.stringify(results, null, 2))}</pre>`;
        };

        // Image grid renderer (for datasets with url column)
        LanceData._renderers.images = (results, config) => {
            if (!results || results.length === 0) {
                return '<div class="lance-empty">No images</div>';
            }

            let html = '<div class="lance-images">';
            for (const row of results) {
                const url = row.url || row.image_url || row.src;
                const text = row.text || row.caption || row.title || '';

                if (url) {
                    html += `
                        <div class="image-card">
                            <img src="${LanceData._escapeHtml(url)}" alt="${LanceData._escapeHtml(text)}" loading="lazy">
                            ${text ? `<div class="image-meta">${LanceData._escapeHtml(text.substring(0, 100))}</div>` : ''}
                        </div>
                    `;
                }
            }
            html += '</div>';
            return html;
        };

        // Count renderer (for aggregates)
        LanceData._renderers.count = (results, config) => {
            const count = results?.[0]?.count ?? results?.length ?? 0;
            return `<span class="lance-count">${count.toLocaleString()}</span>`;
        };
    }

    /**
     * Check if a string is an image URL.
     */
    static _isImageUrl(str) {
        if (!str || typeof str !== 'string') return false;
        const lower = str.toLowerCase();
        return (lower.startsWith('http://') || lower.startsWith('https://')) &&
               (lower.includes('.jpg') || lower.includes('.jpeg') || lower.includes('.png') ||
                lower.includes('.gif') || lower.includes('.webp') || lower.includes('.svg'));
    }

    /**
     * Check if a string is a URL.
     */
    static _isUrl(str) {
        if (!str || typeof str !== 'string') return false;
        return str.startsWith('http://') || str.startsWith('https://');
    }

    /**
     * Format a value for display.
     */
    static _formatValue(value) {
        if (value === null || value === undefined) return '<span class="null-value">NULL</span>';
        if (value === '') return '<span class="empty-value">(empty)</span>';

        if (typeof value === 'number') {
            return Number.isInteger(value) ? value.toLocaleString() : value.toFixed(4);
        }
        if (Array.isArray(value)) {
            if (value.length > 10) return `<span class="vector-badge">[${value.length}d]</span>`;
            return `[${value.slice(0, 5).map(v => LanceData._formatValue(v)).join(', ')}${value.length > 5 ? '...' : ''}]`;
        }
        if (typeof value === 'object') return JSON.stringify(value);

        const str = String(value);

        // Handle image URLs - show thumbnail
        if (LanceData._isImageUrl(str)) {
            const escaped = LanceData._escapeHtml(str);
            const short = escaped.length > 40 ? escaped.substring(0, 40) + '...' : escaped;
            return `<div class="image-cell">
                <img src="${escaped}" alt="" loading="lazy" onerror="this.style.display='none';this.nextElementSibling.style.display='flex'">
                <div class="image-placeholder" style="display:none"><svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg></div>
                <a href="${escaped}" target="_blank" class="url-text" title="${escaped}">${short}</a>
            </div>`;
        }

        // Handle other URLs - show as clickable link
        if (LanceData._isUrl(str)) {
            const escaped = LanceData._escapeHtml(str);
            const short = escaped.length > 50 ? escaped.substring(0, 50) + '...' : escaped;
            return `<a href="${escaped}" target="_blank" class="url-link" title="${escaped}">${short}</a>`;
        }

        // Handle long strings - truncate
        if (str.length > 100) return `<span title="${LanceData._escapeHtml(str)}">${LanceData._escapeHtml(str.substring(0, 100))}...</span>`;
        return LanceData._escapeHtml(str);
    }

    /**
     * Escape HTML special characters.
     */
    static _escapeHtml(str) {
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    /**
     * Clear the query cache.
     */
    static clearCache() {
        LanceData._queryCache.clear();
    }

    /**
     * Refresh all lance-data elements.
     */
    static refresh() {
        LanceData._queryCache.clear();
        document.querySelectorAll('.lance-data').forEach(el => {
            el.setAttribute('data-refresh', Date.now());
        });
    }

    /**
     * Destroy and clean up.
     */
    static destroy() {
        if (LanceData._observer) {
            LanceData._observer.disconnect();
            LanceData._observer = null;
        }

        // Remove bindings
        for (const [key, binding] of LanceData._bindings) {
            binding.input.removeEventListener('input', binding.handler);
            binding.input.removeEventListener('change', binding.handler);
        }
        LanceData._bindings.clear();

        // Remove injected styles
        document.getElementById('lance-data-triggers')?.remove();

        LanceData._instance = null;
        LanceData._dataset = null;
        LanceData._queryCache.clear();
    }
}

// Auto-initialize when DOM is ready (truly CSS-driven - no JS needed by user)
if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => LanceData._autoInit());
    } else {
        LanceData._autoInit();
    }
}

// =============================================================================
// sql.js-Compatible API - Drop-in replacement with vector search
// =============================================================================

/**
 * Statement class - sql.js compatible prepared statement
 *
 * Thin wrapper that delegates to WASM-based SQLExecutor
 */
class Statement {
    constructor(db, sql) {
        this.db = db;
        this.sql = sql;
        this.params = null;
        this.results = null;
        this.resultIndex = 0;
        this.done = false;
    }

    /**
     * Bind parameters to the statement
     * @param {Array|Object} params - Parameters to bind
     * @returns {boolean} true on success
     */
    bind(params) {
        this.params = params;
        this.results = null;
        this.resultIndex = 0;
        this.done = false;
        return true;
    }

    /**
     * Execute and step to next row
     * @returns {boolean} true if there's a row, false if done
     */
    step() {
        if (this.done) return false;

        // Execute on first step
        if (this.results === null) {
            const execResult = this.db.exec(this.sql, this.params);
            if (execResult.length === 0 || execResult[0].values.length === 0) {
                this.done = true;
                return false;
            }
            this.results = execResult[0];
            this.resultIndex = 0;
        }

        if (this.resultIndex >= this.results.values.length) {
            this.done = true;
            return false;
        }

        return true;
    }

    /**
     * Get current row as array
     * @returns {Array} Current row values
     */
    get() {
        if (!this.results || this.resultIndex >= this.results.values.length) {
            return [];
        }
        const row = this.results.values[this.resultIndex];
        this.resultIndex++;
        return row;
    }

    /**
     * Get current row as object
     * @param {Object} params - Optional params (ignored, for compatibility)
     * @returns {Object} Current row as {column: value}
     */
    getAsObject(params) {
        if (!this.results || this.resultIndex >= this.results.values.length) {
            return {};
        }
        const row = this.results.values[this.resultIndex];
        this.resultIndex++;

        const obj = {};
        this.results.columns.forEach((col, i) => {
            obj[col] = row[i];
        });
        return obj;
    }

    /**
     * Get column names
     * @returns {Array} Column names
     */
    getColumnNames() {
        return this.results?.columns || [];
    }

    /**
     * Reset statement for reuse
     * @returns {boolean} true on success
     */
    reset() {
        this.results = null;
        this.resultIndex = 0;
        this.done = false;
        return true;
    }

    /**
     * Free statement resources
     * @returns {boolean} true on success
     */
    free() {
        this.results = null;
        this.params = null;
        return true;
    }

    /**
     * Free and finalize (alias for free)
     */
    freemem() {
        return this.free();
    }
}

/**
 * Database class - sql.js compatible API with vector search
 *
 * Drop-in replacement for sql.js Database with:
 * - Same API: exec(), run(), prepare(), export(), close()
 * - OPFS persistence (automatic, no export/import needed)
 * - Vector search: NEAR, TOPK, embeddings
 * - Columnar Lance format for analytics
 *
 * @example
 * const SQL = await initSqlJs();
 * const db = new SQL.Database('mydb');
 *
 * // Standard SQL (same as sql.js)
 * db.exec("CREATE TABLE users (id INT, name TEXT)");
 * db.run("INSERT INTO users VALUES (?, ?)", [1, 'Alice']);
 * const results = db.exec("SELECT * FROM users");
 *
 * // Vector search (LanceQL extension)
 * db.exec("SELECT * FROM docs NEAR embedding 'search text' TOPK 10");
 */
class Database {
    /**
     * Create a new database
     * @param {string|Uint8Array} nameOrData - Database name (OPFS) or data (in-memory)
     * @param {OPFSStorage} storage - Optional storage backend
     */
    constructor(nameOrData, storage = null) {
        if (nameOrData instanceof Uint8Array) {
            // In-memory database from binary data (sql.js compatibility)
            this._inMemory = true;
            this._data = nameOrData;
            this._name = ':memory:';
            this._db = null;
        } else {
            // OPFS-persisted database
            this._inMemory = false;
            this._name = nameOrData || 'default';
            this._storage = storage;
            this._db = new LocalDatabase(this._name, storage || opfsStorage);
        }
        this._open = false;
        this._rowsModified = 0;
    }

    /**
     * Ensure database is open
     */
    async _ensureOpen() {
        if (!this._open && this._db) {
            await this._db.open();
            this._open = true;
        }
    }

    /**
     * Execute SQL and return results
     *
     * @param {string} sql - SQL statement(s)
     * @param {Array|Object} params - Optional parameters
     * @returns {Array} Array of {columns, values} result sets
     *
     * @example
     * const results = db.exec("SELECT * FROM users WHERE id = ?", [1]);
     * // [{columns: ['id', 'name'], values: [[1, 'Alice']]}]
     */
    exec(sql, params) {
        // Return promise for async operation
        return this._execAsync(sql, params);
    }

    async _execAsync(sql, params) {
        await this._ensureOpen();

        // Substitute parameters
        let processedSql = sql;
        if (params) {
            if (Array.isArray(params)) {
                let paramIndex = 0;
                processedSql = sql.replace(/\?/g, () => {
                    const val = params[paramIndex++];
                    return this._formatValue(val);
                });
            } else if (typeof params === 'object') {
                for (const [key, val] of Object.entries(params)) {
                    const pattern = new RegExp(`[:$@]${key}\\b`, 'g');
                    processedSql = processedSql.replace(pattern, this._formatValue(val));
                }
            }
        }

        // Split multiple statements
        const statements = processedSql
            .split(';')
            .map(s => s.trim())
            .filter(s => s.length > 0);

        const results = [];

        for (const stmt of statements) {
            try {
                const lexer = new SQLLexer(stmt);
                const tokens = lexer.tokenize();
                const parser = new SQLParser(tokens);
                const ast = parser.parse();

                if (ast.type === 'SELECT') {
                    // SELECT returns rows
                    const rows = await this._db._executeAST(ast);
                    if (rows && rows.length > 0) {
                        const columns = Object.keys(rows[0]);
                        const values = rows.map(row => columns.map(c => row[c]));
                        results.push({ columns, values });
                    }
                    this._rowsModified = 0;
                } else {
                    // Non-SELECT statements
                    const result = await this._db._executeAST(ast);
                    this._rowsModified = result?.inserted || result?.updated || result?.deleted || 0;
                }
            } catch (e) {
                throw new Error(`SQL error: ${e.message}\nStatement: ${stmt}`);
            }
        }

        return results;
    }

    /**
     * Execute SQL without returning results
     *
     * @param {string} sql - SQL statement
     * @param {Array|Object} params - Optional parameters
     * @returns {Database} this (for chaining)
     */
    run(sql, params) {
        return this._runAsync(sql, params);
    }

    async _runAsync(sql, params) {
        await this.exec(sql, params);
        return this;
    }

    /**
     * Prepare a statement for execution
     *
     * @param {string} sql - SQL statement
     * @param {Array|Object} params - Optional initial parameters
     * @returns {Statement} Prepared statement
     */
    prepare(sql, params) {
        const stmt = new Statement(this, sql);
        if (params) {
            stmt.bind(params);
        }
        return stmt;
    }

    /**
     * Execute SQL and call callback for each row
     *
     * @param {string} sql - SQL statement
     * @param {Array|Object} params - Parameters
     * @param {Function} callback - Called with row object for each row
     * @param {Function} done - Called when complete
     * @returns {Database} this
     */
    each(sql, params, callback, done) {
        this._eachAsync(sql, params, callback, done);
        return this;
    }

    async _eachAsync(sql, params, callback, done) {
        try {
            const results = await this.exec(sql, params);
            if (results.length > 0) {
                const { columns, values } = results[0];
                for (const row of values) {
                    const obj = {};
                    columns.forEach((col, i) => {
                        obj[col] = row[i];
                    });
                    callback(obj);
                }
            }
            if (done) done();
        } catch (e) {
            if (done) done(e);
            else throw e;
        }
    }

    /**
     * Get number of rows modified by last statement
     * @returns {number} Rows modified
     */
    getRowsModified() {
        return this._rowsModified;
    }

    /**
     * Export database to Uint8Array
     *
     * For OPFS databases, this exports all tables as JSON.
     * For in-memory databases, returns the original data.
     *
     * @returns {Uint8Array} Database contents
     */
    async export() {
        if (this._inMemory && this._data) {
            return this._data;
        }

        await this._ensureOpen();

        // Export all tables as JSON
        const exportData = {
            version: this._db.version,
            tables: {}
        };

        for (const tableName of this._db.listTables()) {
            const table = this._db.getTable(tableName);
            const rows = await this._db.select(tableName, {});
            exportData.tables[tableName] = {
                schema: table.schema,
                rows
            };
        }

        return new TextEncoder().encode(JSON.stringify(exportData));
    }

    /**
     * Close the database
     */
    close() {
        this._open = false;
        this._db = null;
    }

    /**
     * Register a custom SQL function (stub for compatibility)
     * @param {string} name - Function name
     * @param {Function} func - Function implementation
     * @returns {Database} this
     */
    create_function(name, func) {
        console.warn(`[LanceQL] create_function('${name}') not yet implemented`);
        return this;
    }

    /**
     * Register a custom aggregate function (stub for compatibility)
     * @param {string} name - Function name
     * @param {Object} funcs - Aggregate functions {init, step, finalize}
     * @returns {Database} this
     */
    create_aggregate(name, funcs) {
        console.warn(`[LanceQL] create_aggregate('${name}') not yet implemented`);
        return this;
    }

    /**
     * Format a value for SQL
     */
    _formatValue(val) {
        if (val === null || val === undefined) {
            return 'NULL';
        }
        if (typeof val === 'string') {
            return `'${val.replace(/'/g, "''")}'`;
        }
        if (typeof val === 'number') {
            return String(val);
        }
        if (typeof val === 'boolean') {
            return val ? 'TRUE' : 'FALSE';
        }
        if (Array.isArray(val)) {
            // Vector
            return `'[${val.join(',')}]'`;
        }
        return String(val);
    }
}

/**
 * Initialize LanceQL with sql.js-compatible API
 *
 * Drop-in replacement for initSqlJs():
 *
 * @example
 * // sql.js style
 * import initSqlJs from 'sql.js';
 * const SQL = await initSqlJs();
 * const db = new SQL.Database();
 *
 * // LanceQL replacement
 * import { initSqlJs } from 'lanceql';
 * const SQL = await initSqlJs();
 * const db = new SQL.Database('mydb'); // OPFS-persisted + vector search
 *
 * @param {Object} config - Configuration (for compatibility, mostly ignored)
 * @returns {Promise<{Database: class}>} SQL namespace with Database class
 */
export async function initSqlJs(config = {}) {
    // Initialize OPFS storage
    try {
        await opfsStorage.open();
    } catch (e) {
        console.warn('[LanceQL] OPFS not available:', e.message);
    }

    return {
        Database,
        Statement,
    };
}

// Also export as sqljs for explicit naming
export { Database as SqlJsDatabase, Statement as SqlJsStatement };

// Default export for convenience
export default LanceQL;
