# @lanceql/node

SQLite-compatible API for reading Lance columnar files. Drop-in replacement for `better-sqlite3` for read-only analytics workloads.

## Features

- **SQLite-compatible API**: Same interface as `better-sqlite3` - just change your import
- **Read Lance files**: Query `.lance` columnar files using SQL
- **High performance**: Native Zig-powered implementation with zero-copy string handling
- **Cross-platform**: macOS, Linux, and Windows support

## Installation

```bash
npm install @lanceql/node
```

## Quick Start

```javascript
const Database = require('@lanceql/node');

// Open a Lance file (or dataset directory)
const db = new Database('path/to/data.lance');

// Query using SQL
const rows = db.prepare('SELECT * FROM table WHERE value > 100').all();
console.log(rows);

// Get a single row
const row = db.prepare('SELECT * FROM table LIMIT 1').get();

// Clean up
db.close();
```

## API Reference

### Database

#### `new Database(path, [options])`

Opens a Lance file or dataset directory.

- `path` - Path to a `.lance` file or Lance dataset directory
- `options.readonly` - Always `true` for Lance files (read-only)

```javascript
const db = new Database('/path/to/dataset.lance');
```

#### `db.prepare(sql)`

Creates a prepared statement.

```javascript
const stmt = db.prepare('SELECT * FROM table WHERE id = ?');
```

#### `db.close()`

Closes the database connection and releases resources.

#### Properties

- `db.open` - `true` if database is open
- `db.name` - Path to the database file
- `db.readonly` - Always `true` for Lance files
- `db.inTransaction` - Always `false` (no transactions)

### Statement

#### `stmt.all([...params])`

Returns all rows as an array of objects.

```javascript
const rows = stmt.all();
// [{ id: 1, name: 'Alice' }, { id: 2, name: 'Bob' }]
```

#### `stmt.get([...params])`

Returns the first row, or `undefined` if no results.

```javascript
const row = stmt.get();
// { id: 1, name: 'Alice' }
```

#### `stmt.run([...params])`

Executes the statement. Returns `{ changes: 0, lastInsertRowid: 0 }` (read-only).

## Supported SQL

### SELECT

```sql
SELECT * FROM table
SELECT column1, column2 FROM table
SELECT * FROM table WHERE condition
SELECT * FROM table ORDER BY column ASC|DESC
SELECT * FROM table LIMIT n
```

### WHERE Operators

- Comparison: `=`, `!=`, `<`, `>`, `<=`, `>=`
- Logical: `AND`, `OR`
- Literals: integers, floats, strings

## Data Types

| Lance Type | JavaScript Type |
|------------|-----------------|
| int64 | Number |
| float64 | Number |
| utf8/string | String |

## Limitations

This is a **read-only** implementation optimized for analytics:

- No `INSERT`, `UPDATE`, or `DELETE`
- No transactions (always auto-commit)
- No user-defined functions
- No virtual tables
- No extensions
- Table name in SQL is ignored (Lance files are single-table)

## Migration from better-sqlite3

Replace your import:

```javascript
// Before
const Database = require('better-sqlite3');

// After
const Database = require('@lanceql/node');
```

Most read operations work identically. Write operations will silently succeed but have no effect.

## Environment Variables

- `LANCEQL_LIB_PATH` - Custom path to the native library

## Building from Source

Requires [Zig](https://ziglang.org/) 0.13.0+ and Node.js 18+.

```bash
# Build Zig library
zig build lib-nodejs

# Build Node.js addon
cd packages/node
npm install
npm run build
```

## License

MIT
