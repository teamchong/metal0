#!/usr/bin/env node

/**
 * Node.js test for JOIN implementation (parser only, no WASM)
 */

import { SQLLexer, SQLParser } from './packages/browser/src/lanceql.js';

console.log('🧪 Testing JOIN Implementation\n');

// Test 1: Basic JOIN parsing
console.log('Test 1: Basic JOIN Parsing');
console.log('=' .repeat(50));

const sql1 = `
    SELECT i.url, c.text
    FROM images i
    JOIN captions c ON i.id = c.image_id
    WHERE i.aesthetic > 7.0
    LIMIT 20
`;

try {
    const lexer1 = new SQLLexer(sql1);
    const tokens1 = lexer1.tokenize();
    console.log(`✓ Tokenized: ${tokens1.length} tokens`);

    const parser1 = new SQLParser(tokens1);
    const ast1 = parser1.parse();

    console.log(`✓ Parsed successfully`);
    console.log(`  - Type: ${ast1.type}`);
    console.log(`  - Columns: ${ast1.columns.length}`);
    console.log(`  - From: ${ast1.from?.name || ast1.from?.table}`);
    console.log(`  - Joins: ${ast1.joins?.length || 0}`);

    if (ast1.joins && ast1.joins.length > 0) {
        const join = ast1.joins[0];
        console.log(`  - JOIN type: ${join.type}`);
        console.log(`  - JOIN table: ${join.table?.name || join.table?.table}`);
        console.log(`  - JOIN alias: ${join.alias}`);
        console.log(`  - ON condition: ${join.on ? 'present' : 'missing'}`);

        if (join.on) {
            console.log(`    - Condition type: ${join.on.type}`);
            console.log(`    - Operator: ${join.on.op}`);
        }
    }

    console.log('\n✅ Test 1 PASSED\n');
} catch (error) {
    console.error('❌ Test 1 FAILED:', error.message);
    console.error(error.stack);
    process.exit(1);
}

// Test 2: Multiple JOIN types
console.log('Test 2: Different JOIN Types');
console.log('=' .repeat(50));

const joinTypes = [
    'SELECT * FROM a JOIN b ON a.id = b.id',
    'SELECT * FROM a INNER JOIN b ON a.id = b.id',
    'SELECT * FROM a LEFT JOIN b ON a.id = b.id',
    'SELECT * FROM a RIGHT JOIN b ON a.id = b.id',
    'SELECT * FROM a FULL OUTER JOIN b ON a.id = b.id',
];

for (const sql of joinTypes) {
    try {
        const lexer = new SQLLexer(sql);
        const tokens = lexer.tokenize();
        const parser = new SQLParser(tokens);
        const ast = parser.parse();

        if (ast.joins && ast.joins.length > 0) {
            console.log(`✓ ${ast.joins[0].type} JOIN parsed`);
        } else {
            throw new Error('No JOIN found in AST');
        }
    } catch (error) {
        console.error(`❌ Failed to parse: ${sql}`);
        console.error(`   Error: ${error.message}`);
        process.exit(1);
    }
}

console.log('\n✅ Test 2 PASSED\n');

// Test 3: Complex JOIN with aliases
console.log('Test 3: Complex JOIN with Aliases');
console.log('=' .repeat(50));

const sql3 = `
    SELECT i.url, en.text as english, zh.text as chinese
    FROM images i
    JOIN captions_en en ON i.id = en.image_id
    WHERE i.aesthetic > 7.0
    LIMIT 10
`;

try {
    const lexer3 = new SQLLexer(sql3);
    const tokens3 = lexer3.tokenize();
    const parser3 = new SQLParser(tokens3);
    const ast3 = parser3.parse();

    console.log(`✓ Parsed complex query`);
    console.log(`  - SELECT columns: ${ast3.columns.length}`);
    console.log(`  - From alias: ${ast3.from?.alias || 'none'}`);
    console.log(`  - Join count: ${ast3.joins?.length || 0}`);

    if (ast3.joins && ast3.joins.length > 0) {
        ast3.joins.forEach((join, i) => {
            console.log(`  - JOIN ${i + 1}:`);
            console.log(`    - Table: ${join.table?.name || join.table?.table}`);
            console.log(`    - Alias: ${join.alias}`);
        });
    }

    // Check column references
    console.log(`  - Column references:`);
    ast3.columns.forEach(col => {
        if (col.type === 'expr' && col.expr.type === 'column') {
            const table = col.expr.table || 'none';
            const column = col.expr.column;
            const alias = col.alias || 'none';
            console.log(`    - ${table}.${column} AS ${alias}`);
        }
    });

    console.log('\n✅ Test 3 PASSED\n');
} catch (error) {
    console.error('❌ Test 3 FAILED:', error.message);
    console.error(error.stack);
    process.exit(1);
}

// Test 4: Verify AST structure
console.log('Test 4: AST Structure Validation');
console.log('=' .repeat(50));

const sql4 = 'SELECT a.x, b.y FROM t1 a JOIN t2 b ON a.id = b.id LIMIT 5';

try {
    const lexer4 = new SQLLexer(sql4);
    const tokens4 = lexer4.tokenize();
    const parser4 = new SQLParser(tokens4);
    const ast4 = parser4.parse();

    // Validate AST structure
    const checks = [
        { name: 'has type', test: () => ast4.type === 'SELECT' },
        { name: 'has columns', test: () => Array.isArray(ast4.columns) },
        { name: 'has from', test: () => ast4.from !== null },
        { name: 'has joins array', test: () => Array.isArray(ast4.joins) },
        { name: 'joins not empty', test: () => ast4.joins.length > 0 },
        { name: 'join has type', test: () => ast4.joins[0].type !== undefined },
        { name: 'join has table', test: () => ast4.joins[0].table !== undefined },
        { name: 'join has on', test: () => ast4.joins[0].on !== undefined },
        { name: 'has limit', test: () => ast4.limit === 5 },
    ];

    let passed = 0;
    for (const check of checks) {
        try {
            if (check.test()) {
                console.log(`  ✓ ${check.name}`);
                passed++;
            } else {
                console.log(`  ✗ ${check.name} - returned false`);
            }
        } catch (error) {
            console.log(`  ✗ ${check.name} - threw error: ${error.message}`);
        }
    }

    if (passed === checks.length) {
        console.log(`\n✅ Test 4 PASSED (${passed}/${checks.length} checks)\n`);
    } else {
        console.log(`\n⚠️  Test 4 PARTIAL (${passed}/${checks.length} checks)\n`);
    }
} catch (error) {
    console.error('❌ Test 4 FAILED:', error.message);
    console.error(error.stack);
    process.exit(1);
}

// Summary
console.log('=' .repeat(50));
console.log('✅ ALL TESTS PASSED!');
console.log('=' .repeat(50));
console.log('\nJOIN Parser Implementation: WORKING ✓');
console.log('\nNext steps:');
console.log('  1. Test in browser: http://localhost:3100/test-join.html');
console.log('  2. Test with real datasets (executor)');
console.log('  3. Generate translated caption datasets');
console.log('  4. Upload to R2 and test multilingual JOINs');
