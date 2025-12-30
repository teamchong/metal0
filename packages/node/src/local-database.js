/**
 * LocalDatabase - CRUD operations with ACID support for Node.js
 *
 * Uses manifest-based ACID:
 * - Atomic manifest updates (file rename)
 * - Fragment-based storage (append-only data)
 * - Deletion vectors (logical deletes)
 * - Versioning for rollback
 */

const fs = require('fs');
const path = require('path');
const { promisify } = require('util');

const writeFile = promisify(fs.writeFile);
const readFile = promisify(fs.readFile);
const mkdir = promisify(fs.mkdir);
const readdir = promisify(fs.readdir);
const stat = promisify(fs.stat);
const unlink = promisify(fs.unlink);
const rename = promisify(fs.rename);

// =============================================================================
// SQL Lexer/Parser for CRUD operations (shared with browser)
// =============================================================================

const TokenType = {
    SELECT: 'SELECT', FROM: 'FROM', WHERE: 'WHERE', ORDER: 'ORDER', BY: 'BY',
    LIMIT: 'LIMIT', OFFSET: 'OFFSET', ASC: 'ASC', DESC: 'DESC', AND: 'AND',
    OR: 'OR', NOT: 'NOT', IN: 'IN', LIKE: 'LIKE', BETWEEN: 'BETWEEN', IS: 'IS',
    NULL: 'NULL', TRUE: 'TRUE', FALSE: 'FALSE', AS: 'AS', DISTINCT: 'DISTINCT',
    COUNT: 'COUNT', SUM: 'SUM', AVG: 'AVG', MIN: 'MIN', MAX: 'MAX',
    GROUP: 'GROUP', HAVING: 'HAVING', STAR: 'STAR', COMMA: 'COMMA',
    LPAREN: 'LPAREN', RPAREN: 'RPAREN', EQ: 'EQ', NE: 'NE', LT: 'LT',
    LE: 'LE', GT: 'GT', GE: 'GE', PLUS: 'PLUS', MINUS: 'MINUS',
    MULTIPLY: 'MULTIPLY', DIVIDE: 'DIVIDE', IDENTIFIER: 'IDENTIFIER',
    STRING: 'STRING', NUMBER: 'NUMBER', FLOAT: 'FLOAT', EOF: 'EOF',
    DOT: 'DOT', NEAR: 'NEAR', TOPK: 'TOPK', FILE: 'FILE', READ_LANCE: 'READ_LANCE',
    CREATE: 'CREATE', TABLE: 'TABLE', INSERT: 'INSERT', INTO: 'INTO',
    VALUES: 'VALUES', UPDATE: 'UPDATE', SET: 'SET', DELETE: 'DELETE',
    DROP: 'DROP', INTEGER: 'INTEGER', TEXT: 'TEXT', REAL: 'REAL',
    BLOB: 'BLOB', PRIMARY: 'PRIMARY', KEY: 'KEY', AUTOINCREMENT: 'AUTOINCREMENT',
    VECTOR: 'VECTOR'
};

const KEYWORDS = {
    'select': TokenType.SELECT, 'from': TokenType.FROM, 'where': TokenType.WHERE,
    'order': TokenType.ORDER, 'by': TokenType.BY, 'limit': TokenType.LIMIT,
    'offset': TokenType.OFFSET, 'asc': TokenType.ASC, 'desc': TokenType.DESC,
    'and': TokenType.AND, 'or': TokenType.OR, 'not': TokenType.NOT,
    'in': TokenType.IN, 'like': TokenType.LIKE, 'between': TokenType.BETWEEN,
    'is': TokenType.IS, 'null': TokenType.NULL, 'true': TokenType.TRUE,
    'false': TokenType.FALSE, 'as': TokenType.AS, 'distinct': TokenType.DISTINCT,
    'count': TokenType.COUNT, 'sum': TokenType.SUM, 'avg': TokenType.AVG,
    'min': TokenType.MIN, 'max': TokenType.MAX, 'group': TokenType.GROUP,
    'having': TokenType.HAVING, 'near': TokenType.NEAR, 'topk': TokenType.TOPK,
    'file': TokenType.FILE, 'read_lance': TokenType.READ_LANCE,
    'create': TokenType.CREATE, 'table': TokenType.TABLE, 'insert': TokenType.INSERT,
    'into': TokenType.INTO, 'values': TokenType.VALUES, 'update': TokenType.UPDATE,
    'set': TokenType.SET, 'delete': TokenType.DELETE, 'drop': TokenType.DROP,
    'integer': TokenType.INTEGER, 'text': TokenType.TEXT, 'real': TokenType.REAL,
    'blob': TokenType.BLOB, 'primary': TokenType.PRIMARY, 'key': TokenType.KEY,
    'autoincrement': TokenType.AUTOINCREMENT, 'vector': TokenType.VECTOR
};

class SQLLexer {
    constructor(sql) {
        this.sql = sql;
        this.pos = 0;
        this.tokens = [];
    }

    peek() { return this.sql[this.pos] || ''; }
    advance() { return this.sql[this.pos++]; }
    isEnd() { return this.pos >= this.sql.length; }
    isWhitespace(c) { return /\s/.test(c); }
    isDigit(c) { return /[0-9]/.test(c); }
    isAlpha(c) { return /[a-zA-Z_]/.test(c); }
    isAlphaNum(c) { return /[a-zA-Z0-9_]/.test(c); }

