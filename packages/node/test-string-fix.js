const Database = require('./src/index.js');
const paths = require('../../tests/fixtures/better-sqlite3/paths.json');

console.log('Testing string column fix with simple fixture...');
console.log('Lance file:', paths.simple);

try {
    const db = new Database(paths.simple);
    console.log('✓ Database opened successfully');

    // Test 1: Read all rows
    console.log('\nTest 1: SELECT * FROM table');
    const allRows = db.prepare('SELECT * FROM table').all();
    console.log('✓ Query executed successfully');
    console.log('Row count:', allRows.length);
    console.log('First row:', allRows[0]);
    console.log('Last row:', allRows[allRows.length - 1]);

    // Test 2: Verify string values
    console.log('\nTest 2: Verify string values');
    const expectedStrings = ['foo', 'bar', 'baz', 'qux', 'quux', 'corge', 'grault', 'garply', 'waldo', 'fred'];
    const actualStrings = allRows.map(row => row.a);
    console.log('Expected:', expectedStrings);
    console.log('Actual:', actualStrings);

    let passed = true;
    for (let i = 0; i < expectedStrings.length; i++) {
        if (actualStrings[i] !== expectedStrings[i]) {
            console.log(`✗ Mismatch at index ${i}: expected "${expectedStrings[i]}", got "${actualStrings[i]}"`);
            passed = false;
        }
    }

    if (passed) {
        console.log('✓ All string values match!');
    }

    // Test 3: Verify int values
    console.log('\nTest 3: Verify int values');
    const expectedInts = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    const actualInts = allRows.map(row => row.b);
    console.log('Expected:', expectedInts);
    console.log('Actual:', actualInts);

    passed = true;
    for (let i = 0; i < expectedInts.length; i++) {
        if (actualInts[i] !== expectedInts[i]) {
            console.log(`✗ Mismatch at index ${i}: expected ${expectedInts[i]}, got ${actualInts[i]}`);
            passed = false;
        }
    }

    if (passed) {
        console.log('✓ All int values match!');
    }

    // Test 4: WHERE clause on string column
    console.log('\nTest 4: SELECT * FROM table WHERE a = "foo"');
    const fooRows = db.prepare('SELECT * FROM table WHERE a = "foo"').all();
    console.log('Result:', fooRows);
    if (fooRows.length === 1 && fooRows[0].a === 'foo' && fooRows[0].b === 1) {
        console.log('✓ WHERE clause on string column works!');
    } else {
        console.log('✗ WHERE clause failed');
    }

    db.close();
    console.log('\n✓ All tests passed! String column fix is working.');

} catch (err) {
    console.error('\n✗ Error:', err.message);
    console.error(err.stack);
    process.exit(1);
}
