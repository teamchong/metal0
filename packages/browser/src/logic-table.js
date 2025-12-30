/**
 * LogicTable - Hybrid JavaScript logic + Lance data queries.
 *
 * Enables DataFrame-like queries with JavaScript methods pushed to the data layer.
 *
 * @example
 * // Define a logic table
 * const FraudDetector = logicTable({
 *     tables: {
 *         orders: Table('orders.lance', { hotTier: '2GB' }),
 *         customers: Table('customers.lance')
 *     },
 *     methods: {
 *         riskScore() {
 *             return this.orders.amount * this.customers.riskFactor;
 *         },
 *         category() {
 *             return this.riskScore() > 0.8 ? 'high_risk' : 'normal';
 *         }
 *     }
 * });
 *
 * // Query with DataFrame API
 * const results = await FraudDetector
 *     .filter(t => t.riskScore() > 0.5)
 *     .select('id', 'amount', t => t.riskScore())
 *     .orderBy(t => t.riskScore(), { desc: true })
 *     .limit(100)
 *     .toArrow();
 *
 * // Or bind different data at runtime
 * const results = await FraudDetector
 *     .bind({ orders: 'test_orders.lance' })
 *     .filter(t => t.riskScore() > 0)
 *     .toArrow();
 */

import { LanceDataset } from './lanceql.js';

/**
 * Table source declaration.
 *
 * @param {string} path - Path to Lance dataset
 * @param {Object} options - Options
 * @param {string} [options.hotTier] - Hot tier cache size (e.g., '4GB')
 * @param {string[]} [options.columns] - Columns to load (projection pushdown)
 * @returns {TableSpec}
 */
export function Table(path, options = {}) {
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
export class LogicTableQuery {
    /**
     * @param {LogicTableDef} logicDef - Logic table definition
     * @param {Object} bindings - Table path overrides
     */
    constructor(logicDef, bindings = {}) {
        this._logicDef = logicDef;
        this._bindings = bindings;
        this._filters = [];
        this._projections = [];
        this._orderSpecs = [];
        this._limitVal = null;
        this._offsetVal = null;
        this._joins = [];
        this._groupBy = null;
    }

    /**
     * Bind or override table paths.
     * @param {Object} tables - Mapping of table name to path
     * @returns {LogicTableQuery}
     */
    bind(tables) {
        const query = this._clone();
        Object.assign(query._bindings, tables);
        return query;
    }

    /**
     * Filter rows using a predicate function.
     * @param {Function} predicate - Function that takes logic instance, returns bool
     * @returns {LogicTableQuery}
     */
    filter(predicate) {
        const query = this._clone();
        query._filters.push(predicate);
        return query;
    }

    /**
     * Select columns or computed values.
     * @param {...(string|Function|[Function, string])} columns - Columns to select
     * @returns {LogicTableQuery}
     */
    select(...columns) {
        const query = this._clone();
        query._projections = columns;
        return query;
    }

    /**
     * Order results.
     * @param {string|Function} column - Column or lambda
     * @param {Object} options - Options
     * @param {boolean} [options.desc=false] - Descending order
     * @returns {LogicTableQuery}
     */
    orderBy(column, options = {}) {
        const query = this._clone();
        query._orderSpecs.push({ column, desc: options.desc || false });
        return query;
    }

    /**
     * Limit number of results.
     * @param {number} n - Maximum rows
     * @returns {LogicTableQuery}
     */
    limit(n) {
        const query = this._clone();
        query._limitVal = n;
        return query;
    }

    /**
     * Skip first n results.
     * @param {number} n - Rows to skip
     * @returns {LogicTableQuery}
     */
    offset(n) {
        const query = this._clone();
        query._offsetVal = n;
        return query;
    }

    /**
     * Join with another table.
     * @param {string|LogicTableQuery} other - Table path or query
     * @param {Object} options - Join options
     * @returns {LogicTableQuery}
     */
    join(other, options = {}) {
        const query = this._clone();
        query._joins.push({
            other,
            on: options.on || null,
            leftOn: options.leftOn || null,
            rightOn: options.rightOn || null,
            how: options.how || 'inner'
        });
        return query;
    }

    /**
     * Group by and aggregate.
     * @param {...(string|Function)} keys - Grouping keys
     * @returns {LogicTableQueryGrouped}
     */
    groupBy(...keys) {
        const query = this._clone();
        query._groupBy = { keys, aggs: {} };
        return new LogicTableQueryGrouped(query);
    }

    _clone() {
        const query = new LogicTableQuery(this._logicDef, { ...this._bindings });
        query._filters = [...this._filters];
        query._projections = [...this._projections];
        query._orderSpecs = [...this._orderSpecs];
        query._limitVal = this._limitVal;
        query._offsetVal = this._offsetVal;
        query._joins = [...this._joins];
        query._groupBy = this._groupBy;
        return query;
    }

    _resolvePath(tableName, tableSpec) {
        return this._bindings[tableName] || tableSpec.path;
    }

    async _loadTable(path) {
        // Use LanceDataset to load
        const dataset = await LanceDataset.open(path);
        return dataset;
    }

    /**
     * Execute query and return results as array of objects.
     * @returns {Promise<Object[]>}
     */
    async execute() {
        const { tables, methods } = this._logicDef;

        // Load all tables
        const loadedTables = {};
        const tableData = {};

        for (const [name, spec] of Object.entries(tables)) {
            const path = this._resolvePath(name, spec);
            const dataset = await this._loadTable(path);
            loadedTables[name] = dataset;

            // Get all rows (for now - should be optimized with pushdown)
            const rows = await dataset.query('SELECT * FROM data');
            tableData[name] = rows;
        }

        // Get primary table
        const primaryName = Object.keys(tables)[0];
        const primaryData = tableData[primaryName];

        // Create logic instance for each row evaluation
        const results = [];

        for (let i = 0; i < primaryData.length; i++) {
            // Create logic instance with current row bound
            const logicInstance = {};

            // Bind table accessors
            for (const [name, data] of Object.entries(tableData)) {
                const row = data[i] || data[0]; // Fallback for mismatched sizes
                logicInstance[name] = new Proxy(row, {
                    get(target, prop) {
                        if (prop in target) return target[prop];
                        throw new Error(`Column '${prop}' not found in ${name}`);
                    }
                });
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
                } catch (e) {
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
                        // Column name
                        for (const [tableName, data] of Object.entries(tableData)) {
                            if (proj in (data[i] || {})) {
                                row[proj] = data[i][proj];
                                break;
                            }
                        }
                    } else if (Array.isArray(proj)) {
                        // [lambda, alias]
                        const [fn, alias] = proj;
                        row[alias] = fn(logicInstance);
                    } else if (typeof proj === 'function') {
                        // Lambda without alias
                        const value = proj(logicInstance);
                        row[`col_${Object.keys(row).length}`] = value;
                    }
                }
            } else {
                // Select all from primary table
                row = { ...primaryData[i] };
            }

            results.push(row);
        }

        // Apply ordering (in memory for now)
        if (this._orderSpecs.length > 0) {
            results.sort((a, b) => {
                for (const spec of this._orderSpecs) {
                    let aVal, bVal;
                    if (typeof spec.column === 'string') {
                        aVal = a[spec.column];
                        bVal = b[spec.column];
                    } else {
                        // Need to re-evaluate for sorting - simplified for now
                        aVal = a[Object.keys(a)[0]];
                        bVal = b[Object.keys(b)[0]];
                    }
                    const cmp = aVal < bVal ? -1 : aVal > bVal ? 1 : 0;
                    if (cmp !== 0) return spec.desc ? -cmp : cmp;
                }
                return 0;
            });
        }

        // Apply offset
        let finalResults = results;
        if (this._offsetVal) {
            finalResults = finalResults.slice(this._offsetVal);
        }

        // Apply limit
        if (this._limitVal) {
            finalResults = finalResults.slice(0, this._limitVal);
        }

        return finalResults;
    }

    /**
     * Execute query and return as Arrow table.
     * @returns {Promise<Object>} Arrow-like table object
     */
    async toArrow() {
        const results = await this.execute();

        // Convert to columnar format
        if (results.length === 0) {
            return { columns: {}, length: 0 };
        }

        const columns = {};
        const keys = Object.keys(results[0]);
        for (const key of keys) {
            columns[key] = results.map(row => row[key]);
        }

        return {
            columns,
            length: results.length,
            toArray: () => results,
            getColumn: (name) => columns[name] || null,
            schema: keys.map(k => ({ name: k, type: typeof (results[0][k]) }))
        };
    }

    /**
     * Return query plan as string.
     * @returns {string}
     */
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

        if (this._offsetVal) {
            lines.push(`Offset: ${this._offsetVal}`);
        }

        return lines.join('\n');
    }
}

