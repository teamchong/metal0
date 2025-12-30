const binding = require('../build/Release/lanceql.node');

// ============================================================================
// SqliteError - Custom error class matching better-sqlite3
// ============================================================================

class SqliteError extends Error {
    constructor(message, code) {
        super(message);
        this.name = 'SqliteError';
        this.code = code || 'SQLITE_ERROR';
    }
}

// ============================================================================
// Database - Main database class matching better-sqlite3 API
// ============================================================================

class Database {
    constructor(filename, options = {}) {
        // Validate inputs like better-sqlite3
        if (filename === ':memory:' || filename === '') {
            throw new SqliteError('In-memory databases not supported', 'SQLITE_ERROR');
        }

        // Support both file paths and Buffer objects
        try {
            if (Buffer.isBuffer(filename)) {
                this._db = new binding.Database(filename, options);
                this._name = 'buffer';
            } else {
                this._db = new binding.Database(filename, options);
                this._name = filename;
            }
        } catch (err) {
            throw new SqliteError(err.message || 'Failed to open database', 'SQLITE_CANTOPEN');
        }

        this._open = true;
        // Lance files are always read-only, default to true unless explicitly set to false
        this._readonly = options.readonly !== false;
    }

    // Properties (getters matching better-sqlite3)
    get open() { return this._open; }
    get inTransaction() { return false; } // Always false for read-only Lance
    get readonly() { return this._readonly; }
    get memory() { return false; }
    get name() { return this._name; }

    prepare(sql) {
        if (!this._open) {
            throw new SqliteError('The database connection is not open', 'SQLITE_MISUSE');
        }

        if (typeof sql !== 'string') {
            throw new SqliteError('SQL must be a string', 'SQLITE_MISUSE');
        }

        try {
            const nativeStmt = this._db.prepare(sql);
            return new Statement(nativeStmt, this, sql);
        } catch (err) {
            throw new SqliteError(err.message || 'Failed to prepare statement', 'SQLITE_ERROR');
        }
    }

    exec(sql) {
        if (!this._open) {
            throw new SqliteError('The database connection is not open', 'SQLITE_MISUSE');
        }

        // For v0.1.0, exec is a no-op (Lance is read-only)
        // Just validate SQL syntax by trying to parse it
        if (typeof sql !== 'string') {
            throw new SqliteError('SQL must be a string', 'SQLITE_MISUSE');
        }

        return this; // Match better-sqlite3 chaining
    }

    pragma(sql, options) {
        if (!this._open) {
            throw new SqliteError('The database connection is not open', 'SQLITE_MISUSE');
        }

        // PRAGMA commands for metadata queries
        // For v0.1.0, only table_info is supported
        if (sql.startsWith('table_info')) {
            // Return empty array for now (would need lance_pragma_table_info export)
            return [];
        }

        return [];
    }

    transaction(fn) {
        if (!this._open) {
            throw new SqliteError('The database connection is not open', 'SQLITE_MISUSE');
        }

        // Transactions not supported for read-only Lance files
        throw new SqliteError('Transactions not supported in v0.1.0', 'SQLITE_ERROR');
    }

    close() {
        if (!this._open) return this;

        try {
            this._db.close();
            this._open = false;
        } catch (err) {
            throw new SqliteError(err.message || 'Failed to close database', 'SQLITE_ERROR');
        }

        return this; // Match better-sqlite3 chaining
    }

    // Stub methods that throw errors (not supported in v0.1.0)
    // Note: 'function' is a reserved word, so we use quoted property syntax
    'function'() {
        throw new SqliteError('User-defined functions not supported', 'SQLITE_ERROR');
    }

    aggregate() {
        throw new SqliteError('Aggregate functions not supported', 'SQLITE_ERROR');
    }

    table() {
        throw new SqliteError('Virtual tables not supported', 'SQLITE_ERROR');
    }

    loadExtension() {
        throw new SqliteError('Extensions not supported', 'SQLITE_ERROR');
    }

    backup() {
        throw new SqliteError('Backup not supported', 'SQLITE_ERROR');
    }

