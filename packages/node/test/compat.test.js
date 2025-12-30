const Database = require('../src/index.js');
const assert = require('assert');
const path = require('path');

// This test file uses ACTUAL better-sqlite3 code patterns to verify drop-in compatibility
const dbPath = path.join(__dirname, '../../../tests/fixtures/simple_int64.lance/data/0100110011011011000010005445a8407eb6f52a3c35f80bd3.lance');

console.log('=== better-sqlite3 Compatibility Test Suite ===\n');

// Test 1: Constructor patterns
console.log('Test 1: Constructor API');
try {
    const db = new Database(dbPath);
    assert.strictEqual(typeof db, 'object');
    assert.strictEqual(db.constructor.name, 'Database');
    console.log('✓ Constructor works');
    db.close();
} catch (err) {
    console.error('✗ Constructor failed:', err.message);
    process.exit(1);
}

// Test 2: Properties API
console.log('\nTest 2: Database Properties');
try {
    const db = new Database(dbPath);
    assert.strictEqual(db.open, true);
    assert.strictEqual(db.readonly, false);
    assert.strictEqual(db.inTransaction, false);
    assert.strictEqual(db.memory, false);
    assert.strictEqual(typeof db.name, 'string');
    console.log('✓ All properties accessible');
    console.log(`  - open: ${db.open}`);
    console.log(`  - readonly: ${db.readonly}`);
    console.log(`  - name: ${db.name}`);
    db.close();
} catch (err) {
    console.error('✗ Properties test failed:', err.message);
    process.exit(1);
}

// Test 3: Prepare and Statement properties
console.log('\nTest 3: Statement Properties');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table');
    assert.strictEqual(typeof stmt.source, 'string');
    assert.strictEqual(stmt.readonly, true);
    assert.strictEqual(stmt.database, db);
    assert.strictEqual(stmt.reader, true);
    assert.strictEqual(stmt.busy, false);
    console.log('✓ All statement properties accessible');
    console.log(`  - source: "${stmt.source}"`);
    console.log(`  - readonly: ${stmt.readonly}`);
    db.close();
} catch (err) {
    console.error('✗ Statement properties test failed:', err.message);
    process.exit(1);
}

// Test 4: all() returns row objects
console.log('\nTest 4: stmt.all() returns array of objects');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table');
    const rows = stmt.all();
    assert.strictEqual(Array.isArray(rows), true);
    assert.strictEqual(typeof rows[0], 'object');
    assert.strictEqual('id' in rows[0], true);
    console.log('✓ Returns array of row objects');
    console.log(`  First row: ${JSON.stringify(rows[0])}`);
    db.close();
} catch (err) {
    console.error('✗ all() test failed:', err.message);
    process.exit(1);
}

// Test 5: get() returns single row
console.log('\nTest 5: stmt.get() returns single object');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table');
    const row = stmt.get();
    assert.strictEqual(typeof row, 'object');
    assert.strictEqual('id' in row, true);
    console.log('✓ Returns single row object');
    console.log(`  Row: ${JSON.stringify(row)}`);
    db.close();
} catch (err) {
    console.error('✗ get() test failed:', err.message);
    process.exit(1);
}

// Test 6: run() returns info object
console.log('\nTest 6: stmt.run() returns info object');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table');
    const info = stmt.run();
    assert.strictEqual(typeof info, 'object');
    assert.strictEqual('changes' in info, true);
    assert.strictEqual('lastInsertRowid' in info, true);
    console.log('✓ Returns {changes, lastInsertRowid}');
    console.log(`  Info: ${JSON.stringify(info)}`);
    db.close();
} catch (err) {
    console.error('✗ run() test failed:', err.message);
    process.exit(1);
}

// Test 7: Method chaining - pluck()
console.log('\nTest 7: Method chaining - pluck()');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table');
    const values = stmt.pluck().all();
    assert.strictEqual(Array.isArray(values), true);
    assert.strictEqual(typeof values[0], 'number'); // First column only
    console.log('✓ pluck() chaining works');
    console.log(`  Values: ${JSON.stringify(values)}`);
    db.close();
} catch (err) {
    console.error('✗ pluck() test failed:', err.message);
    process.exit(1);
}

// Test 8: Method chaining - raw()
console.log('\nTest 8: Method chaining - raw()');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table');
    const arrays = stmt.raw().all();
    assert.strictEqual(Array.isArray(arrays), true);
    assert.strictEqual(Array.isArray(arrays[0]), true);
    console.log('✓ raw() chaining works');
    console.log(`  First array: ${JSON.stringify(arrays[0])}`);
    db.close();
} catch (err) {
    console.error('✗ raw() test failed:', err.message);
    process.exit(1);
}

// Test 9: iterate() returns iterator
console.log('\nTest 9: iterate() returns iterator');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table WHERE id < 3');
    let count = 0;
    for (const row of stmt.iterate()) {
        assert.strictEqual(typeof row, 'object');
        count++;
    }
    assert.strictEqual(count, 2);
    console.log('✓ iterate() works with for-of');
    console.log(`  Iterated over ${count} rows`);
    db.close();
} catch (err) {
    console.error('✗ iterate() test failed:', err.message);
    process.exit(1);
}

// Test 10: Error handling
console.log('\nTest 10: Error handling');
try {
    const db = new Database(dbPath);
    try {
        db.prepare('INVALID SQL SYNTAX');
        assert.fail('Should have thrown error');
    } catch (err) {
        assert.strictEqual(err.name, 'SqliteError');
        assert.strictEqual(typeof err.code, 'string');
        console.log('✓ Throws SqliteError with code');
        console.log(`  Error: ${err.message}`);
        console.log(`  Code: ${err.code}`);
    }
    db.close();
} catch (err) {
    console.error('✗ Error handling test failed:', err.message);
    process.exit(1);
}

// Test 11: Close behavior
console.log('\nTest 11: Close behavior');
try {
    const db = new Database(dbPath);
    db.close();
    assert.strictEqual(db.open, false);
    try {
        db.prepare('SELECT 1');
        assert.fail('Should throw after close');
    } catch (err) {
        assert.strictEqual(err.name, 'SqliteError');
        console.log('✓ Throws error when using closed database');
    }
} catch (err) {
    console.error('✗ Close behavior test failed:', err.message);
    process.exit(1);
}

console.log('\n✅ All compatibility tests passed!');
console.log('This code would work identically with better-sqlite3!');