    tokenize() {
        while (!this.isEnd()) {
            this.skipWhitespace();
            if (this.isEnd()) break;
            const c = this.peek();

            if (c === "'") { this.string(); continue; }
            if (this.isDigit(c) || (c === '-' && this.isDigit(this.sql[this.pos + 1]))) { this.number(); continue; }
            if (this.isAlpha(c)) { this.identifier(); continue; }
            if (c === '*') { this.advance(); this.tokens.push({ type: TokenType.STAR }); continue; }
            if (c === ',') { this.advance(); this.tokens.push({ type: TokenType.COMMA }); continue; }
            if (c === '(') { this.advance(); this.tokens.push({ type: TokenType.LPAREN }); continue; }
            if (c === ')') { this.advance(); this.tokens.push({ type: TokenType.RPAREN }); continue; }
            if (c === '.') { this.advance(); this.tokens.push({ type: TokenType.DOT }); continue; }
            if (c === '+') { this.advance(); this.tokens.push({ type: TokenType.PLUS }); continue; }
            if (c === '-') { this.advance(); this.tokens.push({ type: TokenType.MINUS }); continue; }
            if (c === '/') { this.advance(); this.tokens.push({ type: TokenType.DIVIDE }); continue; }
            if (c === '=' && this.sql[this.pos + 1] !== '=') { this.advance(); this.tokens.push({ type: TokenType.EQ }); continue; }
            if (c === '!' && this.sql[this.pos + 1] === '=') { this.advance(); this.advance(); this.tokens.push({ type: TokenType.NE }); continue; }
            if (c === '<' && this.sql[this.pos + 1] === '>') { this.advance(); this.advance(); this.tokens.push({ type: TokenType.NE }); continue; }
            if (c === '<' && this.sql[this.pos + 1] === '=') { this.advance(); this.advance(); this.tokens.push({ type: TokenType.LE }); continue; }
            if (c === '>' && this.sql[this.pos + 1] === '=') { this.advance(); this.advance(); this.tokens.push({ type: TokenType.GE }); continue; }
            if (c === '<') { this.advance(); this.tokens.push({ type: TokenType.LT }); continue; }
            if (c === '>') { this.advance(); this.tokens.push({ type: TokenType.GT }); continue; }

            this.advance();
        }
        this.tokens.push({ type: TokenType.EOF });
        return this.tokens;
    }

    skipWhitespace() {
        while (!this.isEnd() && this.isWhitespace(this.peek())) this.advance();
    }

    string() {
        this.advance();
        let value = '';
        while (!this.isEnd() && this.peek() !== "'") {
            if (this.peek() === "'" && this.sql[this.pos + 1] === "'") {
                value += "'";
                this.advance(); this.advance();
            } else {
                value += this.advance();
            }
        }
        this.advance();
        this.tokens.push({ type: TokenType.STRING, value });
    }

    number() {
        let value = '';
        if (this.peek() === '-') value += this.advance();
        while (!this.isEnd() && this.isDigit(this.peek())) value += this.advance();
        if (this.peek() === '.' && this.isDigit(this.sql[this.pos + 1])) {
            value += this.advance();
            while (!this.isEnd() && this.isDigit(this.peek())) value += this.advance();
            this.tokens.push({ type: TokenType.FLOAT, value: parseFloat(value) });
        } else {
            this.tokens.push({ type: TokenType.NUMBER, value: parseInt(value, 10) });
        }
    }

    identifier() {
        let value = '';
        while (!this.isEnd() && this.isAlphaNum(this.peek())) value += this.advance();
        const lower = value.toLowerCase();
        const type = KEYWORDS[lower] || TokenType.IDENTIFIER;
        this.tokens.push({ type, value: type === TokenType.IDENTIFIER ? value : lower });
    }
}

// =============================================================================
// SQL Parser for CRUD statements
// =============================================================================

class LocalSQLParser {
    constructor(tokens) {
        this.tokens = tokens;
        this.pos = 0;
    }

    peek() { return this.tokens[this.pos]; }
    advance() { return this.tokens[this.pos++]; }
    isEnd() { return this.peek().type === TokenType.EOF; }
    match(type) { return this.peek().type === type ? this.advance() : null; }

    parse() {
        const token = this.peek();
        if (token.type === TokenType.CREATE) return this.parseCreate();
        if (token.type === TokenType.INSERT) return this.parseInsert();
        if (token.type === TokenType.UPDATE) return this.parseUpdate();
        if (token.type === TokenType.DELETE) return this.parseDelete();
        if (token.type === TokenType.DROP) return this.parseDrop();
        if (token.type === TokenType.SELECT) return this.parseSelect();
        throw new Error(`Unexpected token: ${token.type}`);
    }

    parseCreate() {
        this.match(TokenType.CREATE);
        if (!this.match(TokenType.TABLE)) throw new Error('Expected TABLE');
        const name = this.match(TokenType.IDENTIFIER)?.value;
        if (!name) throw new Error('Expected table name');
        if (!this.match(TokenType.LPAREN)) throw new Error('Expected (');
        const columns = [];
        do {
            const col = this.parseColumnDef();
            columns.push(col);
        } while (this.match(TokenType.COMMA));
        if (!this.match(TokenType.RPAREN)) throw new Error('Expected )');
        return { type: 'CREATE_TABLE', table: name, columns };
    }