    serialize() {
        throw new SqliteError('Serialize not supported', 'SQLITE_ERROR');
    }

    defaultSafeIntegers(toggle) {
        // No-op for v0.1.0 (always uses JavaScript numbers)
        return this;
    }

    unsafeMode(toggle) {
        // No-op (always safe)
        return this;
    }
}

// ============================================================================
// Statement - Prepared statement class matching better-sqlite3 API
// ============================================================================

class Statement {
    constructor(nativeStmt, db, sql) {
        this._stmt = nativeStmt;
        this._db = db;
        this._sql = sql;
        this._pluck = false;
        this._expand = false;
        this._raw = false;
    }

    // Properties (getters matching better-sqlite3)
    get source() { return this._sql; }
    get readonly() { return this._sql.trim().toUpperCase().startsWith('SELECT'); }
    get database() { return this._db; }
    get reader() { return this.readonly; }
    get busy() { return false; } // Synchronous execution

    all(...params) {
        if (!this._stmt) {
            throw new SqliteError('Statement has been finalized', 'SQLITE_MISUSE');
        }

        // Use bound params if no params provided
        const actualParams = params.length > 0 ? params : (this._boundParams || []);

        try {
            // Pass parameters to native binding
            let rows = this._stmt.all(...actualParams);

            // Apply formatting modifiers
            if (this._raw) {
                // Convert {id: 1, name: 'John'} to [1, 'John']
                return rows.map(row => Object.values(row));
            }
            if (this._pluck) {
                // Return first column only
                return rows.map(row => Object.values(row)[0]);
            }
            if (this._expand) {
                // Namespace by table (if column metadata available)
                // For v0.1.0, just return as-is since we don't track table names yet
                return rows;
            }

            return rows;
        } catch (err) {
            throw new SqliteError(err.message || 'Failed to execute statement', 'SQLITE_ERROR');
        }
    }

    get(...params) {
        const rows = this.all(...params);
        return rows.length > 0 ? rows[0] : undefined;
    }

    run(...params) {
        if (!this.readonly) {
            throw new SqliteError('Write operations not supported in v0.1.0', 'SQLITE_READONLY');
        }

        // For SELECT queries, execute but return dummy write result
        try {
            this.all(...params);
            return { changes: 0, lastInsertRowid: 0 };
        } catch (err) {
            throw new SqliteError(err.message || 'Failed to execute statement', 'SQLITE_ERROR');
        }
    }

    iterate(...params) {
        // Return iterator matching better-sqlite3
        const rows = this.all(...params);
        return rows[Symbol.iterator]();
    }

    // Formatting methods (return this for chaining)
    pluck(toggle = true) {
        this._pluck = toggle;
        return this; // Enable chaining
    }

    expand(toggle = true) {
        this._expand = toggle;
        return this; // Enable chaining
    }

    raw(toggle = true) {
        this._raw = toggle;
        return this; // Enable chaining
    }

    columns() {
        // Return column metadata
        // For v0.1.0, execute query and extract column names from first row
        try {
            const rows = this._stmt.all();
            if (rows.length === 0) {
                return [];
            }

            // Return array of {name, column, table?, database?, type?}
            const firstRow = rows[0];
            return Object.keys(firstRow).map((name, index) => ({
                name: name,
                column: name,
                table: null,
                database: null,
                type: null
            }));
        } catch (err) {
            return [];
        }
    }

    bind(...params) {
        // Store parameters for use in all/get/run
        this._boundParams = params;
        return this;
    }

    safeIntegers(toggle = true) {
        // No-op for v0.1.0 (always uses JavaScript numbers)
        return this;
    }

    finalize() {
        // Explicitly release native statement resources
        // This is important for long-running applications or when creating many statements
        if (this._stmt && typeof this._stmt.finalize === 'function') {
            this._stmt.finalize();
        }
        this._stmt = null;
    }
}

// ============================================================================
// LocalDatabase - CRUD with ACID support
// ============================================================================

