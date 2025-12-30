const Database = require('../src/index.js');
const assert = require('assert');
const path = require('path');

// Test with distinct fixture (has duplicate values)
const dbPath = path.join(__dirname, '../../../tests/fixtures/better-sqlite3/distinct_test.lance/data/1011100101110011011000001a2ed149c5895af73c13059290.lance');

console.log('=== DISTINCT Tests ===\n');

// Test 1: SELECT DISTINCT single column (string)
console.log('Test 1: SELECT DISTINCT category (string column with duplicates)');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT DISTINCT category FROM table');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    // Original data: ['A', 'B', 'A', 'C', 'B', 'A', 'C', 'A']
    // Expected unique: 3 values (A, B, C)
    assert.strictEqual(rows.length, 3, `Expected 3 unique categories, got ${rows.length}`);

    // Check all unique values are present
    const categories = rows.map(r => r.category).sort();
    assert.deepStrictEqual(categories, ['A', 'B', 'C']);

    console.log('✓ SELECT DISTINCT single string column works');
    db.close();
} catch (err) {
    console.error('✗ SELECT DISTINCT single column failed:', err.message);
    process.exit(1);
}

// Test 2: SELECT DISTINCT single column (integer)
console.log('\nTest 2: SELECT DISTINCT value (integer column with duplicates)');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT DISTINCT value FROM table');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    // Original data: [1, 2, 1, 3, 2, 1, 3, 1]
    // Expected unique: 3 values (1, 2, 3)
    assert.strictEqual(rows.length, 3, `Expected 3 unique values, got ${rows.length}`);

    // Check all unique values are present
    const values = rows.map(r => r.value).sort((a, b) => a - b);
    assert.deepStrictEqual(values, [1, 2, 3]);

    console.log('✓ SELECT DISTINCT single integer column works');
    db.close();
} catch (err) {
    console.error('✗ SELECT DISTINCT integer column failed:', err.message);
    process.exit(1);
}

// Test 3: SELECT DISTINCT multiple columns
console.log('\nTest 3: SELECT DISTINCT category, value (multiple columns)');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT DISTINCT category, value FROM table');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    // Original data combinations:
    // (A,1), (B,2), (A,1), (C,3), (B,2), (A,1), (C,3), (A,1)
    // Unique combinations: (A,1), (B,2), (C,3) = 3 unique
    assert.strictEqual(rows.length, 3, `Expected 3 unique combinations, got ${rows.length}`);

    console.log('✓ SELECT DISTINCT multiple columns works');
    db.close();
} catch (err) {
    console.error('✗ SELECT DISTINCT multiple columns failed:', err.message);
    process.exit(1);
}

// Test 4: SELECT DISTINCT with WHERE clause
console.log('\nTest 4: SELECT DISTINCT category FROM table WHERE value > 1');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT DISTINCT category FROM table WHERE value > 1');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    // Filtered data: (B,2), (C,3), (B,2), (C,3)
    // Unique categories after filter: B, C = 2 unique
    assert.strictEqual(rows.length, 2, `Expected 2 unique categories, got ${rows.length}`);

    const categories = rows.map(r => r.category).sort();
    assert.deepStrictEqual(categories, ['B', 'C']);

    console.log('✓ SELECT DISTINCT with WHERE works');
    db.close();
} catch (err) {
    console.error('✗ SELECT DISTINCT with WHERE failed:', err.message);
    process.exit(1);
}

// Test 5: SELECT DISTINCT with ORDER BY
console.log('\nTest 5: SELECT DISTINCT category FROM table ORDER BY category DESC');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT DISTINCT category FROM table ORDER BY category DESC');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    // Expected: C, B, A (descending order)
    assert.strictEqual(rows.length, 3);
    assert.strictEqual(rows[0].category, 'C');
    assert.strictEqual(rows[1].category, 'B');
    assert.strictEqual(rows[2].category, 'A');

    console.log('✓ SELECT DISTINCT with ORDER BY works');
    db.close();
} catch (err) {
    console.error('✗ SELECT DISTINCT with ORDER BY failed:', err.message);
    process.exit(1);
}

// Test 6: SELECT DISTINCT with LIMIT
console.log('\nTest 6: SELECT DISTINCT category FROM table LIMIT 2');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT DISTINCT category FROM table LIMIT 2');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    // Should return only 2 unique values
    assert.strictEqual(rows.length, 2, `Expected 2 rows with LIMIT 2, got ${rows.length}`);

    console.log('✓ SELECT DISTINCT with LIMIT works');
    db.close();
} catch (err) {
    console.error('✗ SELECT DISTINCT with LIMIT failed:', err.message);
    process.exit(1);
}

// Test 7: SELECT without DISTINCT (baseline - should have duplicates)
console.log('\nTest 7: SELECT category FROM table (without DISTINCT - baseline)');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT category FROM table');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    // Should return all 8 rows (with duplicates)
    assert.strictEqual(rows.length, 8, `Expected 8 rows without DISTINCT, got ${rows.length}`);

    console.log('✓ SELECT without DISTINCT returns all rows (including duplicates)');
    db.close();
} catch (err) {
    console.error('✗ SELECT without DISTINCT failed:', err.message);
    process.exit(1);
}

// Test 8: SELECT DISTINCT * (all columns)
console.log('\nTest 8: SELECT DISTINCT * FROM table');
try {
    const db = new Database(dbPath);
    const stmt = db.prepare('SELECT DISTINCT * FROM table');
    const rows = stmt.all();
    console.log(`Rows: ${JSON.stringify(rows)}`);

    // All columns together: (A,1,foo), (B,2,bar), (A,1,foo), (C,3,baz), etc.
    // Unique combinations when considering all columns: 3
    // (A,1,foo), (B,2,bar), (C,3,baz)
    assert.strictEqual(rows.length, 3, `Expected 3 unique rows, got ${rows.length}`);

    console.log('✓ SELECT DISTINCT * works');
    db.close();
} catch (err) {
    console.error('✗ SELECT DISTINCT * failed:', err.message);
    process.exit(1);
}

console.log('\n✅ All DISTINCT tests passed!');
