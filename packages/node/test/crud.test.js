/**
 * CRUD operations test for LocalDatabase (Node.js)
 * Run with: npm test
 */

import { describe, it, beforeAll, afterAll, expect } from 'vitest';
import path from 'path';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';
import fs from 'fs/promises';

const require = createRequire(import.meta.url);
// Import LocalDatabase directly (pure JS, no native binding)
const { LocalDatabase } = require('../src/local-database.js');

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const TEST_DB_PATH = path.join(__dirname, 'test-db');

async function rimraf(dirPath) {
    try {
        await fs.rm(dirPath, { recursive: true, force: true });
    } catch {}
}

describe('LocalDatabase CRUD', () => {
    let db;

    beforeAll(async () => {
        // Clean up previous test db
        await rimraf(TEST_DB_PATH);

        db = new LocalDatabase(TEST_DB_PATH);
        await db.open();
    });

    afterAll(async () => {
        await db.close();
        // Clean up test db
        await rimraf(TEST_DB_PATH);
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
        expect(result.success).toBe(true);
        expect(result.table).toBe('users');
        expect(db.listTables()).toContain('users');
    });

    it('INSERT INTO', async () => {
        const result = await db.exec(`
            INSERT INTO users (id, name, email, age) VALUES
            (1, 'Alice', 'alice@example.com', 30),
            (2, 'Bob', 'bob@example.com', 25),
            (3, 'Charlie', 'charlie@example.com', 35)
        `);
        expect(result.success).toBe(true);
        expect(result.inserted).toBe(3);
    });

    it('SELECT *', async () => {
        const rows = await db.exec('SELECT * FROM users');
        expect(rows.length).toBe(3);
        expect(rows[0].name).toBe('Alice');
        expect(rows[1].name).toBe('Bob');
        expect(rows[2].name).toBe('Charlie');
    });

    it('SELECT with WHERE', async () => {
        const rows = await db.exec('SELECT * FROM users WHERE age > 28');
        expect(rows.length).toBe(2);
        expect(rows.some(r => r.name === 'Alice')).toBe(true);
        expect(rows.some(r => r.name === 'Charlie')).toBe(true);
    });

    it('SELECT with ORDER BY', async () => {
        const rows = await db.exec('SELECT * FROM users ORDER BY age DESC');
        expect(rows[0].name).toBe('Charlie');
        expect(rows[1].name).toBe('Alice');
        expect(rows[2].name).toBe('Bob');
    });

    it('SELECT with LIMIT', async () => {
        const rows = await db.exec('SELECT * FROM users LIMIT 2');
        expect(rows.length).toBe(2);
    });

    it('UPDATE', async () => {
        const result = await db.exec("UPDATE users SET age = 31 WHERE name = 'Alice'");
        expect(result.success).toBe(true);
        expect(result.updated).toBe(1);

        const rows = await db.exec("SELECT * FROM users WHERE name = 'Alice'");
        expect(rows[0].age).toBe(31);
    });

    it('DELETE', async () => {
        const result = await db.exec("DELETE FROM users WHERE name = 'Bob'");
        expect(result.success).toBe(true);
        expect(result.deleted).toBe(1);

        const rows = await db.exec('SELECT * FROM users');
        expect(rows.length).toBe(2);
        expect(rows.some(r => r.name === 'Bob')).toBe(false);
    });

    it('DROP TABLE', async () => {
        await db.exec('CREATE TABLE temp (id INTEGER)');
        expect(db.listTables()).toContain('temp');

        const result = await db.exec('DROP TABLE temp');
        expect(result.success).toBe(true);
        expect(db.listTables()).not.toContain('temp');
    });
});

describe('ACID - persistence', () => {
    const PERSIST_DB_PATH = path.join(__dirname, 'persist-db');
    let db;

    beforeAll(async () => {
        await rimraf(PERSIST_DB_PATH);

        db = new LocalDatabase(PERSIST_DB_PATH);
        await db.open();

        await db.exec(`
            CREATE TABLE items (
                id INTEGER PRIMARY KEY,
                name TEXT
            )
        `);
        await db.exec(`INSERT INTO items (id, name) VALUES (1, 'Item1'), (2, 'Item2')`);
    });

    afterAll(async () => {
        await rimraf(PERSIST_DB_PATH);
    });

    it('persists data across sessions', async () => {
        await db.close();

        // Reopen database
        const db2 = new LocalDatabase(PERSIST_DB_PATH);
        await db2.open();

        const rows = await db2.exec('SELECT * FROM items');
        expect(rows.length).toBe(2);
        expect(rows.some(r => r.name === 'Item1')).toBe(true);
        expect(rows.some(r => r.name === 'Item2')).toBe(true);

        await db2.close();
    });
});

describe('LocalDatabase with Vectors', () => {
    const VECTOR_DB_PATH = path.join(__dirname, 'vector-db');
    let db;

    beforeAll(async () => {
        await rimraf(VECTOR_DB_PATH);

        db = new LocalDatabase(VECTOR_DB_PATH);
        await db.open();
    });

    afterAll(async () => {
        await db.close();
        await rimraf(VECTOR_DB_PATH);
    });

    it('CREATE TABLE with VECTOR column', async () => {
        const result = await db.createTable('embeddings', [
            { name: 'id', type: 'INTEGER', primaryKey: true },
            { name: 'text', type: 'TEXT' },
            { name: 'embedding', type: 'VECTOR', vectorDim: 384 },
        ]);
        expect(result.success).toBe(true);
    });

    it('INSERT with vector data', async () => {
        const embedding = new Array(384).fill(0).map(() => Math.random());
        const result = await db.insert('embeddings', [
            { id: 1, text: 'Hello world', embedding },
        ]);
        expect(result.success).toBe(true);
        expect(result.inserted).toBe(1);
    });

    it('SELECT vector data', async () => {
        const rows = await db.select('embeddings');
        expect(rows.length).toBe(1);
        expect(rows[0].text).toBe('Hello world');
        expect(rows[0].embedding.length).toBe(384);
    });
});
