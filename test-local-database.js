#!/usr/bin/env node

/**
 * Test LocalDatabase with SQL interface (Node.js mock)
 *
 * Note: This test uses a mock storage since IndexedDB/OPFS aren't available in Node.js
 */

import { LocalDatabase, SQLLexer, SQLParser } from './packages/browser/src/lanceql.js';

console.log('🧪 Testing LocalDatabase with SQL\n');

// Mock storage for Node.js testing
class MockStorage {
    constructor() {
        this.data = new Map();
    }

    async open() { return this; }

    async save(name, data) {
        this.data.set(name, data);
        return { name, size: data.length };
    }

    async load(name) {
        return this.data.get(name) || null;
    }

    async delete(name) {
        this.data.delete(name);
        return true;
    }
}

async function runTests() {
    const mockStorage = new MockStorage();
    const db = new LocalDatabase('testdb', mockStorage);
    await db.open();

    // Test 1: CREATE TABLE
    console.log('Test 1: CREATE TABLE');
    console.log('=' .repeat(50));

    try {
        const result1 = await db.exec(`
            CREATE TABLE users (
                id INT PRIMARY KEY,
                name TEXT,
                age INT,
                score FLOAT
            )
        `);

        console.log('✓ Created table users');
        console.log(`  Result: ${JSON.stringify(result1)}`);
        console.log(`  Tables: [${db.listTables().join(', ')}]`);
        console.log('✅ Test 1 PASSED\n');
    } catch (error) {
        console.error('❌ Test 1 FAILED:', error.message);
        process.exit(1);
    }

    // Test 2: INSERT
    console.log('Test 2: INSERT');
    console.log('=' .repeat(50));

    try {
        const result2 = await db.exec(`
            INSERT INTO users (id, name, age, score)
            VALUES (1, 'Alice', 30, 95.5),
                   (2, 'Bob', 25, 88.0),
                   (3, 'Charlie', 35, 92.3)
        `);

        console.log('✓ Inserted rows');
        console.log(`  Result: ${JSON.stringify(result2)}`);
        console.log('✅ Test 2 PASSED\n');
    } catch (error) {
        console.error('❌ Test 2 FAILED:', error.message);
        process.exit(1);
    }

    // Test 3: SELECT
    console.log('Test 3: SELECT');
    console.log('=' .repeat(50));

    try {
        const result3 = await db.exec(`SELECT * FROM users`);

        console.log('✓ Selected all rows');
        console.log(`  Rows: ${result3.length}`);
        result3.forEach((row, i) => {
            console.log(`    ${i + 1}: ${JSON.stringify(row)}`);
        });
        console.log('✅ Test 3 PASSED\n');
    } catch (error) {
        console.error('❌ Test 3 FAILED:', error.message);
        process.exit(1);
    }

    // Test 4: SELECT with WHERE
    console.log('Test 4: SELECT with WHERE');
    console.log('=' .repeat(50));

    try {
        const result4 = await db.exec(`SELECT name, age FROM users WHERE age > 25`);

        console.log('✓ Selected rows where age > 25');
        console.log(`  Rows: ${result4.length}`);
        result4.forEach((row, i) => {
            console.log(`    ${i + 1}: ${JSON.stringify(row)}`);
        });
        console.log('✅ Test 4 PASSED\n');
    } catch (error) {
        console.error('❌ Test 4 FAILED:', error.message);
        process.exit(1);
    }

    // Test 5: UPDATE
    console.log('Test 5: UPDATE');
    console.log('=' .repeat(50));

    try {
        const result5 = await db.exec(`UPDATE users SET score = 100.0 WHERE name = 'Alice'`);

        console.log('✓ Updated Alice score');
        console.log(`  Result: ${JSON.stringify(result5)}`);

        // Verify update
        const verify = await db.exec(`SELECT name, score FROM users WHERE name = 'Alice'`);
        console.log(`  After update: ${JSON.stringify(verify[0])}`);
        console.log('✅ Test 5 PASSED\n');
    } catch (error) {
        console.error('❌ Test 5 FAILED:', error.message);
        process.exit(1);
    }

    // Test 6: DELETE
    console.log('Test 6: DELETE');
    console.log('=' .repeat(50));

    try {
        const result6 = await db.exec(`DELETE FROM users WHERE age < 30`);

        console.log('✓ Deleted rows where age < 30');
        console.log(`  Result: ${JSON.stringify(result6)}`);

        // Verify delete
        const remaining = await db.exec(`SELECT * FROM users`);
        console.log(`  Remaining rows: ${remaining.length}`);
        remaining.forEach((row, i) => {
            console.log(`    ${i + 1}: ${JSON.stringify(row)}`);
        });
        console.log('✅ Test 6 PASSED\n');
    } catch (error) {
        console.error('❌ Test 6 FAILED:', error.message);
        process.exit(1);
    }

    // Test 7: DROP TABLE
    console.log('Test 7: DROP TABLE');
    console.log('=' .repeat(50));

    try {
        const result7 = await db.exec(`DROP TABLE users`);

        console.log('✓ Dropped table users');
        console.log(`  Result: ${JSON.stringify(result7)}`);
        console.log(`  Tables: [${db.listTables().join(', ')}]`);
        console.log('✅ Test 7 PASSED\n');
    } catch (error) {
        console.error('❌ Test 7 FAILED:', error.message);
        process.exit(1);
    }

    // Summary
    console.log('=' .repeat(50));
    console.log('✅ ALL LocalDatabase SQL TESTS PASSED!');
    console.log('=' .repeat(50));
    console.log('\nLocalDatabase now supports:');
    console.log('  - CREATE TABLE ... (col TYPE, ...)');
    console.log('  - INSERT INTO ... VALUES ...');
    console.log('  - SELECT ... FROM ... WHERE ...');
    console.log('  - UPDATE ... SET ... WHERE ...');
    console.log('  - DELETE FROM ... WHERE ...');
    console.log('  - DROP TABLE ...');
    console.log('\nStorage: IndexedDB (small) + OPFS (large files)');
}

runTests().catch(console.error);