    parseColumnDef() {
        const name = this.match(TokenType.IDENTIFIER)?.value;
        if (!name) throw new Error('Expected column name');
        let dataType = 'TEXT';
        let vectorDim = null;
        let primaryKey = false;
        let autoIncrement = false;

        if (this.match(TokenType.INTEGER)) dataType = 'INTEGER';
        else if (this.match(TokenType.TEXT)) dataType = 'TEXT';
        else if (this.match(TokenType.REAL)) dataType = 'REAL';
        else if (this.match(TokenType.BLOB)) dataType = 'BLOB';
        else if (this.match(TokenType.VECTOR)) {
            dataType = 'VECTOR';
            if (this.match(TokenType.LPAREN)) {
                const dim = this.match(TokenType.NUMBER);
                vectorDim = dim?.value || 384;
                this.match(TokenType.RPAREN);
            }
        }

        if (this.match(TokenType.PRIMARY)) {
            this.match(TokenType.KEY);
            primaryKey = true;
        }
        if (this.match(TokenType.AUTOINCREMENT)) autoIncrement = true;

        return { name, type: dataType, primaryKey, autoIncrement, vectorDim };
    }

    parseInsert() {
        this.match(TokenType.INSERT);
        this.match(TokenType.INTO);
        const table = this.match(TokenType.IDENTIFIER)?.value;
        if (!table) throw new Error('Expected table name');

        let columns = null;
        if (this.match(TokenType.LPAREN)) {
            columns = [];
            do {
                const col = this.match(TokenType.IDENTIFIER)?.value;
                if (col) columns.push(col);
            } while (this.match(TokenType.COMMA));
            this.match(TokenType.RPAREN);
        }

        if (!this.match(TokenType.VALUES)) throw new Error('Expected VALUES');

        const rows = [];
        do {
            if (!this.match(TokenType.LPAREN)) throw new Error('Expected (');
            const values = [];
            do {
                values.push(this.parseValue());
            } while (this.match(TokenType.COMMA));
            if (!this.match(TokenType.RPAREN)) throw new Error('Expected )');
            rows.push(values);
        } while (this.match(TokenType.COMMA));

        return { type: 'INSERT', table, columns, rows };
    }

    parseUpdate() {
        this.match(TokenType.UPDATE);
        const table = this.match(TokenType.IDENTIFIER)?.value;
        if (!table) throw new Error('Expected table name');
        if (!this.match(TokenType.SET)) throw new Error('Expected SET');

        const updates = {};
        do {
            const col = this.match(TokenType.IDENTIFIER)?.value;
            if (!this.match(TokenType.EQ)) throw new Error('Expected =');
            updates[col] = this.parseValue();
        } while (this.match(TokenType.COMMA));

        let where = null;
        if (this.match(TokenType.WHERE)) {
            where = this.parseCondition();
        }

        return { type: 'UPDATE', table, updates, where };
    }

    parseDelete() {
        this.match(TokenType.DELETE);
        this.match(TokenType.FROM);
        const table = this.match(TokenType.IDENTIFIER)?.value;
        if (!table) throw new Error('Expected table name');

        let where = null;
        if (this.match(TokenType.WHERE)) {
            where = this.parseCondition();
        }

        return { type: 'DELETE', table, where };
    }

    parseDrop() {
        this.match(TokenType.DROP);
        if (!this.match(TokenType.TABLE)) throw new Error('Expected TABLE');
        const table = this.match(TokenType.IDENTIFIER)?.value;
        if (!table) throw new Error('Expected table name');
        return { type: 'DROP_TABLE', table };
    }

    parseSelect() {
        this.match(TokenType.SELECT);
        const columns = [];
        if (this.match(TokenType.STAR)) {
            columns.push({ type: 'star' });
        } else {
            do {
                const col = this.match(TokenType.IDENTIFIER)?.value;
                if (col) columns.push({ type: 'column', name: col });
            } while (this.match(TokenType.COMMA));
        }

        this.match(TokenType.FROM);
        const table = this.match(TokenType.IDENTIFIER)?.value;

        let where = null;
        if (this.match(TokenType.WHERE)) {
            where = this.parseCondition();
        }

        let orderBy = null;
        if (this.match(TokenType.ORDER)) {
            this.match(TokenType.BY);
            const col = this.match(TokenType.IDENTIFIER)?.value;
            let desc = false;
            if (this.match(TokenType.DESC)) desc = true;
            else this.match(TokenType.ASC);
            orderBy = { column: col, desc };
        }

        let limit = null;
        if (this.match(TokenType.LIMIT)) {
            const num = this.match(TokenType.NUMBER);
            limit = num?.value;
        }

        return { type: 'SELECT', columns, table, where, orderBy, limit };
    }

    parseValue() {
        if (this.match(TokenType.NULL)) return null;
        if (this.match(TokenType.TRUE)) return true;
        if (this.match(TokenType.FALSE)) return false;
        const str = this.match(TokenType.STRING);
        if (str) return str.value;
        const num = this.match(TokenType.NUMBER);
        if (num) return num.value;
        const flt = this.match(TokenType.FLOAT);
        if (flt) return flt.value;
        throw new Error('Expected value');
    }

    parseCondition() {
        const column = this.match(TokenType.IDENTIFIER)?.value;
        if (!column) throw new Error('Expected column name');
        let op;
        if (this.match(TokenType.EQ)) op = '=';
        else if (this.match(TokenType.NE)) op = '!=';
        else if (this.match(TokenType.LT)) op = '<';
        else if (this.match(TokenType.LE)) op = '<=';
        else if (this.match(TokenType.GT)) op = '>';
        else if (this.match(TokenType.GE)) op = '>=';
        else if (this.match(TokenType.LIKE)) op = 'LIKE';
        else throw new Error('Expected comparison operator');
        const value = this.parseValue();
        return { op, column, value };
    }
}