const { LocalDatabase, FileStorage, SQLLexer, LocalSQLParser, HotTierCache, hotTierCache, VectorAccelerator, vectorAccelerator } = require('./local-database');

// ============================================================================
// RemoteLanceDataset - HTTP Range-based remote dataset with IVF vector search
// ============================================================================

const https = require('https');
const http = require('http');

/**
 * Fetch a byte range from a URL.
 * @param {string} url - URL to fetch
 * @param {number} start - Start byte
 * @param {number} end - End byte (inclusive)
 * @returns {Promise<Buffer>}
 */
async function fetchRange(url, start, end) {
    return new Promise((resolve, reject) => {
        const protocol = url.startsWith('https') ? https : http;
        const options = {
            headers: { 'Range': `bytes=${start}-${end}` }
        };

        protocol.get(url, options, (res) => {
            const chunks = [];
            res.on('data', chunk => chunks.push(chunk));
            res.on('end', () => resolve(Buffer.concat(chunks)));
            res.on('error', reject);
        }).on('error', reject);
    });
}

/**
 * IVF Index for Node.js - mirrors browser implementation.
 */
class IVFIndex {
    constructor(baseUrl) {
        this.baseUrl = baseUrl;
        this.centroids = null;
        this.dimension = 0;
        this.numPartitions = 0;
        this.partitionOffsets = null;
        this.partitionVectorsUrl = null;
        this.hasPartitionIndex = false;
        this._partitionCache = new Map();
    }

    /**
     * Load IVF index from remote dataset.
     */
    async load() {
        // Try to load centroids
        const centroidsUrl = `${this.baseUrl}/_indices/vector_idx/centroids.npy`;
        try {
            const resp = await fetchRange(centroidsUrl, 0, 1024 * 1024); // First 1MB
            // Parse numpy header and extract centroids
            // Simplified: assume float32 array after 128-byte header
            const headerSize = 128;
            if (resp.length > headerSize) {
                const data = new Float32Array(resp.buffer.slice(headerSize));
                // Detect dimension from data size (256 partitions typical)
                this.numPartitions = 256;
                this.dimension = Math.floor(data.length / this.numPartitions);
                this.centroids = [];
                for (let i = 0; i < this.numPartitions; i++) {
                    this.centroids.push(data.slice(i * this.dimension, (i + 1) * this.dimension));
                }
                console.log(`[IVFIndex] Loaded ${this.numPartitions} centroids, dim=${this.dimension}`);
            }
        } catch (e) {
            console.log('[IVFIndex] No centroids found');
            return false;
        }

        // Try to load partition offsets
        const offsetsUrl = `${this.baseUrl}/_indices/vector_idx/ivf_partitions.bin`;
        try {
            const resp = await fetchRange(offsetsUrl, 0, (this.numPartitions + 1) * 8);
            this.partitionOffsets = new BigUint64Array(resp.buffer);
            this.partitionVectorsUrl = `${this.baseUrl}/_indices/vector_idx/ivf_vectors.bin`;
            this.hasPartitionIndex = true;
            console.log('[IVFIndex] Loaded partition offsets');
        } catch (e) {
            console.log('[IVFIndex] No partition offsets found');
        }

        return this.centroids !== null;
    }

    /**
     * Find nearest partition centroids.
     */
    findNearestPartitions(queryVec, nprobe = 10) {
        if (!this.centroids) return [];

        const distances = this.centroids.map((centroid, idx) => {
            let dot = 0;
            for (let i = 0; i < this.dimension; i++) {
                dot += queryVec[i] * centroid[i];
            }
            return { idx, score: dot };
        });

        distances.sort((a, b) => b.score - a.score);
        return distances.slice(0, nprobe).map(d => d.idx);
    }

