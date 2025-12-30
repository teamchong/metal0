/**
 * CRUD operations test for LocalDatabase
 * Run with: node --test test/crud.test.js
 */

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';

// Mock IndexedDB for Node.js testing
import { LocalDatabase, DatasetStorage } from '../src/lanceql.js';

// Simple in-memory storage mock for testing
class MemoryStorage {
    constructor() {
        this.data = new Map();
    }
    async save(name, data) {
        this.data.set(name, data);
        return { name, size: data.byteLength, storage: 'memory' };
    }
    async load(name) {
        return this.data.get(name) || null;
    }
    async delete(name) {
        this.data.delete(name);
    }
    async list() {
        return Array.from(this.data.keys()).map(name => ({ name }));
    }
    async exists(name) {
        return this.data.has(name);
    }
}

describe('LocalDatabase CRUD', () => {
    let db;
    let storage;

    before(async () => {
        storage = new MemoryStorage();
        db = new LocalDatabase('test-db', storage);
        await db.open();
    });

    after(async () => {
        await db.close();
    });

    it('CREATE TABLE', async () => {
        const result = await db.exec(`
            CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                name TEXT,
                email TEXT,
                age INTEGER
            )
        `);
        assert.strictEqual(result.success, true);
        assert.strictEqual(result.table, 'users');
        assert.ok(db.listTables().includes('users'));
    });

    it('INSERT INTO', async () => {
        const result = await db.exec(`
            INSERT INTO users (id, name, email, age) VALUES
            (1, 'Alice', 'alice@example.com', 30),
            (2, 'Bob', 'bob@example.com', 25),
            (3, 'Charlie', 'charlie@example.com', 35)
        `);
        assert.strictEqual(result.success, true);
        assert.strictEqual(result.inserted, 3);
    });

    it('SELECT *', async () => {
        const rows = await db.exec('SELECT * FROM users');
        assert.strictEqual(rows.length, 3);
        assert.strictEqual(rows[0].name, 'Alice');
        assert.strictEqual(rows[1].name, 'Bob');
        assert.strictEqual(rows[2].name, 'Charlie');
    });

    it('SELECT with WHERE', async () => {
        const rows = await db.exec('SELECT * FROM users WHERE age > 28');
        assert.strictEqual(rows.length, 2);
        assert.ok(rows.some(r => r.name === 'Alice'));
        assert.ok(rows.some(r => r.name === 'Charlie'));
    });

    it('SELECT with ORDER BY', async () => {
        const rows = await db.exec('SELECT * FROM users ORDER BY age DESC');
        assert.strictEqual(rows[0].name, 'Charlie');
        assert.strictEqual(rows[1].name, 'Alice');
        assert.strictEqual(rows[2].name, 'Bob');
    });

    it('SELECT with LIMIT', async () => {
        const rows = await db.exec('SELECT * FROM users LIMIT 2');
        assert.strictEqual(rows.length, 2);
    });

    it('UPDATE', async () => {
        const result = await db.exec("UPDATE users SET age = 31 WHERE name = 'Alice'");
        assert.strictEqual(result.success, true);
        assert.strictEqual(result.updated, 1);

        const rows = await db.exec("SELECT * FROM users WHERE name = 'Alice'");
        assert.strictEqual(rows[0].age, 31);
    });

    it('DELETE', async () => {
        const result = await db.exec("DELETE FROM users WHERE name = 'Bob'");
        assert.strictEqual(result.success, true);
        assert.strictEqual(result.deleted, 1);

        const rows = await db.exec('SELECT * FROM users');
        assert.strictEqual(rows.length, 2);
        assert.ok(!rows.some(r => r.name === 'Bob'));
    });

    it('DROP TABLE', async () => {
        // Create a temp table first
        await db.exec('CREATE TABLE temp (id INTEGER)');
        assert.ok(db.listTables().includes('temp'));

        const result = await db.exec('DROP TABLE temp');
        assert.strictEqual(result.success, true);
        assert.ok(!db.listTables().includes('temp'));
    });

    it('ACID - persistence across sessions', async () => {
        // Close and reopen database
        await db.close();

        const db2 = new LocalDatabase('test-db', storage);
        await db2.open();

        // Data should still be there
        const rows = await db2.exec('SELECT * FROM users');
        assert.strictEqual(rows.length, 2);
        assert.ok(rows.some(r => r.name === 'Alice'));
        assert.ok(rows.some(r => r.name === 'Charlie'));

        await db2.close();
    });
});

describe('LocalDatabase with Vectors', () => {
    let db;
    let storage;

    before(async () => {
        storage = new MemoryStorage();
        db = new LocalDatabase('vector-db', storage);
        await db.open();
    });

    after(async () => {
        await db.close();
    });

    it('CREATE TABLE with VECTOR column', async () => {
        const result = await db.createTable('embeddings', [
            { name: 'id', type: 'INTEGER', primaryKey: true },
            { name: 'text', type: 'TEXT' },
            { name: 'embedding', type: 'VECTOR', vectorDim: 384 },
        ]);
        assert.strictEqual(result.success, true);
    });

    it('INSERT with vector data', async () => {
        const embedding = new Array(384).fill(0).map(() => Math.random());
        const result = await db.insert('embeddings', [
            { id: 1, text: 'Hello world', embedding },
        ]);
        assert.strictEqual(result.success, true);
        assert.strictEqual(result.inserted, 1);
    });

    it('SELECT vector data', async () => {
        const rows = await db.select('embeddings');
        assert.strictEqual(rows.length, 1);
        assert.strictEqual(rows[0].text, 'Hello world');
        assert.strictEqual(rows[0].embedding.length, 384);
    });
});

console.log('Running CRUD tests...');
