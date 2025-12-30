# Phase 4: Official better-sqlite3 Test Suite Analysis

## Overview
This document analyzes the better-sqlite3 test suite (28 test files) to identify which tests we can run against our read-only Lance implementation.

## Test Suite Breakdown

### ✅ TESTABLE - Read Operations (Priority: HIGH)

These tests can be adapted for Lance with test fixture generation:

1. **21.statement.get.js** - ✅ HIGH PRIORITY
   - Tests: Statement.get() returns first row
   - Features: pluck(), expand(), raw(), parameter binding
   - Adaptation: Generate Lance fixture matching their test data

2. **22.statement.all.js** - ✅ HIGH PRIORITY
   - Tests: Statement.all() returns all rows
   - Features: pluck(), expand(), raw(), empty results, parameter binding
   - Adaptation: Generate Lance fixture matching their test data

3. **23.statement.iterate.js** - ✅ HIGH PRIORITY
   - Tests: Statement.iterate() iterator pattern
   - Features: for-of loops, lazy evaluation
   - Adaptation: Generate Lance fixture

4. **25.statement.columns.js** - ✅ MEDIUM PRIORITY
   - Tests: Statement.columns() metadata
   - Features: Column names, types
   - Adaptation: Should work with Lance schema

5. **13.database.prepare.js** - ✅ HIGH PRIORITY
   - Tests: Database.prepare() creating statements
   - Features: SQL parsing, statement lifecycle
   - Adaptation: SELECT queries only

6. **12.database.pragma.js** - ⚠️ PARTIAL
   - Tests: PRAGMA queries for metadata
   - Testable: PRAGMA table_info (schema queries)
   - Not testable: PRAGMA settings that modify SQLite behavior
   - Adaptation: Implement table_info for Lance schema

7. **11.database.close.js** - ✅ HIGH PRIORITY
   - Tests: Database.close() behavior
   - Features: Error when using closed database
   - Adaptation: Should work as-is

8. **10.database.open.js** - ⚠️ PARTIAL
   - Testable: Opening existing Lance files, readonly option
   - Not testable: Creating databases, :memory:, temporary databases
   - Adaptation: Only test opening existing files

9. **01.sqlite-error.js** - ✅ HIGH PRIORITY
   - Tests: SqliteError class and error codes
   - Features: Error messages, .code property
   - Adaptation: Should work with our SqliteError implementation

10. **24.statement.bind.js** - ⚠️ PARTIAL
    - Testable: Positional parameter binding (`?`)
    - Not yet testable: Named parameters (`:name`, `@name`, `$name`) - v0.2.0
    - Adaptation: Test positional params only

### ❌ NOT TESTABLE - Write Operations

These tests require write capabilities (Lance is read-only in v0.1.0):

11. **20.statement.run.js** - ❌ SKIP
    - Reason: INSERT, UPDATE, DELETE operations
    - Note: We have stub that returns {changes: 0} for SELECT

12. **14.database.exec.js** - ❌ SKIP
    - Reason: CREATE TABLE, INSERT, batch writes
    - Note: We have stub that ignores writes

13. **30.database.transaction.js** - ❌ SKIP
    - Reason: BEGIN/COMMIT/ROLLBACK
    - Note: Lance is read-only, no transactions

14. **31.database.checkpoint.js** - ❌ SKIP
    - Reason: WAL checkpoint operations

15. **36.database.backup.js** - ❌ SKIP
    - Reason: Database backup operations

16. **37.database.serialize.js** - ❌ SKIP
    - Reason: Database serialization

### ❌ NOT TESTABLE - Advanced Features

These tests require features not in v0.1.0 scope:

17. **32.database.function.js** - ❌ SKIP
    - Reason: User-defined functions (UDFs)
    - Future: v0.2.0 could add this

18. **33.database.aggregate.js** - ❌ SKIP
    - Reason: User-defined aggregate functions
    - Future: v0.2.0 could add this

19. **34.database.table.js** - ❌ SKIP
    - Reason: Virtual table functions
    - Future: Not planned

20. **35.database.load-extension.js** - ❌ SKIP
    - Reason: SQLite extension loading
    - Future: Not applicable to Lance

21. **40.bigints.js** - ⚠️ PARTIAL
    - Testable: Reading int64 as JavaScript Number (lossy for >53 bits)
    - Not testable: BigInt support without implementation
    - Future: v0.2.0 should add safeIntegers() / BigInt

22. **41.at-exit.js** - ❌ SKIP
    - Reason: Process exit handlers
    - Future: Not priority

23. **42.integrity.js** - ❌ SKIP
    - Reason: Database integrity checks (SQLite-specific)
    - Future: Not applicable to Lance

24. **43.verbose.js** - ❌ SKIP
    - Reason: Verbose logging mode
    - Future: Could add debug logging

25. **44.worker-threads.js** - ❌ SKIP
    - Reason: Worker thread safety
    - Future: v0.2.0 could test this

26. **45.unsafe-mode.js** - ❌ SKIP
    - Reason: Unsafe mode for performance
    - Future: Not applicable (Lance is always safe)

