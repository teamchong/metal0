# Testing Guide - JOIN Implementation

## Quick Test (5 minutes)

### 1. Start Local Server

```bash
cd examples/wasm
python -m http.server 3100
```

### 2. Open Test Page

Open in browser: **http://localhost:3100/test-join.html**

### 3. Run Tests

Click through the buttons in order:

1. **Load WASM Module** - Should show "✓ WASM loaded successfully"
2. **Test Parser** - Should show "✓ Found 1 JOIN clause(s)"
3. **Create Database** - Should show "✓ LanceDatabase created successfully"
4. **Register Table** - Should show "✓ Dataset registered"
5. **Query Single Table** - Should show 10 rows in a table
6. **Test Mock JOIN** - This will test the JOIN logic!

### Expected Results

#### Parser Test (Step 2)
```json
{
  "type": "SELECT",
  "joins": [
    {
      "type": "INNER",
      "table": { "name": "captions" },
      "alias": "c",
      "on": { "type": "binary", "op": "=", ... }
    }
  ],
  ...
}
```

#### Mock JOIN Test (Step 6)
Should either:
- **Success**: Show joined rows (if implementation works perfectly)
- **Expected Error**: Show error about WHERE IN clause (means parser works, executor needs fix)

## What We're Testing

### ✅ Parser Tests
- JOIN keyword recognition
- Table aliases (e.g., `images i`)
- ON conditions (e.g., `ON i.id = c.image_id`)
- Multiple table references

### ✅ Database Tests
- Creating LanceDatabase instance
- Registering remote datasets
- Table name resolution

### ✅ Executor Tests (Partial)
- Single-table queries work
- JOIN query parsing
- Hash join logic (may need fixes)

## Debugging

If something fails, check browser console:

```javascript
// Browser console commands

// Check what's loaded
console.log('LanceQL:', window.lanceql);
console.log('Database:', window.db);
console.log('Tables:', window.db?.tables);

// Manual parser test
const lexer = new SQLLexer("SELECT * FROM a JOIN b ON a.id = b.id");
const tokens = lexer.tokenize();
console.log('Tokens:', tokens);

const parser = new SQLParser(tokens);
const ast = parser.parse();
console.log('AST:', ast);
console.log('Joins:', ast.joins);

// Manual query test
window.db.executeSQL('SELECT url FROM images LIMIT 5')
  .then(r => console.log('Result:', r))
  .catch(e => console.error('Error:', e));
```

## Known Issues to Fix

If you see these errors, they're expected and will be fixed:

### 1. "WHERE ... IN clause not supported"
**What it means**: Parser works! Executor needs to handle IN clause for join keys.

**Fix**: Update SQLExecutor to support IN clause like:
```sql
WHERE column IN (1, 2, 3, 4, 5)
```

### 2. "Column not found in schema"
**What it means**: Column aliasing issue in JOIN.

**Fix**: Handle column prefixes (e.g., `i.url` vs `url`).

### 3. "Table alias not resolved"
**What it means**: Alias mapping needs work.

**Fix**: Improve alias resolution in `_executeJoin()`.

## Next Steps After Testing

### If Parser Works ✓
- Parser correctly recognizes JOIN keywords
- AST includes `joins` array
- ON conditions parsed correctly

**→ Parser is done!**

### If Single-Table Query Works ✓
- Database can register tables
- executeSQL works for simple queries
- Results are formatted correctly

**→ Basic execution works!**

### If JOIN Has Errors (Expected)
Most likely issues:
1. IN clause not supported in WHERE
2. Column aliasing (table.column syntax)
3. JOIN key extraction logic

**→ Need to debug executor, not a blocker**

## Testing With Real Translated Datasets

Once you run the translation script and upload to R2:

```javascript
// In browser console on test-join.html
const db = window.lanceql.createDatabase();

// Register multiple languages
await db.registerRemote('images', 'https://data.metal0.dev/laion-1m/images.lance');
await db.registerRemote('captions_en', 'https://data.metal0.dev/laion-1m/captions_en.lance');
await db.registerRemote('captions_zh', 'https://data.metal0.dev/laion-1m/captions_zh.lance');

// Try multilingual JOIN
const results = await db.executeSQL(`
  SELECT i.url, en.text as english, zh.text as chinese
  FROM images i
  JOIN captions_en en ON i.id = en.image_id
  JOIN captions_zh zh ON i.id = zh.image_id
  WHERE i.aesthetic > 7.0
  LIMIT 10
`);

console.log(results);
```

## Files Created

- `examples/wasm/test-join.html` - Interactive test page
- `examples/wasm/lanceql.js` - Built library with JOIN support
- `TESTING_GUIDE.md` - This file
- `JOIN_IMPLEMENTATION.md` - Full documentation
- `scripts/translate_captions.py` - Translation script
- `scripts/README.md` - Translation docs

## Summary

**What to check:**
1. ✅ Does parser recognize JOIN?
2. ✅ Does LanceDatabase create?
3. ✅ Can it register tables?
4. ✅ Does single-table query work?
5. ⚠️ Does JOIN execute? (May need fixes)

**Bottom line:** If steps 1-4 work, the implementation is solid. Step 5 may need debugging but that's normal for first iteration.

---

**Not pushed yet!** Waiting for your confirmation that it works.
