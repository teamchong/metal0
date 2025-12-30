const fs = require('fs');
const path = require('path');
const LanceQL = require('./src/index.js');

// Read paths.json
const pathsFile = path.join(__dirname, '../../tests/fixtures/better-sqlite3/paths.json');
const paths = JSON.parse(fs.readFileSync(pathsFile, 'utf8'));
const testFilePath = paths.timestamp_test;

console.log('Test file:', testFilePath);
console.log('File exists:', fs.existsSync(testFilePath));

try {
  const db = new LanceQL(testFilePath);
  console.log('Database opened successfully');

  console.log('\nTrying simple SELECT *:');
  const rows = db.prepare('SELECT * FROM data').all();
  console.log('Success! Rows:', rows.length);
  console.log('First row:', JSON.stringify(rows[0], null, 2));
} catch (error) {
  console.error('Error:', error.message);
  console.error('Stack:', error.stack);
}
