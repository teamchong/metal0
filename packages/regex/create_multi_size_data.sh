#!/bin/bash

echo "Creating multi-size benchmark datasets (Rust regex standard sizes)..."

# Common realistic content template
TEMPLATE='The quick brown fox jumps over the lazy dog. Email me at user@example.com for more info.
Visit our website at https://www.example.com/path/to/page?query=123 for details.
Call us at (555) 123-4567 or 555-987-6543 for customer support.
Order #12345 was shipped on 2024-01-15 and will arrive by 2024-01-20.
The price is $49.99 per unit, with a 15% discount applied.
IPv4: 192.168.1.1, IPv6: 2001:0db8:85a3:0000:0000:8a2e:0370:7334
Processing 1234567890 records took 123.456 seconds with 99.9% accuracy.
Error: File not found at /usr/local/bin/app.exe (code: 404)
Temperature readings: 23.5°C, 74.3°F, 296.65K
User IDs: abc123, xyz789, def456, ghi012
Timestamps: 2024-11-23T08:30:45Z, 2024-11-23T14:22:10Z
Version: v1.2.3-beta.4+build.567
'

# SMALL: 1KB (Rust standard - cache-friendly)
{
    echo "$TEMPLATE"
} > bench_data_small.txt
# Pad to exactly 1KB
truncate -s 1024 bench_data_small.txt
echo "Created bench_data_small.txt: $(wc -c < bench_data_small.txt) bytes"

# MEDIUM: 32KB (Rust standard - L1 cache limit)
{
    for i in {1..22}; do
        echo "$TEMPLATE"
    done
} > bench_data_medium.txt
# Pad to exactly 32KB
truncate -s 32768 bench_data_medium.txt
echo "Created bench_data_medium.txt: $(wc -c < bench_data_medium.txt) bytes"

# LARGE: 500KB (Rust standard - realistic files)
{
    for i in {1..350}; do
        echo "$TEMPLATE"
    done
} > bench_data_large.txt
# Pad to exactly 500KB
truncate -s 512000 bench_data_large.txt
echo "Created bench_data_large.txt: $(wc -c < bench_data_large.txt) bytes"

# EXTRA: 100x multiplier for stress testing (50MB)
{
    for i in {1..35000}; do
        echo "$TEMPLATE"
    done
} > bench_data_large_100x.txt
echo "Created bench_data_large_100x.txt (100x): $(wc -c < bench_data_large_100x.txt) bytes"

echo ""
echo "Summary (Rust regex standard sizes):"
ls -lh bench_data_small.txt bench_data_medium.txt bench_data_large.txt bench_data_large_100x.txt

echo ""
echo "Match counts:"
for file in bench_data_small.txt bench_data_medium.txt bench_data_large.txt; do
    echo "$file:"
    echo "  Emails (@): $(grep -o '@' "$file" | wc -l)"
    echo "  URLs (http): $(grep -o 'http' "$file" | wc -l)"
    echo "  Digits: $(grep -oE '[0-9]+' "$file" | wc -l)"
done