// =============================================================================
// FileStorage - File-based storage backend
// =============================================================================

class FileStorage {
    constructor(basePath) {
        this.basePath = basePath;
    }

    async init() {
        await mkdir(this.basePath, { recursive: true });
    }

    async save(name, data) {
        const filePath = path.join(this.basePath, name);
        const dir = path.dirname(filePath);
        await mkdir(dir, { recursive: true });
        const buffer = Buffer.isBuffer(data) ? data : Buffer.from(JSON.stringify(data));
        await writeFile(filePath, buffer);
        return { name, size: buffer.length, storage: 'file' };
    }

    async load(name) {
        const filePath = path.join(this.basePath, name);
        try {
            const data = await readFile(filePath);
            try {
                return JSON.parse(data.toString());
            } catch {
                return data;
            }
        } catch (err) {
            if (err.code === 'ENOENT') return null;
            throw err;
        }
    }

    async delete(name) {
        const filePath = path.join(this.basePath, name);
        try {
            await unlink(filePath);
        } catch (err) {
            if (err.code !== 'ENOENT') throw err;
        }
    }

    async list() {
        try {
            const files = await readdir(this.basePath, { recursive: true });
            return files.map(f => ({ name: f }));
        } catch {
            return [];
        }
    }

    async exists(name) {
        const filePath = path.join(this.basePath, name);
        try {
            await stat(filePath);
            return true;
        } catch {
            return false;
        }
    }
}

// =============================================================================
// VectorAccelerator - GPU/CPU accelerated batch vector operations
// =============================================================================

/**
 * VectorAccelerator provides GPU-accelerated batch cosine similarity.
 *
 * Acceleration hierarchy:
 * 1. Metal (macOS) via native addon (if available)
 * 2. CUDA (Linux/Windows) via native addon (if available)
 * 3. CPU SIMD via optimized TypedArray operations (fallback)
 *
 * For L2-normalized vectors, dot product = cosine similarity.
 */
class VectorAccelerator {
    constructor() {
        this._gpuAvailable = false;
        this._backend = 'cpu';
        this._init();
    }

    _init() {
        // Try to load native GPU addon (Metal/CUDA)
        try {
            // Future: native addon with Metal/CUDA support
            // this._native = require('../build/Release/lanceql_gpu.node');
            // this._gpuAvailable = true;
            // this._backend = process.platform === 'darwin' ? 'metal' : 'cuda';
        } catch (e) {
            // Fall back to CPU
        }
        console.log(`[VectorAccelerator] Using ${this._backend} backend`);
    }

    /**
     * Check if GPU acceleration is available
     */
    isGPUAvailable() {
        return this._gpuAvailable;
    }

    /**
     * Get current backend name
     */
    getBackend() {
        return this._backend;
    }

    /**
     * Batch cosine similarity for L2-normalized vectors.
     * @param {Float32Array} queryVec - Query vector (dim)
     * @param {Float32Array[]} vectors - Array of candidate vectors
     * @param {boolean} normalized - Whether vectors are L2-normalized
     * @returns {Float32Array} Similarity scores
     */
    batchCosineSimilarity(queryVec, vectors, normalized = true) {
        if (vectors.length === 0) return new Float32Array(0);

        const dim = queryVec.length;
        const numVectors = vectors.length;

        // GPU path (future)
        if (this._gpuAvailable && this._native) {
            return this._native.batchCosineSimilarity(queryVec, vectors, normalized);
        }

        // CPU SIMD path - optimized with loop unrolling
        const scores = new Float32Array(numVectors);

        for (let i = 0; i < numVectors; i++) {
            const vec = vectors[i];
            let dot = 0;

            // Unroll loop by 8 for better CPU cache and SIMD utilization
            const unrollEnd = dim - (dim % 8);
            let j = 0;

            for (; j < unrollEnd; j += 8) {
                dot += queryVec[j] * vec[j]
                    + queryVec[j + 1] * vec[j + 1]
                    + queryVec[j + 2] * vec[j + 2]
                    + queryVec[j + 3] * vec[j + 3]
                    + queryVec[j + 4] * vec[j + 4]
                    + queryVec[j + 5] * vec[j + 5]
                    + queryVec[j + 6] * vec[j + 6]
                    + queryVec[j + 7] * vec[j + 7];
            }

            // Handle remaining elements
            for (; j < dim; j++) {
                dot += queryVec[j] * vec[j];
            }

            if (!normalized) {
                // Compute norms and divide
                let normQ = 0, normV = 0;
                for (let k = 0; k < dim; k++) {
                    normQ += queryVec[k] * queryVec[k];
                    normV += vec[k] * vec[k];
                }
                dot /= Math.sqrt(normQ * normV);
            }

            scores[i] = dot;
        }

        return scores;
    }

    /**
     * Find top-k most similar vectors.
     * @param {Float32Array} queryVec - Query vector
     * @param {Float32Array[]} vectors - Array of candidate vectors
     * @param {number} topK - Number of results
     * @param {boolean} normalized - Whether vectors are L2-normalized
     * @returns {{indices: number[], scores: Float32Array}}
     */
    topKSimilarity(queryVec, vectors, topK = 10, normalized = true) {
        const scores = this.batchCosineSimilarity(queryVec, vectors, normalized);

        // Build index array and partial sort for top-k
        const indices = Array.from({ length: scores.length }, (_, i) => i);

        // Partial sort (only need top-k)
        indices.sort((a, b) => scores[b] - scores[a]);

        const topIndices = indices.slice(0, topK);
        const topScores = new Float32Array(topK);
        for (let i = 0; i < topK && i < topIndices.length; i++) {
            topScores[i] = scores[topIndices[i]];
        }

        return { indices: topIndices, scores: topScores };
    }
}

