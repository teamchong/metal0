# Translation Scripts

## translate_captions.py

Translate LAION-1M image captions to multiple languages using Meta's NLLB model.

### Installation

```bash
pip install lance transformers torch pyarrow tqdm
```

For GPU acceleration (recommended):
```bash
pip install torch --index-url https://download.pytorch.org/whl/cu118
```

### Usage

**Basic usage (translate 100K captions to Chinese and Spanish):**
```bash
python translate_captions.py \
  --input ../laion-1m/images.lance \
  --output ../translations/ \
  --languages zh,es \
  --limit 100000
```

**Translate all 1M captions (takes ~28 hours on GPU):**
```bash
python translate_captions.py \
  --input ../laion-1m/images.lance \
  --output ../translations/ \
  --languages zh,es,ja,fr \
  --limit 0  # 0 = all captions
```

**Adjust batch size for your GPU:**
```bash
# Larger batch = faster but more VRAM
python translate_captions.py \
  --input ../laion-1m/images.lance \
  --output ../translations/ \
  --languages zh,es \
  --limit 100000 \
  --batch-size 64  # Default: 32
```

### Supported Languages

- `en` - English (original)
- `zh` - Chinese (Simplified) - 中文
- `es` - Spanish - Español
- `ja` - Japanese - 日本語
- `fr` - French - Français

### Output

Creates separate Lance datasets for each language:
```
translations/
├── captions_en.lance/    # English (original)
├── captions_zh.lance/    # Chinese
├── captions_es.lance/    # Spanish
└── captions_ja.lance/    # Japanese (if requested)
```

Each dataset has the schema:
- `image_id` (int64) - Links to original images dataset
- `text` (string) - Translated caption
- `language` (string) - Language code

### Performance

| Setup | Speed | Time for 100K | Time for 1M |
|-------|-------|---------------|-------------|
| CPU (8 cores) | ~1 caption/sec | ~28 hours | ~11 days |
| GPU (RTX 3090) | ~10 captions/sec | ~3 hours | ~28 hours |
| GPU (A100) | ~20 captions/sec | ~1.5 hours | ~14 hours |

### Upload to R2

After generating translations, upload to Cloudflare R2:

```bash
# Upload English captions
aws s3 sync translations/captions_en.lance \
  s3://metal0-data/laion-1m/captions_en.lance/ \
  --profile r2 \
  --endpoint-url https://36498dc359676cbbcf8c3616e6c07e94.r2.cloudflarestorage.com \
  --delete

# Upload Chinese captions
aws s3 sync translations/captions_zh.lance \
  s3://metal0-data/laion-1m/captions_zh.lance/ \
  --profile r2 \
  --endpoint-url https://36498dc359676cbbcf8c3616e6c07e94.r2.cloudflarestorage.com \
  --delete

# Upload Spanish captions
aws s3 sync translations/captions_es.lance \
  s3://metal0-data/laion-1m/captions_es.lance/ \
  --profile r2 \
  --endpoint-url https://36498dc359676cbbcf8c3616e6c07e94.r2.cloudflarestorage.com \
  --delete
```

### Public URLs

After upload, datasets will be available at:
- `https://data.metal0.dev/laion-1m/captions_en.lance`
- `https://data.metal0.dev/laion-1m/captions_zh.lance`
- `https://data.metal0.dev/laion-1m/captions_es.lance`

### Example JOIN Query

Once uploaded, you can query across languages:

```javascript
const db = await LanceQL.createDatabase();
await db.registerRemote('images', 'https://data.metal0.dev/laion-1m/images.lance');
await db.registerRemote('captions_en', 'https://data.metal0.dev/laion-1m/captions_en.lance');
await db.registerRemote('captions_zh', 'https://data.metal0.dev/laion-1m/captions_zh.lance');
await db.registerRemote('captions_es', 'https://data.metal0.dev/laion-1m/captions_es.lance');

// Multi-table multilingual query!
const results = await db.executeSQL(`
  SELECT i.url, en.text as english, zh.text as chinese, es.text as spanish
  FROM images i
  JOIN captions_en en ON i.id = en.image_id
  JOIN captions_zh zh ON i.id = zh.image_id
  JOIN captions_es es ON i.id = es.image_id
  WHERE i.aesthetic > 7.0
    AND en.text LIKE '%cat%'
  LIMIT 20
`);
```

## Cost Estimate

### Using NLLB (Free)

- Model: facebook/nllb-200-distilled-600M (1.3GB download)
- Cost: $0 (open source)
- Time: ~3 hours per language per 100K captions (GPU)

### Using Paid APIs (Alternative)

**Google Cloud Translation:**
- Cost: $20 per 1M characters
- Average caption: ~50 characters
- 100K captions = 5M characters = **$100**
- Much faster: ~10 minutes

**DeepL API:**
- Cost: $25 per 500K characters
- 100K captions = 5M characters = **$250**
- Better quality than Google

**Recommendation:** Use NLLB (free) for this project. Quality is good enough for demo purposes.
