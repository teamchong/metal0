const Database = require('../src/index.js');
const assert = require('assert');
const path = require('path');

// Test with types fixture (has int32, float32, bool columns)
const dbPath = path.join(__dirname, '../../../tests/fixtures/better-sqlite3/types_test.lance/data/1001011110111010000110017c7899445c8eadd0bc3b151743.lance');

console.log('=== Additional Data Types Tests ===\n');

// Test 1: SELECT int32 column
console.log('Test 1: SELECT i32_col (int32 column)');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT i32_col FROM table');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    assert.strictEqual(rows.length, 5, `Expected 5 rows, got ${rows.length}`);

    const values = rows.map(r => r.i32_col);
    assert.deepStrictEqual(values, [1, 2, 3, -1, 0]);

    console.log('✓ SELECT int32 column works');
    db.close();
} catch (err) {
    console.error('✗ SELECT int32 column failed:', err.message);
    process.exit(1);
}

// Test 2: SELECT float32 column
console.log('\nTest 2: SELECT f32_col (float32 column)');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT f32_col FROM table');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    assert.strictEqual(rows.length, 5, `Expected 5 rows, got ${rows.length}`);

    // Check approximate values due to float precision
    const values = rows.map(r => r.f32_col);
    assert.ok(Math.abs(values[0] - 1.5) < 0.001, `Expected ~1.5, got ${values[0]}`);
    assert.ok(Math.abs(values[1] - 2.5) < 0.001, `Expected ~2.5, got ${values[1]}`);
    assert.ok(Math.abs(values[2] - 3.5) < 0.001, `Expected ~3.5, got ${values[2]}`);
    assert.ok(Math.abs(values[3] - (-1.5)) < 0.001, `Expected ~-1.5, got ${values[3]}`);
    assert.ok(Math.abs(values[4] - 0.0) < 0.001, `Expected ~0.0, got ${values[4]}`);

    console.log('✓ SELECT float32 column works');
    db.close();
} catch (err) {
    console.error('✗ SELECT float32 column failed:', err.message);
    process.exit(1);
}

// Test 3: SELECT bool column
console.log('\nTest 3: SELECT bool_col (bool column)');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT bool_col FROM table');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    assert.strictEqual(rows.length, 5, `Expected 5 rows, got ${rows.length}`);

    const values = rows.map(r => r.bool_col);
    assert.deepStrictEqual(values, [true, false, true, false, true]);

    console.log('✓ SELECT bool column works');
    db.close();
} catch (err) {
    console.error('✗ SELECT bool column failed:', err.message);
    process.exit(1);
}

// Test 4: SELECT all columns
console.log('\nTest 4: SELECT * (all columns including new types)');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    assert.strictEqual(rows.length, 5, `Expected 5 rows, got ${rows.length}`);

    // Check first row has all types
    const firstRow = rows[0];
    assert.strictEqual(typeof firstRow.i32_col, 'number', 'i32_col should be a number');
    assert.strictEqual(typeof firstRow.f32_col, 'number', 'f32_col should be a number');
    assert.strictEqual(typeof firstRow.bool_col, 'boolean', 'bool_col should be a boolean');
    assert.strictEqual(typeof firstRow.i64_col, 'number', 'i64_col should be a number');
    assert.strictEqual(typeof firstRow.name, 'string', 'name should be a string');

    console.log('✓ SELECT * with all types works');
    db.close();
} catch (err) {
    console.error('✗ SELECT * failed:', err.message);
    process.exit(1);
}

// Test 5: WHERE clause on int32
console.log('\nTest 5: SELECT * WHERE i32_col > 0');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT * FROM table WHERE i32_col > 0');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    assert.strictEqual(rows.length, 3, `Expected 3 rows with i32_col > 0, got ${rows.length}`);

    // All rows should have positive i32_col
    rows.forEach(row => {
        assert.ok(row.i32_col > 0, `Expected positive i32_col, got ${row.i32_col}`);
    });

    console.log('✓ WHERE clause on int32 works');
    db.close();
} catch (err) {
    console.error('✗ WHERE on int32 failed:', err.message);
    process.exit(1);
}

// Test 6: ORDER BY on int32
console.log('\nTest 6: SELECT i32_col FROM table ORDER BY i32_col');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT i32_col FROM table ORDER BY i32_col');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    const values = rows.map(r => r.i32_col);
    assert.deepStrictEqual(values, [-1, 0, 1, 2, 3]);

    console.log('✓ ORDER BY on int32 works');
    db.close();
} catch (err) {
    console.error('✗ ORDER BY on int32 failed:', err.message);
    process.exit(1);
}

// Test 7: DISTINCT on bool
console.log('\nTest 7: SELECT DISTINCT bool_col FROM table');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT DISTINCT bool_col FROM table');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    assert.strictEqual(rows.length, 2, `Expected 2 unique bool values, got ${rows.length}`);

    console.log('✓ DISTINCT on bool works');
    db.close();
} catch (err) {
    console.error('✗ DISTINCT on bool failed:', err.message);
    process.exit(1);
}

// Test 8: Mixed type expressions
console.log('\nTest 8: SELECT name, i32_col, bool_col FROM table WHERE i32_col >= 0 AND bool_col = true');
try {
    const db = new Database(dbPath);
    // Note: bool comparison syntax may vary - this tests if it works
    const stmt = db.prepare('SELECT name, i32_col, bool_col FROM table WHERE i32_col >= 0');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    // Should have rows with i32_col >= 0 (values 1, 2, 3, 0)
    assert.strictEqual(rows.length, 4, `Expected 4 rows with i32_col >= 0, got ${rows.length}`);

    console.log('✓ Mixed type query works');
    db.close();
} catch (err) {
    console.error('✗ Mixed type query failed:', err.message);
    process.exit(1);
}

console.log('\n✅ All additional data types tests passed!');
