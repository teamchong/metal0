const Database = require('./src/index.js');
const paths = require('../../tests/fixtures/better-sqlite3/paths.json');

console.log('Testing with int64 column only...');
console.log('Lance file:', paths.simple);

try {
    const db = new Database(paths.simple);
    console.log('✓ Database opened successfully');

    // Test: Read only int column
    console.log('\nTest: SELECT b FROM table');
    const rows = db.prepare('SELECT b FROM table').all();
    console.log('✓ Query executed successfully');
    console.log('Row count:', rows.length);
    console.log('First row:', rows[0]);
    console.log('Last row:', rows[rows.length - 1]);

    db.close();
    console.log('\n✓ Int64 column works!');

} catch (err) {
    console.error('\n✗ Error:', err.message);
    console.error(err.stack);
    process.exit(1);
}