    /**
     * Fetch partition data (row IDs + vectors).
     */
    async fetchPartitionData(partitionIndices, dim, onProgress = null) {
        if (!this.hasPartitionIndex) return null;

        const allRowIds = [];
        const allVectors = [];
        let totalBytes = 0;
        let loadedBytes = 0;

        // Check cache and calculate bytes to fetch
        const uncached = [];
        for (const p of partitionIndices) {
            if (this._partitionCache.has(p)) {
                const cached = this._partitionCache.get(p);
                allRowIds.push(...cached.rowIds);
                allVectors.push(...cached.vectors);
            } else {
                uncached.push(p);
                const start = Number(this.partitionOffsets[p]);
                const end = Number(this.partitionOffsets[p + 1]);
                totalBytes += end - start;
            }
        }

        if (uncached.length === 0) {
            if (onProgress) onProgress(100, 100);
            return { rowIds: allRowIds, vectors: allVectors };
        }

        console.log(`[IVFIndex] Fetching ${uncached.length} partitions, ${(totalBytes / 1024 / 1024).toFixed(1)} MB`);

        // Fetch in parallel
        const results = await Promise.all(uncached.map(async (p) => {
            const start = Number(this.partitionOffsets[p]);
            const end = Number(this.partitionOffsets[p + 1]) - 1;

            const data = await fetchRange(this.partitionVectorsUrl, start, end);
            const view = new DataView(data.buffer);

            const rowCount = view.getUint32(0, true);
            const rowIds = new Uint32Array(data.buffer.slice(4, 4 + rowCount * 4));
            const vectorsFlat = new Float32Array(data.buffer.slice(4 + rowCount * 4));

            const vectors = [];
            for (let j = 0; j < rowCount; j++) {
                vectors.push(vectorsFlat.slice(j * dim, (j + 1) * dim));
            }

            loadedBytes += data.length;
            if (onProgress) onProgress(loadedBytes, totalBytes);

            return { p, rowIds: Array.from(rowIds), vectors };
        }));

        // Cache and collect
        for (const { p, rowIds, vectors } of results) {
            this._partitionCache.set(p, { rowIds, vectors });
            allRowIds.push(...rowIds);
            allVectors.push(...vectors);
        }

        return { rowIds: allRowIds, vectors: allVectors };
    }
}

/**
 * Remote Lance Dataset with IVF vector search for Node.js.
 */
class RemoteLanceDataset {
    constructor(baseUrl) {
        this.baseUrl = baseUrl;
        this._ivfIndex = null;
    }

    /**
     * Open a remote dataset.
     */
    static async open(baseUrl) {
        const dataset = new RemoteLanceDataset(baseUrl);

        // Try to load IVF index
        dataset._ivfIndex = new IVFIndex(baseUrl);
        await dataset._ivfIndex.load();

        return dataset;
    }

    /**
     * Check if dataset has IVF index.
     */
    hasIndex() {
        return this._ivfIndex?.centroids !== null;
    }

    /**
     * Vector search using IVF index.
     * @param {Float32Array} queryVec - Query vector
     * @param {number} topK - Number of results
     * @param {Object} options - Search options
     * @returns {Promise<{indices: number[], scores: Float32Array}>}
     */
    async vectorSearch(queryVec, topK = 10, options = {}) {
        const { nprobe = 10, onProgress = null } = options;

        if (!this.hasIndex()) {
            throw new Error('No IVF index available');
        }

        // Find nearest partitions
        const partitions = this._ivfIndex.findNearestPartitions(queryVec, nprobe);

        // Fetch partition data
        const data = await this._ivfIndex.fetchPartitionData(
            partitions,
            this._ivfIndex.dimension,
            (loaded, total) => {
                if (onProgress) onProgress(Math.floor(loaded / total * 80), 100);
            }
        );

        if (!data || data.rowIds.length === 0) {
            throw new Error('No vectors found in partitions');
        }

        // Compute similarities using VectorAccelerator
        console.log(`[VectorSearch] Computing similarity for ${data.rowIds.length} vectors`);
        const scores = vectorAccelerator.batchCosineSimilarity(
            new Float32Array(queryVec),
            data.vectors.map(v => new Float32Array(v)),
            true
        );

        if (onProgress) onProgress(90, 100);

        // Find top-k
        const results = data.rowIds.map((idx, i) => ({ idx, score: scores[i] }));
        results.sort((a, b) => b.score - a.score);

        const topResults = results.slice(0, topK);

        if (onProgress) onProgress(100, 100);

        return {
            indices: topResults.map(r => r.idx),
            scores: new Float32Array(topResults.map(r => r.score))
        };
    }
}