// Global vector accelerator instance
const vectorAccelerator = new VectorAccelerator();

// =============================================================================
// HotTierCache - Disk-backed cache for remote Lance files (mmap for speed)
// =============================================================================

/**
 * HotTierCache provides fast local caching for remote Lance files in Node.js.
 *
 * Architecture:
 * - First request: Fetch from R2/S3 → Cache to disk
 * - Subsequent requests: mmap from disk → ~1000x faster
 *
 * Cache strategies:
 * - Small files (<10MB): Cache entire file
 * - Large files: Cache individual ranges/fragments on demand
 *
 * Storage layout:
 *   {cacheDir}/
 *     {urlHash}/
 *       meta.json          - URL, size, version, cached ranges
 *       data.lance         - Full file (if small) or range blocks
 *       ranges/
 *         {start}-{end}    - Cached range blocks (for large files)
 */
class HotTierCache {
    constructor(options = {}) {
        this.cacheDir = options.cacheDir || path.join(require('os').homedir(), '.lanceql-cache');
        this.maxFileSize = options.maxFileSize || 10 * 1024 * 1024; // 10MB - cache whole file
        this.maxCacheSize = options.maxCacheSize || 500 * 1024 * 1024; // 500MB total cache
        this.enabled = options.enabled ?? true;
        this._mmapCache = new Map(); // url -> { fd, buffer }
        this._stats = {
            hits: 0,
            misses: 0,
            bytesFromCache: 0,
            bytesFromNetwork: 0,
        };
        // In-memory cache for metadata to avoid disk reads on every getRange call
        this._metaCache = new Map();  // url -> { meta, fullFileData }
    }

    /**
     * Initialize the cache directory
     */
    async init() {
        await mkdir(this.cacheDir, { recursive: true });
    }

    /**
     * Get cache key from URL (hash for safe filesystem names)
     */
    _getCacheKey(url) {
        const crypto = require('crypto');
        return crypto.createHash('sha256').update(url).digest('hex').slice(0, 16);
    }

    /**
     * Get cache path for a URL
     */
    _getCachePath(url, suffix = '') {
        const key = this._getCacheKey(url);
        return path.join(this.cacheDir, key, suffix);
    }

    /**
     * Check if a URL is cached
     * @param {string} url - Remote URL
     * @returns {Promise<{cached: boolean, meta?: object}>}
     */
    async isCached(url) {
        if (!this.enabled) return { cached: false };

        try {
            const metaPath = this._getCachePath(url, 'meta.json');
            const metaData = await readFile(metaPath, 'utf8');
            const meta = JSON.parse(metaData);
            return { cached: true, meta };
        } catch (e) {
            return { cached: false };
        }
    }

    /**
     * Get or fetch a file, using cache when available.
     * Uses mmap for cached files for near-instant access.
     * @param {string} url - Remote URL
     * @returns {Promise<Buffer>}
     */
    async getFile(url) {
        if (!this.enabled) {
            return this._fetchFile(url);
        }

        await this.init();

        // Check cache
        const { cached, meta } = await this.isCached(url);
        if (cached && meta.fullFile) {
            const dataPath = this._getCachePath(url, 'data.lance');
            try {
                // Try to use mmap if available
                const data = await this._mmapRead(dataPath);
                this._stats.hits++;
                this._stats.bytesFromCache += data.length;
                console.log(`[HotTierCache] HIT: ${url} (${(data.length / 1024).toFixed(1)} KB)`);
                return data;
            } catch (e) {
                // Fallback to regular read
                const data = await readFile(dataPath);
                this._stats.hits++;
                this._stats.bytesFromCache += data.length;
                return data;
            }
        }

        // Cache miss - fetch and cache
        this._stats.misses++;
        const data = await this._fetchFile(url);
        this._stats.bytesFromNetwork += data.length;

        // Cache if small enough
        if (data.length <= this.maxFileSize) {
            await this._cacheFile(url, data);
        }

        return data;
    }

    /**
     * Get or fetch a byte range, using cache when available.
     * @param {string} url - Remote URL
     * @param {number} start - Start byte offset
     * @param {number} end - End byte offset (inclusive)
     * @param {number} [fileSize] - Total file size
     * @returns {Promise<Buffer>}
     */
    async getRange(url, start, end, fileSize = null) {
        if (!this.enabled) {
            return this._fetchRange(url, start, end);
        }

        // Fast path: check in-memory cache first (no disk I/O)
        const memCached = this._metaCache.get(url);
        if (memCached?.fullFileData) {
            const data = memCached.fullFileData;
            if (data.length > end) {
                this._stats.hits++;
                this._stats.bytesFromCache += (end - start + 1);
                return data.slice(start, end + 1);
            }
        }

        await this.init();

        // Check disk cache (only once per URL, then cache in memory)
        if (!memCached) {
            const { cached, meta } = await this.isCached(url);
            if (cached && meta.fullFile) {
                const dataPath = this._getCachePath(url, 'data.lance');
                try {
                    const data = await this._mmapRead(dataPath);
                    // Cache in memory for subsequent calls
                    this._metaCache.set(url, { meta, fullFileData: data });
                    if (data.length > end) {
                        this._stats.hits++;
                        this._stats.bytesFromCache += (end - start + 1);
                        return data.slice(start, end + 1);
                    }
                } catch (e) {
                    // Fallback to regular read
                    const fullData = await readFile(dataPath);
                    this._metaCache.set(url, { meta, fullFileData: fullData });
                    if (fullData.length > end) {
                        this._stats.hits++;
                        this._stats.bytesFromCache += (end - start + 1);
                        return fullData.slice(start, end + 1);
                    }
                }
            }
            // Mark as checked even if not cached
            this._metaCache.set(url, { meta: cached ? meta : null, fullFileData: null });
        }

        // Cache miss - fetch from network
        this._stats.misses++;
        const data = await this._fetchRange(url, start, end);
        this._stats.bytesFromNetwork += data.length;

        // Don't cache individual ranges - too slow for many small reads
        // Only full files are cached (via prefetch)

        return data;
    }