27. **50.misc.js** - ⚠️ UNKNOWN
    - Need to examine contents
    - Likely mixed bag of features

28. **00.setup.js** - ✅ UTILITY
    - Test framework setup
    - We'll need similar setup for our tests

## Summary Statistics

**Total Test Files:** 28

**Testable Categories:**
- ✅ Full support: 7 files (25%)
- ⚠️ Partial support: 5 files (18%)
- ❌ No support: 16 files (57%)

**Estimated Test Count:**
- Each file has ~5-15 individual test cases
- Estimated total: ~300-400 tests
- Estimated testable: ~80-120 tests (30%)
- **Target: Pass 80%+ of testable tests** = 64-96 tests passing

## Implementation Strategy

### Step 1: Generate Test Fixtures

Create Lance files matching better-sqlite3 test data:

```python
# fixtures/generate_better_sqlite3_fixtures.py
import pyarrow as pa
import lance

# Fixture 1: entries table (matches 21.statement.get.js and 22.statement.all.js)
# Columns: a TEXT, b INTEGER, c REAL, d BLOB, e TEXT
entries_data = {
    'a': ['foo'] * 10,
    'b': list(range(1, 11)),  # 1-10
    'c': [3.14] * 10,
    'd': [b'\xdd\xdd\xdd\xdd'] * 10,  # BLOB
    'e': [None] * 10,
}

schema = pa.schema([
    ('a', pa.string()),
    ('b', pa.int64()),
    ('c', pa.float64()),
    ('d', pa.binary()),
    ('e', pa.string()),
])

table = pa.Table.from_pydict(entries_data, schema=schema)
lance.write_lance('tests/fixtures/entries.lance', table)

print(f"Created entries.lance with {len(table)} rows")
```

### Step 2: Adapt Test Runner

Create test adapter that:
1. Replaces `new Database()` calls with Lance file paths
2. Skips CREATE/INSERT in beforeEach
3. Uses pre-generated fixtures instead

```javascript
// test/better-sqlite3-adapter.js
const Database = require('../src/index.js');
const path = require('path');

// Map table names to Lance files
const fixtures = {
    'entries': path.join(__dirname, '../../tests/fixtures/entries.lance/data/XXX.lance'),
};

class TestAdapter {
    static createDatabase(tableName = 'entries') {
        if (!fixtures[tableName]) {
            throw new Error(`No fixture for table: ${tableName}`);
        }
        return new Database(fixtures[tableName]);
    }

    static skipWrite(fn) {
        // Wrapper that catches write operations and no-ops
        try {
            fn();
        } catch (err) {
            if (err.message.includes('Write operations not supported')) {
                return; // Expected, skip
            }
            throw err;
        }
    }
}

module.exports = TestAdapter;
```

### Step 3: Run Adapted Tests

```bash
cd packages/node

# Install Mocha and Chai
npm install --save-dev mocha chai

# Copy and adapt testable tests
mkdir -p test/better-sqlite3-adapted
cp /tmp/better-sqlite3/test/21.statement.get.js test/better-sqlite3-adapted/
cp /tmp/better-sqlite3/test/22.statement.all.js test/better-sqlite3-adapted/
# ... etc

# Modify tests to use our adapter
# (Replace beforeEach database creation with fixture loading)

# Run tests
DYLD_LIBRARY_PATH=../../zig-out/lib npx mocha test/better-sqlite3-adapted/**/*.js
```

### Step 4: Measure Pass Rate

Track results:
- Total tests run: X
- Tests passed: Y
- Tests failed: Z
- Pass rate: Y/X%

Target: >80% pass rate for read-only operations

## Expected Gaps (v0.1.0 Limitations)

Based on test analysis, we expect failures in:

1. **Named parameter binding** (`:name`, `@name`, `$name`)
   - Test files affected: 22, 21, 24
   - Fix: Implement in v0.2.0

2. **BLOB/Buffer handling**
   - Test files affected: 21, 22
   - Fix: Add Buffer support to Zig C API

3. **BigInt support**
   - Test files affected: 40
   - Fix: Implement safeIntegers() in v0.2.0

4. **PRAGMA queries**
   - Test files affected: 12
   - Fix: Implement lance_pragma_table_info in C API

5. **Expand mode with table namespacing**
   - Test files affected: 21, 22
   - Fix: Track table names in SQL executor

## Success Metrics

**Must Have:**
- [ ] Pass >80% of read-operation tests (64+ tests)
- [ ] All Statement.all() tests pass
- [ ] All Statement.get() tests pass
- [ ] All Statement.iterate() tests pass
- [ ] Error handling tests pass

**Nice to Have:**
- [ ] Pass >90% of read-operation tests
- [ ] Parameter binding tests pass (positional only)
- [ ] PRAGMA table_info tests pass
- [ ] Column metadata tests pass

## Next Steps

1. ✅ Complete this analysis
2. ⏳ Generate Lance test fixtures
3. ⏳ Install Mocha/Chai test framework
4. ⏳ Copy and adapt high-priority tests (21, 22, 23)
5. ⏳ Run tests and measure pass rate
6. ⏳ Fix critical failures
7. ⏳ Document compatibility matrix