// ============================================================================
// LogicTable - Hybrid JavaScript logic + Lance data queries
// ============================================================================

/**
 * Table source declaration.
 * @param {string} path - Path to Lance dataset
 * @param {Object} options - Options
 * @returns {Object} Table specification
 */
function Table(path, options = {}) {
    return {
        type: 'table',
        path,
        hotTier: options.hotTier || null,
        columns: options.columns || null
    };
}

/**
 * Query builder for LogicTable.
 */
class LogicTableQuery {
    constructor(logicDef, bindings = {}) {
        this._logicDef = logicDef;
        this._bindings = bindings;
        this._filters = [];
        this._projections = [];
        this._orderSpecs = [];
        this._limitVal = null;
        this._offsetVal = null;
    }

    bind(tables) {
        const query = this._clone();
        Object.assign(query._bindings, tables);
        return query;
    }

    filter(predicate) {
        const query = this._clone();
        query._filters.push(predicate);
        return query;
    }

    select(...columns) {
        const query = this._clone();
        query._projections = columns;
        return query;
    }

    orderBy(column, options = {}) {
        const query = this._clone();
        query._orderSpecs.push({ column, desc: options.desc || false });
        return query;
    }

    limit(n) {
        const query = this._clone();
        query._limitVal = n;
        return query;
    }

    offset(n) {
        const query = this._clone();
        query._offsetVal = n;
        return query;
    }

    _clone() {
        const query = new LogicTableQuery(this._logicDef, { ...this._bindings });
        query._filters = [...this._filters];
        query._projections = [...this._projections];
        query._orderSpecs = [...this._orderSpecs];
        query._limitVal = this._limitVal;
        query._offsetVal = this._offsetVal;
        return query;
    }

    _resolvePath(tableName, tableSpec) {
        return this._bindings[tableName] || tableSpec.path;
    }

    async _loadTable(path) {
        // Use LocalDatabase to load Lance files
        const db = new LocalDatabase(path);
        const rows = db.prepare('SELECT * FROM data').all();
        db.close();
        return rows;
    }

    async execute() {
        const { tables, methods } = this._logicDef;

        // Load all tables
        const tableData = {};
        for (const [name, spec] of Object.entries(tables)) {
            const path = this._resolvePath(name, spec);
            tableData[name] = await this._loadTable(path);
        }

        // Get primary table
        const primaryName = Object.keys(tables)[0];
        const primaryData = tableData[primaryName];

        const results = [];

        for (let i = 0; i < primaryData.length; i++) {
            // Create logic instance with current row bound
            const logicInstance = {};

            // Bind table accessors
            for (const [name, data] of Object.entries(tableData)) {
                const row = data[i] || data[0];
                logicInstance[name] = row;
            }

            // Bind methods
            for (const [name, fn] of Object.entries(methods || {})) {
                logicInstance[name] = fn.bind(logicInstance);
            }

            // Evaluate filters
            let pass = true;
            for (const filter of this._filters) {
                try {
                    if (!filter(logicInstance)) {
                        pass = false;
                        break;
                    }
                } catch {
                    pass = false;
                    break;
                }
            }

            if (!pass) continue;

            // Build result row
            let row;
            if (this._projections.length > 0) {
                row = {};
                for (const proj of this._projections) {
                    if (typeof proj === 'string') {
                        for (const data of Object.values(tableData)) {
                            if (proj in (data[i] || {})) {
                                row[proj] = data[i][proj];
                                break;
                            }
                        }
                    } else if (Array.isArray(proj)) {
                        const [fn, alias] = proj;
                        row[alias] = fn(logicInstance);
                    } else if (typeof proj === 'function') {
                        const value = proj(logicInstance);
                        row[`col_${Object.keys(row).length}`] = value;
                    }
                }
            } else {
                row = { ...primaryData[i] };
            }

            results.push(row);
        }

        // Apply ordering
        if (this._orderSpecs.length > 0) {
            results.sort((a, b) => {
                for (const spec of this._orderSpecs) {
                    let aVal, bVal;
                    if (typeof spec.column === 'string') {
                        aVal = a[spec.column];
                        bVal = b[spec.column];
                    } else {
                        aVal = a[Object.keys(a)[0]];
                        bVal = b[Object.keys(b)[0]];
                    }
                    const cmp = aVal < bVal ? -1 : aVal > bVal ? 1 : 0;
                    if (cmp !== 0) return spec.desc ? -cmp : cmp;
                }
                return 0;
            });
        }

        let finalResults = results;
        if (this._offsetVal) {
            finalResults = finalResults.slice(this._offsetVal);
        }
        if (this._limitVal) {
            finalResults = finalResults.slice(0, this._limitVal);
        }

        return finalResults;
    }

