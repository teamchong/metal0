const { describe, it, before } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('path');
const LanceQL = require('../src/index.js');

describe('Timestamp and Date Types', () => {
  let db;
  let testFilePath;

  before(() => {
    // Read paths.json to get the test file path
    const pathsFile = path.join(__dirname, '../../../tests/fixtures/better-sqlite3/paths.json');
    const paths = JSON.parse(fs.readFileSync(pathsFile, 'utf8'));
    testFilePath = paths.timestamp_test;

    if (!fs.existsSync(testFilePath)) {
      throw new Error(`Test file not found: ${testFilePath}`);
    }

    db = new LanceQL(testFilePath);
  });

  it('should read all timestamp and date columns', () => {
    const rows = db.prepare('SELECT * FROM data ORDER BY id').all();

    assert.strictEqual(rows.length, 3);

    // Verify all columns exist
    const row = rows[0];
    assert.ok('id' in row);
    assert.ok('ts_s' in row);
    assert.ok('ts_ms' in row);
    assert.ok('ts_us' in row);
    assert.ok('ts_ns' in row);
    assert.ok('date32' in row);
    assert.ok('date64' in row);
  });

  it('should convert timestamp[s] to milliseconds for JavaScript', () => {
    const rows = db.prepare('SELECT id, ts_s FROM data WHERE id = 1').all();

    assert.strictEqual(rows.length, 1);
    assert.strictEqual(rows[0].id, 1);

    // ts_s for 2024-01-15 10:30:45 UTC is 1705314645 seconds
    // Should be converted to 1705314645000 milliseconds
    const expectedMs = 1705314645000;
    assert.strictEqual(rows[0].ts_s, expectedMs);

    // Verify it's a valid Date
    const date = new Date(rows[0].ts_s);
    assert.strictEqual(date.toISOString(), '2024-01-15T10:30:45.000Z');
  });

  it('should convert timestamp[ms] to milliseconds (direct)', () => {
    const rows = db.prepare('SELECT id, ts_ms FROM data WHERE id = 1').all();

    assert.strictEqual(rows.length, 1);
    const expectedMs = 1705314645000;
    assert.strictEqual(rows[0].ts_ms, expectedMs);

    const date = new Date(rows[0].ts_ms);
    assert.strictEqual(date.toISOString(), '2024-01-15T10:30:45.000Z');
  });

  it('should convert timestamp[us] to milliseconds', () => {
    const rows = db.prepare('SELECT id, ts_us FROM data WHERE id = 1').all();

    assert.strictEqual(rows.length, 1);
    // Microseconds divided by 1000
    const expectedMs = 1705314645000;
    assert.strictEqual(rows[0].ts_us, expectedMs);

    const date = new Date(rows[0].ts_us);
    assert.strictEqual(date.toISOString(), '2024-01-15T10:30:45.000Z');
  });

  it('should convert timestamp[ns] to milliseconds', () => {
    const rows = db.prepare('SELECT id, ts_ns FROM data WHERE id = 1').all();

    assert.strictEqual(rows.length, 1);
    // Nanoseconds divided by 1000000
    const expectedMs = 1705314645000;
    assert.strictEqual(rows[0].ts_ns, expectedMs);

    const date = new Date(rows[0].ts_ns);
    assert.strictEqual(date.toISOString(), '2024-01-15T10:30:45.000Z');
  });

  it('should convert date32 (days) to milliseconds', () => {
    const rows = db.prepare('SELECT id, date32 FROM data WHERE id = 1').all();

    assert.strictEqual(rows.length, 1);
    // 19737 days * 86400000 ms/day = 1705363200000 ms
    // This represents 2024-01-15 00:00:00 UTC (midnight)
    const expectedMs = 19737 * 86400000;
    assert.strictEqual(rows[0].date32, expectedMs);

    const date = new Date(rows[0].date32);
    assert.strictEqual(date.toISOString(), '2024-01-15T00:00:00.000Z');
  });

  it('should convert date64 to milliseconds (direct)', () => {
    const rows = db.prepare('SELECT id, date64 FROM data WHERE id = 1').all();

    assert.strictEqual(rows.length, 1);
    const expectedMs = 1705314645000;
    assert.strictEqual(rows[0].date64, expectedMs);

    const date = new Date(rows[0].date64);
    assert.strictEqual(date.toISOString(), '2024-01-15T10:30:45.000Z');
  });

  it('should handle Unix epoch (1970-01-01) correctly', () => {
    const rows = db.prepare('SELECT * FROM data WHERE id = 2').all();

    assert.strictEqual(rows.length, 1);
    const row = rows[0];

    // All timestamp types should convert to 0 (Unix epoch)
    assert.strictEqual(row.ts_s, 0);
    assert.strictEqual(row.ts_ms, 0);
    assert.strictEqual(row.ts_us, 0);
    assert.strictEqual(row.ts_ns, 0);
    assert.strictEqual(row.date32, 0);
    assert.strictEqual(row.date64, 0);

    // Verify all convert to valid dates
    assert.strictEqual(new Date(row.ts_s).toISOString(), '1970-01-01T00:00:00.000Z');
  });

  it('should handle Y2K (2000-01-01) correctly', () => {
    const rows = db.prepare('SELECT * FROM data WHERE id = 3').all();

    assert.strictEqual(rows.length, 1);
    const row = rows[0];

    // Y2K timestamp: 946684800 seconds = 946684800000 ms
    assert.strictEqual(row.ts_s, 946684800000);
    assert.strictEqual(row.ts_ms, 946684800000);
    assert.strictEqual(row.ts_us, 946684800000);
    assert.strictEqual(row.ts_ns, 946684800000);

    // Y2K is 10957 days since epoch
    assert.strictEqual(row.date32, 10957 * 86400000);
    assert.strictEqual(row.date64, 946684800000);

    // Verify dates
    assert.strictEqual(new Date(row.ts_s).toISOString(), '2000-01-01T00:00:00.000Z');
    assert.strictEqual(new Date(row.date32).toISOString(), '2000-01-01T00:00:00.000Z');
  });

  it('should support WHERE clauses on timestamp columns', () => {
    // Query for rows after Unix epoch
    const rows = db.prepare('SELECT id FROM data WHERE ts_s > 0 ORDER BY id').all();

    assert.strictEqual(rows.length, 2);
    assert.strictEqual(rows[0].id, 1);
    assert.strictEqual(rows[1].id, 3);
  });

  it('should support ORDER BY on timestamp columns', () => {
    const rows = db.prepare('SELECT id, ts_s FROM data ORDER BY ts_s DESC').all();

    assert.strictEqual(rows.length, 3);
    // Descending order: 2024 (id=1), 2000 (id=3), 1970 (id=2)
    assert.strictEqual(rows[0].id, 1);
    assert.strictEqual(rows[1].id, 3);
    assert.strictEqual(rows[2].id, 2);
  });

  it('should support aggregate functions on timestamp columns', () => {
    const rows = db.prepare('SELECT MIN(ts_s) as min_ts, MAX(ts_s) as max_ts FROM data').all();

    assert.strictEqual(rows.length, 1);
    assert.strictEqual(rows[0].min_ts, 0); // Unix epoch
    assert.strictEqual(rows[0].max_ts, 1705314645000); // 2024 timestamp
  });

  it('should support GROUP BY on date columns', () => {
    const rows = db.prepare('SELECT date32, COUNT(*) as cnt FROM data GROUP BY date32 ORDER BY date32').all();

    assert.strictEqual(rows.length, 3);
    // Should have 3 distinct dates
    assert.strictEqual(rows[0].cnt, 1);
    assert.strictEqual(rows[1].cnt, 1);
    assert.strictEqual(rows[2].cnt, 1);
  });
});