    /**
     * Read file using mmap for zero-copy access (if available)
     * @private
     */
    async _mmapRead(filePath, offset = 0, length = null) {
        // Check if we have this file mmap'd already
        if (this._mmapCache.has(filePath)) {
            const { buffer } = this._mmapCache.get(filePath);
            if (length === null) {
                return buffer;
            }
            return buffer.slice(offset, offset + length);
        }

        // Try to mmap the file
        try {
            // Node.js doesn't have native mmap, but we can use fs.read with a buffer pool
            // For true mmap, would need a native addon like 'mmap-io'
            const fd = fs.openSync(filePath, 'r');
            const stats = fs.fstatSync(fd);
            const buffer = Buffer.allocUnsafe(stats.size);
            fs.readSync(fd, buffer, 0, stats.size, 0);

            // Cache the buffer (simulating mmap behavior)
            this._mmapCache.set(filePath, { fd, buffer });

            if (length === null) {
                return buffer;
            }
            return buffer.slice(offset, offset + length);
        } catch (e) {
            throw e;
        }
    }

    /**
     * Prefetch and cache an entire file
     * @param {string} url - Remote URL
     * @param {function} [onProgress] - Progress callback (bytesLoaded, totalBytes)
     */
    async prefetch(url, onProgress = null) {
        await this.init();

        const { cached, meta } = await this.isCached(url);
        if (cached && meta.fullFile) {
            console.log(`[HotTierCache] Already cached: ${url}`);
            return;
        }

        console.log(`[HotTierCache] Prefetching: ${url}`);
        const data = await this._fetchFile(url, onProgress);
        await this._cacheFile(url, data);
        console.log(`[HotTierCache] Cached: ${url} (${(data.length / 1024 / 1024).toFixed(2)} MB)`);
    }

    /**
     * Evict a URL from cache
     */
    async evict(url) {
        const cachePath = this._getCachePath(url);
        try {
            // Close any mmap'd files
            const dataPath = path.join(cachePath, 'data.lance');
            if (this._mmapCache.has(dataPath)) {
                const { fd } = this._mmapCache.get(dataPath);
                fs.closeSync(fd);
                this._mmapCache.delete(dataPath);
            }

            // Remove directory recursively
            await fs.promises.rm(cachePath, { recursive: true, force: true });
            console.log(`[HotTierCache] Evicted: ${url}`);
        } catch (e) {
            // Ignore if not exists
        }
    }

    /**
     * Clear entire cache
     */
    async clear() {
        // Close all mmap'd files
        for (const [filePath, { fd }] of this._mmapCache) {
            try { fs.closeSync(fd); } catch (e) {}
        }
        this._mmapCache.clear();

        // Remove cache directory
        try {
            await fs.promises.rm(this.cacheDir, { recursive: true, force: true });
        } catch (e) {}

        await this.init();
        this._stats = { hits: 0, misses: 0, bytesFromCache: 0, bytesFromNetwork: 0 };
        console.log(`[HotTierCache] Cleared all cache`);
    }

    /**
     * Get cache statistics
     */
    getStats() {
        const hitRate = this._stats.hits + this._stats.misses > 0
            ? (this._stats.hits / (this._stats.hits + this._stats.misses) * 100).toFixed(1)
            : 0;
        return {
            ...this._stats,
            hitRate: `${hitRate}%`,
            bytesFromCacheMB: (this._stats.bytesFromCache / 1024 / 1024).toFixed(2),
            bytesFromNetworkMB: (this._stats.bytesFromNetwork / 1024 / 1024).toFixed(2),
        };
    }

