import { describe, it, expect, afterEach } from 'vitest';
import path from 'path';

const Database = require('../src/index.js');

const FIXTURE_DIR = path.join(__dirname, '../../../tests/fixtures');
const SIMPLE_INT64_LANCE = path.join(
  FIXTURE_DIR,
  'simple_int64.lance/data/0100110011011011000010005445a8407eb6f52a3c35f80bd3.lance'
);

describe('Memory Safety', () => {
  let db;

  afterEach(() => {
    if (db && db.open) {
      db.close();
    }
  });

  describe('repeated operations', () => {
    it('should handle 1000 consecutive queries without memory leaks', () => {
      db = new Database(SIMPLE_INT64_LANCE);

      for (let i = 0; i < 1000; i++) {
        const rows = db.prepare('SELECT * FROM table').all();
        expect(rows.length).toBe(5);
      }
    });

    it('should handle 1000 open/close cycles', () => {
      for (let i = 0; i < 1000; i++) {
        const tempDb = new Database(SIMPLE_INT64_LANCE);
        expect(tempDb.open).toBe(true);
        tempDb.close();
        expect(tempDb.open).toBe(false);
      }
    });

    it('should handle 1000 prepared statements', () => {
      db = new Database(SIMPLE_INT64_LANCE);

      for (let i = 0; i < 1000; i++) {
        const stmt = db.prepare('SELECT * FROM table WHERE id > 0');
        const rows = stmt.all();
        expect(rows.length).toBe(5);
      }
    });
  });

  describe('concurrent access patterns', () => {
    it('should handle multiple statements on same connection', () => {
      db = new Database(SIMPLE_INT64_LANCE);

      const stmt1 = db.prepare('SELECT * FROM table');
      const stmt2 = db.prepare('SELECT * FROM table WHERE id > 2');
      const stmt3 = db.prepare('SELECT * FROM table LIMIT 1');

      for (let i = 0; i < 100; i++) {
        expect(stmt1.all().length).toBe(5);
        expect(stmt2.all().length).toBe(3);
        expect(stmt3.all().length).toBe(1);
      }
    });
  });

  describe('edge cases', () => {
    it('should handle empty result sets', () => {
      db = new Database(SIMPLE_INT64_LANCE);

      for (let i = 0; i < 100; i++) {
        const rows = db.prepare('SELECT * FROM table WHERE id > 1000').all();
        expect(rows.length).toBe(0);
      }
    });

    it('should handle get() returning undefined', () => {
      db = new Database(SIMPLE_INT64_LANCE);

      for (let i = 0; i < 100; i++) {
        const row = db.prepare('SELECT * FROM table WHERE id > 1000').get();
        expect(row).toBeUndefined();
      }
    });
  });
});