    explain() {
        const lines = [`LogicTable: ${this._logicDef.name || 'anonymous'}`];

        lines.push('Tables:');
        for (const [name, spec] of Object.entries(this._logicDef.tables)) {
            const path = this._resolvePath(name, spec);
            const hot = spec.hotTier ? ` (hotTier=${spec.hotTier})` : '';
            lines.push(`  ${name} = ${path}${hot}`);
        }

        if (this._filters.length > 0) {
            lines.push(`Filters: ${this._filters.length} predicate(s)`);
        }
        if (this._projections.length > 0) {
            lines.push(`Projections: ${this._projections.length} column(s)`);
        }
        if (this._orderSpecs.length > 0) {
            lines.push(`Order by: ${this._orderSpecs.length} key(s)`);
        }
        if (this._limitVal) {
            lines.push(`Limit: ${this._limitVal}`);
        }

        return lines.join('\n');
    }
}

/**
 * Create a LogicTable definition.
 * @param {Object} def - Definition with tables and methods
 * @returns {Object} LogicTable with query methods
 */
function logicTable(def) {
    const logicDef = {
        name: def.name || 'LogicTable',
        tables: def.tables || {},
        methods: def.methods || {}
    };

    return {
        _def: logicDef,

        filter(predicate) {
            return new LogicTableQuery(logicDef).filter(predicate);
        },

        select(...columns) {
            return new LogicTableQuery(logicDef).select(...columns);
        },

        bind(tables) {
            return new LogicTableQuery(logicDef).bind(tables);
        },

        orderBy(column, options) {
            return new LogicTableQuery(logicDef).orderBy(column, options);
        },

        limit(n) {
            return new LogicTableQuery(logicDef).limit(n);
        },

        query() {
            return new LogicTableQuery(logicDef);
        },

        async execute() {
            return new LogicTableQuery(logicDef).execute();
        }
    };
}

/**
 * Load a LogicTable from a JavaScript file.
 * @param {string} path - Path to JS file
 * @returns {Object} LogicTable
 */
function loadLogicTable(path) {
    const module = require(path);
    if (module.default && module.default._def) {
        return module.default;
    }
    if (module.Logic && module.Logic._def) {
        return module.Logic;
    }
    if (module._def) {
        return module;
    }
    throw new Error(`No LogicTable found in ${path}`);
}

// ============================================================================
// Exports - Match better-sqlite3 export format exactly
// ============================================================================

module.exports = Database;
module.exports.Database = Database;
module.exports.SqliteError = SqliteError;
module.exports.LocalDatabase = LocalDatabase;
module.exports.FileStorage = FileStorage;
module.exports.HotTierCache = HotTierCache;
module.exports.hotTierCache = hotTierCache;
module.exports.VectorAccelerator = VectorAccelerator;
module.exports.vectorAccelerator = vectorAccelerator;
module.exports.RemoteLanceDataset = RemoteLanceDataset;
module.exports.IVFIndex = IVFIndex;
module.exports.Table = Table;
module.exports.logicTable = logicTable;
module.exports.LogicTableQuery = LogicTableQuery;
module.exports.loadLogicTable = loadLogicTable;
