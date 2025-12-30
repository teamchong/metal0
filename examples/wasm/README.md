# LanceQL Web Demo

Browser-based Lance file reader with SQL queries and vector search. Query 1M+ row datasets directly from URLs without downloading the full file.

**Live Demo:** [https://teamchong.github.io/lanceql/](https://teamchong.github.io/lanceql/)

## Features

- **SQL Queries** - DuckDB-style syntax with `read_lance()` function
- **Vector Search** - Semantic search using MiniLM or CLIP encoders
- **HTTP Range Requests** - Only downloads needed data (~100MB instead of 1.5GB)
- **IVF Index Support** - Fast approximate nearest neighbor search

## SQL Syntax

### Basic Queries

```sql
-- Load and query remote dataset
SELECT * FROM read_lance('https://data.metal0.dev/laion-1m/images.lance') LIMIT 50

-- With filter
SELECT url, text, aesthetic
FROM read_lance('https://data.metal0.dev/laion-1m/images.lance')
WHERE aesthetic > 7
LIMIT 100
```

### Vector Search

```sql
-- Text search using MiniLM (default)
SELECT * FROM read_lance('https://data.metal0.dev/laion-1m/images.lance')
SEARCH 'cat'
LIMIT 20

-- Image search using CLIP
SELECT * FROM read_lance('https://data.metal0.dev/laion-1m/images.lance')
SEARCH 'sunset on the beach' USING clip
LIMIT 20

-- Specify vector column
SELECT * FROM read_lance('https://data.metal0.dev/laion-1m/images.lance')
SEARCH 'cat' ON embedding
LIMIT 20
```

## DataFrame API

```python
import lanceql

# Open remote dataset
dataset = lanceql.open("https://data.metal0.dev/laion-1m/images.lance")

# Query data
result = (
    dataset.df()
    .search("cat", encoder="minilm")
    .filter("aesthetic", ">", 7)
    .select(["url", "text", "aesthetic"])
    .limit(50)
    .collect()
)
```

## Encoders

| Encoder | Model | Dimensions | Use Case |
|---------|-------|------------|----------|
| `minilm` | all-MiniLM-L6-v2 | 384 | Text-to-text similarity |
| `clip` | OpenAI ViT-B/32 | 512 | Text-to-image search |

## Dataset

The demo uses the LAION-1M dataset hosted on Cloudflare R2:

- **URL:** `https://data.metal0.dev/laion-1m/images.lance`
- **Rows:** 1,000,000
- **Schema:** `url`, `text`, `width`, `height`, `aesthetic`, `embedding` (384D)
- **Index:** IVF-PQ with 256 partitions

## Local Development

```bash
# Build WASM module
zig build wasm
cp zig-out/bin/lanceql.wasm examples/wasm/

# Start local server
cd examples/wasm
python -m http.server 3000

# Open http://localhost:3000
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Browser (JavaScript)                     │
├─────────────────────────────────────────────────────────────┤
│  SQL Parser  │  DataFrame API  │  Text Encoders (WASM)       │
├─────────────────────────────────────────────────────────────┤
│                    LanceQL WASM Module                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Lance File  │  │  Protobuf   │  │  Vector Search      │  │
│  │  Parser     │  │  Decoder    │  │  (IVF Index)        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                  HTTP Range Requests (fetch)                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Cloudflare R2 / Any HTTP Server                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  images.lance/                                       │    │
│  │  ├── _versions/1.manifest                           │    │
│  │  ├── data/*.lance                                   │    │
│  │  └── ivf_vectors.bin (partition-organized vectors)  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Performance

| Operation | Data Transfer | Time |
|-----------|--------------|------|
| Load metadata | ~50 KB | <1s |
| First 50 rows | ~200 KB | <2s |
| Vector search (20 partitions) | ~100 MB | ~5s |
| Full dataset scan | 1.5 GB | N/A (not needed) |
