#!/usr/bin/env node

/**
 * Test SQL parser for INSERT/UPDATE/DELETE/CREATE/DROP
 */

import { SQLLexer, SQLParser } from './packages/browser/src/lanceql.js';

console.log('🧪 Testing SQL Parser (CRUD Operations)\n');

// Test 1: INSERT
console.log('Test 1: INSERT Statement');
console.log('=' .repeat(50));

try {
    const sql1 = `INSERT INTO users (id, name, age) VALUES (1, 'Alice', 30), (2, 'Bob', 25)`;
    const lexer1 = new SQLLexer(sql1);
    const tokens1 = lexer1.tokenize();
    const parser1 = new SQLParser(tokens1);
    const ast1 = parser1.parse();

    console.log('✓ Parsed INSERT');
    console.log(`  Type: ${ast1.type}`);
    console.log(`  Table: ${ast1.table}`);
    console.log(`  Columns: [${ast1.columns?.join(', ')}]`);
    console.log(`  Rows: ${ast1.rows?.length}`);
    ast1.rows?.forEach((row, i) => {
        const values = row.map(v => `${v.value}(${v.type})`).join(', ');
        console.log(`    Row ${i + 1}: [${values}]`);
    });
    console.log('✅ Test 1 PASSED\n');
} catch (error) {
    console.error('❌ Test 1 FAILED:', error.message);
    process.exit(1);
}

// Test 2: UPDATE
console.log('Test 2: UPDATE Statement');
console.log('=' .repeat(50));

try {
    const sql2 = `UPDATE users SET name = 'Charlie', age = 35 WHERE id = 1`;
    const lexer2 = new SQLLexer(sql2);
    const tokens2 = lexer2.tokenize();
    const parser2 = new SQLParser(tokens2);
    const ast2 = parser2.parse();

    console.log('✓ Parsed UPDATE');
    console.log(`  Type: ${ast2.type}`);
    console.log(`  Table: ${ast2.table}`);
    console.log(`  Assignments: ${ast2.assignments?.length}`);
    ast2.assignments?.forEach(a => {
        console.log(`    - ${a.column} = ${a.value.value} (${a.value.type})`);
    });
    console.log(`  WHERE: ${ast2.where ? 'present' : 'none'}`);
    console.log('✅ Test 2 PASSED\n');
} catch (error) {
    console.error('❌ Test 2 FAILED:', error.message);
    process.exit(1);
}

// Test 3: DELETE
console.log('Test 3: DELETE Statement');
console.log('=' .repeat(50));

try {
    const sql3 = `DELETE FROM users WHERE age < 18`;
    const lexer3 = new SQLLexer(sql3);
    const tokens3 = lexer3.tokenize();
    const parser3 = new SQLParser(tokens3);
    const ast3 = parser3.parse();

    console.log('✓ Parsed DELETE');
    console.log(`  Type: ${ast3.type}`);
    console.log(`  Table: ${ast3.table}`);
    console.log(`  WHERE: ${ast3.where ? 'present' : 'none'}`);
    console.log('✅ Test 3 PASSED\n');
} catch (error) {
    console.error('❌ Test 3 FAILED:', error.message);
    process.exit(1);
}

// Test 4: CREATE TABLE
console.log('Test 4: CREATE TABLE Statement');
console.log('=' .repeat(50));

try {
    const sql4 = `CREATE TABLE users (id INT PRIMARY KEY, name TEXT, age INT, score FLOAT, embedding VECTOR(384))`;
    const lexer4 = new SQLLexer(sql4);
    const tokens4 = lexer4.tokenize();
    const parser4 = new SQLParser(tokens4);
    const ast4 = parser4.parse();

    console.log('✓ Parsed CREATE TABLE');
    console.log(`  Type: ${ast4.type}`);
    console.log(`  Table: ${ast4.table}`);
    console.log(`  Columns: ${ast4.columns?.length}`);
    ast4.columns?.forEach(c => {
        const pk = c.primaryKey ? ' PRIMARY KEY' : '';
        const dim = c.vectorDim ? `(${c.vectorDim})` : '';
        console.log(`    - ${c.name}: ${c.dataType}${dim}${pk}`);
    });
    console.log('✅ Test 4 PASSED\n');
} catch (error) {
    console.error('❌ Test 4 FAILED:', error.message);
    process.exit(1);
}

// Test 5: DROP TABLE
console.log('Test 5: DROP TABLE Statement');
console.log('=' .repeat(50));

try {
    const sql5 = `DROP TABLE users`;
    const lexer5 = new SQLLexer(sql5);
    const tokens5 = lexer5.tokenize();
    const parser5 = new SQLParser(tokens5);
    const ast5 = parser5.parse();

    console.log('✓ Parsed DROP TABLE');
    console.log(`  Type: ${ast5.type}`);
    console.log(`  Table: ${ast5.table}`);
    console.log('✅ Test 5 PASSED\n');
} catch (error) {
    console.error('❌ Test 5 FAILED:', error.message);
    process.exit(1);
}

// Test 6: SELECT (backward compatibility)
console.log('Test 6: SELECT (backward compatibility)');
console.log('=' .repeat(50));

try {
    const sql6 = `SELECT id, name FROM users WHERE age > 18 LIMIT 10`;
    const lexer6 = new SQLLexer(sql6);
    const tokens6 = lexer6.tokenize();
    const parser6 = new SQLParser(tokens6);
    const ast6 = parser6.parse();

    console.log('✓ Parsed SELECT');
    console.log(`  Type: ${ast6.type}`);
    console.log(`  Columns: ${ast6.columns?.length}`);
    console.log(`  Limit: ${ast6.limit}`);
    console.log('✅ Test 6 PASSED\n');
} catch (error) {
    console.error('❌ Test 6 FAILED:', error.message);
    process.exit(1);
}

// Summary
console.log('=' .repeat(50));
console.log('✅ ALL SQL PARSER TESTS PASSED!');
console.log('=' .repeat(50));
console.log('\nSupported SQL statements:');
console.log('  - SELECT ... FROM ... WHERE ... LIMIT ...');
console.log('  - INSERT INTO ... VALUES ...');
console.log('  - UPDATE ... SET ... WHERE ...');
console.log('  - DELETE FROM ... WHERE ...');
console.log('  - CREATE TABLE ... (col TYPE, ...)');
console.log('  - DROP TABLE ...');