/**
 * Grouped query for aggregations.
 */
class LogicTableQueryGrouped {
    constructor(query) {
        this._query = query;
    }

    /**
     * Add aggregation.
     * @param {Object} aggs - Aggregation functions {name: fn}
     * @returns {LogicTableQuery}
     */
    agg(aggs) {
        const query = this._query._clone();
        query._groupBy.aggs = aggs;
        return query;
    }
}

/**
 * Create a LogicTable definition.
 *
 * @param {Object} def - Definition
 * @param {string} [def.name] - Table name
 * @param {Object} def.tables - Table declarations
 * @param {Object} [def.methods] - Method definitions
 * @returns {LogicTableDef}
 */
export function logicTable(def) {
    const logicDef = {
        name: def.name || 'LogicTable',
        tables: def.tables || {},
        methods: def.methods || {}
    };

    // Return object with query methods
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

        join(other, options) {
            return new LogicTableQuery(logicDef).join(other, options);
        },

        groupBy(...keys) {
            return new LogicTableQuery(logicDef).groupBy(...keys);
        },

        query() {
            return new LogicTableQuery(logicDef);
        },

        async toArrow() {
            return new LogicTableQuery(logicDef).toArrow();
        },

        async execute() {
            return new LogicTableQuery(logicDef).execute();
        }
    };
}

/**
 * Load a LogicTable from a JavaScript module.
 *
 * @param {string} path - Path to JS module
 * @returns {Promise<LogicTableDef>}
 */
export async function loadLogicTable(path) {
    const module = await import(path);
    if (module.default && module.default._def) {
        return module.default;
    }
    if (module.Logic && module.Logic._def) {
        return module.Logic;
    }
    throw new Error(`No LogicTable found in ${path}`);
}

export default { Table, logicTable, LogicTableQuery, loadLogicTable };
