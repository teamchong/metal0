const Database = require('../src/index.js');
const assert = require('assert');
const path = require('path');

// Test with existing fixture
const dbPath = path.join(__dirname, '../../../tests/fixtures/simple_int64.lance/data/0100110011011011000010005445a8407eb6f52a3c35f80bd3.lance');

console.log('=== Basic Functionality Tests ===\n');

// Test 1: Open database
console.log('Test 1: Open database');
try {
    const db = new Database(dbPath);
    assert.strictEqual(typeof db, 'object');
    console.log('✓ Database opened successfully');
    db.close();
} catch (err) {
    console.error('✗ Failed to open database:', err.message);
    process.exit(1);
}

// Test 2: SELECT *
console.log('\nTest 2: SELECT *');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);
    assert.strictEqual(rows.length, 5);
    assert.strictEqual(rows[0].id, 1);
    assert.strictEqual(rows[4].id, 5);
    console.log('✓ SELECT * works');
    db.close();
} catch (err) {
    console.error('✗ SELECT * failed:', err.message);
    process.exit(1);
}

// Test 3: SELECT with WHERE
console.log('\nTest 3: SELECT with WHERE');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table WHERE id > 2');
    const rows = stmt.all();
    console.log(`Filtered rows: ${JSON.stringify(rows)}`);
    assert.strictEqual(rows.length, 3);
    assert.strictEqual(rows[0].id, 3);
    console.log('✓ WHERE clause works');
    db.close();
} catch (err) {
    console.error('✗ WHERE clause failed:', err.message);
    process.exit(1);
}

// Test 4: Statement.get()
console.log('\nTest 4: Statement.get()');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table WHERE id = 3');
    const row = stmt.get();
    console.log(`Single row: ${JSON.stringify(row)}`);
    assert.strictEqual(row.id, 3);
    console.log('✓ get() works');
    db.close();
} catch (err) {
    console.error('✗ get() failed:', err.message);
    process.exit(1);
}

// Test 5: Close database
console.log('\nTest 5: Close database');
try {
    const db = new Database(dbPath);
    db.close();
    assert.strictEqual(db.open, false);
    console.log('✓ Database closed successfully');
} catch (err) {
    console.error('✗ Close failed:', err.message);
    process.exit(1);
}

console.log('\n✅ All basic tests passed!');