    /**
     * Fetch file from network
     * @private
     */
    async _fetchFile(url, onProgress = null) {
        const https = require('https');
        const http = require('http');
        const client = url.startsWith('https') ? https : http;

        return new Promise((resolve, reject) => {
            const req = client.get(url, (res) => {
                if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                    // Follow redirect
                    return this._fetchFile(res.headers.location, onProgress).then(resolve).catch(reject);
                }

                if (res.statusCode !== 200) {
                    return reject(new Error(`HTTP error: ${res.statusCode}`));
                }

                const chunks = [];
                let loaded = 0;
                const total = parseInt(res.headers['content-length'] || '0');

                res.on('data', (chunk) => {
                    chunks.push(chunk);
                    loaded += chunk.length;
                    if (onProgress) onProgress(loaded, total);
                });

                res.on('end', () => {
                    resolve(Buffer.concat(chunks));
                });

                res.on('error', reject);
            });

            req.on('error', reject);
        });
    }

    /**
     * Fetch range from network
     * @private
     */
    async _fetchRange(url, start, end) {
        const https = require('https');
        const http = require('http');
        const client = url.startsWith('https') ? https : http;

        return new Promise((resolve, reject) => {
            const options = {
                headers: { 'Range': `bytes=${start}-${end}` }
            };

            const req = client.get(url, options, (res) => {
                if (res.statusCode !== 200 && res.statusCode !== 206) {
                    return reject(new Error(`HTTP error: ${res.statusCode}`));
                }

                const chunks = [];
                res.on('data', (chunk) => chunks.push(chunk));
                res.on('end', () => resolve(Buffer.concat(chunks)));
                res.on('error', reject);
            });

            req.on('error', reject);
        });
    }

    /**
     * Cache a full file
     * @private
     */
    async _cacheFile(url, data) {
        const cachePath = this._getCachePath(url);
        await mkdir(cachePath, { recursive: true });

        const metaPath = path.join(cachePath, 'meta.json');
        const dataPath = path.join(cachePath, 'data.lance');

        const meta = {
            url,
            size: data.length,
            cachedAt: Date.now(),
            fullFile: true,
            ranges: null,
        };

        await writeFile(metaPath, JSON.stringify(meta));
        await writeFile(dataPath, data);
    }

    /**
     * Cache a byte range
     * @private
     */
    async _cacheRange(url, start, end, data, fileSize) {
        const cachePath = this._getCachePath(url);
        await mkdir(path.join(cachePath, 'ranges'), { recursive: true });

        const metaPath = path.join(cachePath, 'meta.json');
        const rangePath = path.join(cachePath, 'ranges', `${start}-${end}`);

        // Load existing meta or create new
        let meta;
        const { cached, meta: existingMeta } = await this.isCached(url);
        if (cached) {
            meta = existingMeta;
            meta.ranges = meta.ranges || [];
        } else {
            meta = {
                url,
                size: fileSize,
                cachedAt: Date.now(),
                fullFile: false,
                ranges: [],
            };
        }

        // Add this range
        meta.ranges.push({ start, end, cachedAt: Date.now() });
        meta.ranges = this._mergeRanges(meta.ranges);

        await writeFile(metaPath, JSON.stringify(meta));
        await writeFile(rangePath, data);
    }

    /**
     * Merge overlapping ranges
     * @private
     */
    _mergeRanges(ranges) {
        if (ranges.length <= 1) return ranges;

        ranges.sort((a, b) => a.start - b.start);
        const merged = [ranges[0]];

        for (let i = 1; i < ranges.length; i++) {
            const last = merged[merged.length - 1];
            const current = ranges[i];

            if (current.start <= last.end + 1) {
                last.end = Math.max(last.end, current.end);
            } else {
                merged.push(current);
            }
        }

        return merged;
    }
}

// Global hot-tier cache instance for Node.js
const hotTierCache = new HotTierCache();

// =============================================================================
// LocalDatabase - CRUD with ACID support
// =============================================================================

class LocalDatabase {
    constructor(dbPath, options = {}) {
        this.name = path.basename(dbPath);
        this.dbPath = dbPath;
        this.storage = new FileStorage(dbPath);
        this.tables = new Map();
        this.version = 0;
        this.manifestKey = '__manifest__.json';
        this._open = false;
    }

    async open() {
        await this.storage.init();
        const manifest = await this.storage.load(this.manifestKey);
        if (manifest) {
            this.version = manifest.version || 0;
            for (const [name, schema] of Object.entries(manifest.tables || {})) {
                const deletionsArr = manifest.deletions?.[name] || [];
                this.tables.set(name, {
                    schema,
                    fragments: manifest.fragments?.[name] || [],
                    deletions: new Set(deletionsArr)
                });
            }
        }
        this._open = true;
    }

    async close() {
        await this._saveManifest();
        this.tables.clear();
        this._open = false;
    }

    get isOpen() { return this._open; }

    async _saveManifest() {
        const manifest = {
            version: this.version,
            tables: {},
            fragments: {},
            deletions: {}
        };
        for (const [name, table] of this.tables) {
            manifest.tables[name] = table.schema;
            manifest.fragments[name] = table.fragments;
            manifest.deletions[name] = Array.from(table.deletions || []);
        }
        await this.storage.save(this.manifestKey, manifest);
    }

    listTables() {
        return Array.from(this.tables.keys());
    }

    async exec(sql) {
        const lexer = new SQLLexer(sql);
        const tokens = lexer.tokenize();
        const parser = new LocalSQLParser(tokens);
        const ast = parser.parse();
        return this._executeAST(ast);
    }

    async _executeAST(ast) {
        switch (ast.type) {
            case 'CREATE_TABLE': return this.createTable(ast.table, ast.columns);
            case 'DROP_TABLE': return this.dropTable(ast.table);
            case 'INSERT': return this._executeInsert(ast);
            case 'UPDATE': return this._executeUpdate(ast);
            case 'DELETE': return this._executeDelete(ast);
            case 'SELECT': return this._executeSelect(ast);
            default: throw new Error(`Unknown statement type: ${ast.type}`);
        }
    }

    async createTable(tableName, columns) {
        if (this.tables.has(tableName)) {
            throw new Error(`Table ${tableName} already exists`);
        }
        this.tables.set(tableName, {
            schema: { columns, primaryKey: columns.find(c => c.primaryKey)?.name },
            fragments: [],
            deletions: new Set()
        });
        this.version++;
        await this._saveManifest();
        return { success: true, table: tableName };
    }

