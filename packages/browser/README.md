# lanceql

Query Lance columnar files in the browser with SQL and vector search. No server required.

## Features

- **CSS-Driven** - Zero JavaScript! Just add `lq-*` attributes to HTML elements
- **SQL Queries** - SELECT, WHERE, ORDER BY, LIMIT, GROUP BY, aggregations
- **Vector Search** - Semantic search with NEAR clause using MiniLM/CLIP embeddings
- **HTTP Range Requests** - Only fetch the bytes you need from remote files
- **Local + Remote** - Load local files or remote URLs
- **Zero Dependencies** - Pure JavaScript + WebAssembly

## Installation

```bash
npm install lanceql
```

## Quick Start - CSS-Driven (Zero JavaScript)

```html
<!-- Just include the script -->
<script type="module" src="node_modules/lanceql/dist/lanceql.esm.js"></script>

<!-- Query and render with HTML attributes only -->
<div lq-query="SELECT * FROM read_lance('https://example.com/data.lance') LIMIT 10"
     lq-render="table">
</div>
```

That's it! No JavaScript needed. The query executes and renders automatically.

## CSS-Driven Features

### Table Rendering

```html
<div lq-query="SELECT name, value FROM read_lance('https://...') WHERE value > 100 LIMIT 50"
     lq-render="table">
</div>
```

### Image Gallery

```html
<div lq-query="SELECT url, text FROM read_lance('https://...') LIMIT 20"
     lq-render="images">
</div>
```

### Reactive Search

```html
<input type="text" id="search" placeholder="Search...">

<div lq-query="SELECT * FROM read_lance('https://...') WHERE text LIKE '%$value%' LIMIT 20"
     lq-bind="#search"
     lq-render="table">
</div>
```

Types as you search - no JavaScript needed!

### Available Renderers

- `lq-render="table"` - Table with image thumbnails (default)
- `lq-render="images"` - Image grid with captions
- `lq-render="json"` - JSON output
- `lq-render="value"` - Single value (for aggregates)
- `lq-render="list"` - Simple list

## JavaScript API (Optional)

For programmatic control, you can also use the JavaScript API:

```javascript
import LanceQL from 'lanceql';

// Load the WASM module
const lanceql = await LanceQL.load();

// Open a remote dataset
const dataset = await lanceql.openDataset('https://example.com/data.lance');

// Execute SQL
const results = await dataset.executeSQL(`
  SELECT name, value FROM data WHERE value > 100 LIMIT 50
`);

// Vector search
const similar = await dataset.executeSQL(`
  SELECT * FROM data NEAR 'sunset beach' TOPK 20
`);
```

## Usage with Local Files

```javascript
// File input handler
document.getElementById('fileInput').addEventListener('change', async (e) => {
  const file = e.target.files[0];
  const lanceql = await LanceQL.load();
  const lanceFile = await lanceql.openFile(file);

  // Query the file
  const results = await lanceFile.executeSQL('SELECT * FROM data LIMIT 10');
});
```

## SQL Support

```sql
-- Basic queries
SELECT * FROM data LIMIT 100
SELECT col1, col2 FROM data WHERE col1 > 10

-- Aggregations
SELECT COUNT(*), AVG(value), SUM(value) FROM data
SELECT category, COUNT(*) FROM data GROUP BY category

-- Vector search
SELECT * FROM data NEAR 'search text' TOPK 20
SELECT * FROM data NEAR embedding 'query' WHERE score > 0.5
```

## API Reference

### LanceQL.load(wasmUrl?)

Load the WASM module. Returns a LanceQL instance.

```javascript
const lanceql = await LanceQL.load('./lanceql.wasm');
```

### lanceql.openDataset(url, options?)

Open a remote Lance dataset.

```javascript
const dataset = await lanceql.openDataset('https://example.com/data.lance', {
  version: 24,  // Optional: specific version
});
```

### lanceql.openFile(file)

Open a local File object.

```javascript
const lanceFile = await lanceql.openFile(file);
```

### dataset.executeSQL(sql)

Execute a SQL query against the dataset.

```javascript
const results = await dataset.executeSQL('SELECT * FROM data LIMIT 10');
// Returns: { columns: ['col1', 'col2'], values: [[...], [...]] }
```

### dataset.df()

Get a DataFrame API for fluent queries.

```javascript
const result = await dataset.df()
  .filter('value', '>', 100)
  .select(['name', 'value'])
  .limit(50)
  .collect();
```

## Browser Support

- Chrome 89+
- Firefox 89+
- Safari 15+
- Edge 89+

Requires WebAssembly and async/await support.

## License

Apache-2.0
