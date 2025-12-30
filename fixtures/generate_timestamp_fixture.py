#!/usr/bin/env python3
"""
Generate Lance file with timestamp and date types for testing.

This fixture includes all 6 timestamp/date types:
- timestamp[s]: seconds since epoch
- timestamp[ms]: milliseconds since epoch
- timestamp[us]: microseconds since epoch
- timestamp[ns]: nanoseconds since epoch
- date32[day]: days since epoch
- date64[ms]: milliseconds since epoch
"""

import pyarrow as pa
import pyarrow.parquet as pq
import lancedb
import os
from datetime import datetime, timezone

# Create output directory
output_dir = os.path.join(os.path.dirname(__file__), "../tests/fixtures/better-sqlite3")
os.makedirs(output_dir, exist_ok=True)

# Test timestamp: 2024-01-15 10:30:45 UTC
test_dt = datetime(2024, 1, 15, 10, 30, 45, tzinfo=timezone.utc)
epoch_seconds = int(test_dt.timestamp())
epoch_ms = epoch_seconds * 1000
epoch_us = epoch_seconds * 1000000
epoch_ns = epoch_seconds * 1000000000

# Test date: 2024-01-15 (days since 1970-01-01)
epoch_days = (test_dt.date() - datetime(1970, 1, 1).date()).days

print(f"Test datetime: {test_dt}")
print(f"Epoch seconds: {epoch_seconds}")
print(f"Epoch milliseconds: {epoch_ms}")
print(f"Epoch microseconds: {epoch_us}")
print(f"Epoch nanoseconds: {epoch_ns}")
print(f"Epoch days: {epoch_days}")

# Create test data with 3 rows
# Row 0: Test datetime
# Row 1: Unix epoch (1970-01-01 00:00:00)
# Row 2: Y2K (2000-01-01 00:00:00)
data = {
    "id": [1, 2, 3],
    "ts_s": pa.array([epoch_seconds, 0, 946684800], type=pa.timestamp("s")),
    "ts_ms": pa.array([epoch_ms, 0, 946684800000], type=pa.timestamp("ms")),
    "ts_us": pa.array([epoch_us, 0, 946684800000000], type=pa.timestamp("us")),
    "ts_ns": pa.array([epoch_ns, 0, 946684800000000000], type=pa.timestamp("ns")),
    "date32": pa.array([epoch_days, 0, 10957], type=pa.date32()),
    "date64": pa.array([epoch_ms, 0, 946684800000], type=pa.date64()),
}

# Create PyArrow table
table = pa.table(data)

print("\nPyArrow Schema:")
print(table.schema)

print("\nSample data:")
print(table.to_pandas())

# Write to Lance format
output_path = os.path.join(output_dir, "timestamp_test.lance")

# Use lancedb to write
db = lancedb.connect(output_dir)
if "timestamp_test" in db.table_names():
    db.drop_table("timestamp_test")
tbl = db.create_table("timestamp_test", table)

print(f"\nWrote Lance file to: {output_path}")

# Verify by reading back
read_table = tbl.to_arrow()
print("\nVerification - read back schema:")
print(read_table.schema)
print("\nVerification - read back data:")
print(read_table.to_pandas())