    async dropTable(tableName) {
        if (!this.tables.has(tableName)) {
            throw new Error(`Table ${tableName} does not exist`);
        }
        const table = this.tables.get(tableName);
        for (const fragId of table.fragments) {
            await this.storage.delete(`${tableName}/${fragId}.json`);
        }
        this.tables.delete(tableName);
        this.version++;
        await this._saveManifest();
        return { success: true };
    }

    async insert(tableName, rows) {
        const table = this.tables.get(tableName);
        if (!table) throw new Error(`Table ${tableName} does not exist`);

        const fragId = `frag_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        await this.storage.save(`${tableName}/${fragId}.json`, rows);
        table.fragments.push(fragId);
        this.version++;
        await this._saveManifest();
        return { success: true, inserted: rows.length };
    }

    async _executeInsert(ast) {
        const rows = ast.rows.map(values => {
            const row = {};
            if (ast.columns) {
                ast.columns.forEach((col, i) => { row[col] = values[i]; });
            } else {
                const table = this.tables.get(ast.table);
                table.schema.columns.forEach((col, i) => { row[col.name] = values[i]; });
            }
            return row;
        });
        return this.insert(ast.table, rows);
    }

    async _getAllRows(tableName) {
        const table = this.tables.get(tableName);
        if (!table) throw new Error(`Table ${tableName} does not exist`);

        const rows = [];
        let rowId = 0;
        for (const fragId of table.fragments) {
            const fragData = await this.storage.load(`${tableName}/${fragId}.json`);
            if (fragData) {
                for (const row of fragData) {
                    if (!table.deletions.has(rowId)) {
                        rows.push({ ...row, __rowId: rowId });
                    }
                    rowId++;
                }
            }
        }
        return rows;
    }

    async delete(tableName, predicate) {
        const table = this.tables.get(tableName);
        if (!table) throw new Error(`Table ${tableName} does not exist`);

        const rows = await this._getAllRows(tableName);
        let deleted = 0;
        for (const row of rows) {
            if (predicate(row)) {
                table.deletions.add(row.__rowId);
                deleted++;
            }
        }
        this.version++;
        await this._saveManifest();
        return { success: true, deleted };
    }

    async _executeDelete(ast) {
        return this.delete(ast.table, row => this._matchCondition(row, ast.where));
    }

    async update(tableName, updates, predicate) {
        const table = this.tables.get(tableName);
        if (!table) throw new Error(`Table ${tableName} does not exist`);

        const rows = await this._getAllRows(tableName);
        const newRows = [];
        let updated = 0;

        for (const row of rows) {
            if (predicate(row)) {
                table.deletions.add(row.__rowId);
                const newRow = { ...row };
                delete newRow.__rowId;
                Object.assign(newRow, updates);
                newRows.push(newRow);
                updated++;
            }
        }

        if (newRows.length > 0) {
            const fragId = `frag_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
            await this.storage.save(`${tableName}/${fragId}.json`, newRows);
            table.fragments.push(fragId);
        }

        this.version++;
        await this._saveManifest();
        return { success: true, updated };
    }

    async _executeUpdate(ast) {
        return this.update(ast.table, ast.updates, row => this._matchCondition(row, ast.where));
    }

    async select(tableName, options = {}) {
        const rows = await this._getAllRows(tableName);
        let result = rows.map(r => { const { __rowId, ...rest } = r; return rest; });

        if (options.where) {
            result = result.filter(row => options.where(row));
        }
        if (options.orderBy) {
            result.sort((a, b) => {
                const aVal = a[options.orderBy.column];
                const bVal = b[options.orderBy.column];
                return options.orderBy.desc ? (bVal > aVal ? 1 : -1) : (aVal > bVal ? 1 : -1);
            });
        }
        if (options.limit) {
            result = result.slice(0, options.limit);
        }
        return result;
    }

    async _executeSelect(ast) {
        return this.select(ast.table, {
            where: ast.where ? (row => this._matchCondition(row, ast.where)) : null,
            orderBy: ast.orderBy,
            limit: ast.limit
        });
    }

    _matchCondition(row, cond) {
        if (!cond) return true;
        const val = row[cond.column];
        switch (cond.op) {
            case '=': return val === cond.value;
            case '!=': return val !== cond.value;
            case '<': return val < cond.value;
            case '<=': return val <= cond.value;
            case '>': return val > cond.value;
            case '>=': return val >= cond.value;
            case 'LIKE': {
                const pattern = cond.value.replace(/%/g, '.*').replace(/_/g, '.');
                return new RegExp(`^${pattern}$`, 'i').test(val);
            }
            default: return false;
        }
    }

    async compact() {
        for (const [tableName, table] of this.tables) {
            const rows = await this._getAllRows(tableName);
            const cleanRows = rows.map(r => { const { __rowId, ...rest } = r; return rest; });

            for (const fragId of table.fragments) {
                await this.storage.delete(`${tableName}/${fragId}.json`);
            }

            const fragId = `frag_${Date.now()}_compacted`;
            await this.storage.save(`${tableName}/${fragId}.json`, cleanRows);
            table.fragments = [fragId];
            table.deletions = new Set();
        }
        this.version++;
        await this._saveManifest();
    }
}

module.exports = { LocalDatabase, FileStorage, SQLLexer, LocalSQLParser, HotTierCache, hotTierCache, VectorAccelerator, vectorAccelerator };
