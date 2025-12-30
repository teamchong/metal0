#!/usr/bin/env python3
"""
Run all Lance vs Parquet benchmarks.
"""

import subprocess
import sys
import os

BENCHMARKS = [
    ("01_time_travel.py", "Time Travel"),
    ("02_updates.py", "Updates & Deletes"),
    ("03_vector_search.py", "Vector Search (Lance-only feature)"),
    ("04_query_speed.py", "Query Speed"),
    ("05_compression.py", "Compression"),
    ("06_read_performance.py", "LanceQL vs lancedb - Read Performance"),
]

def main():
    print("=" * 70)
    print("Lance vs Parquet - Full Benchmark Suite")
    print("=" * 70)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    failed = []

    for script, name in BENCHMARKS:
        print(f"\n{'=' * 70}")
        print(f"Running: {name}")
        print("=" * 70)

        script_path = os.path.join(script_dir, script)
        result = subprocess.run(
            [sys.executable, script_path],
            capture_output=False
        )

        if result.returncode != 0:
            failed.append(name)
            print(f"\n❌ {name} failed!")

    print("\n" + "=" * 70)
    print("Summary")
    print("=" * 70)

    if failed:
        print(f"\n❌ Failed benchmarks: {', '.join(failed)}")
    else:
        print("\n✅ All benchmarks completed successfully!")

    print("""
┌─────────────────────────────────────────────────────────────────────┐
│                    Lance vs Parquet Summary                         │
├─────────────────────────────────────────────────────────────────────┤
│ Feature              │ Lance          │ Parquet                     │
├──────────────────────┼────────────────┼─────────────────────────────┤
│ Time Travel          │ ✅ Native      │ ❌ Manual file copies       │
│ Row Updates          │ ✅ O(1)        │ ❌ Full rewrite             │
│ Row Deletes          │ ✅ O(1)        │ ❌ Full rewrite             │
│ Vector Search        │ ✅ Native ANN  │ ❌ External (FAISS, etc.)   │
│ Query Speed          │ ✅ Fast        │ ✅ Fast                     │
│ Compression          │ ✅ Good        │ ✅ Good                     │
│ ACID Transactions    │ ✅ Yes         │ ❌ No                       │
│ Schema Evolution     │ ✅ Yes         │ ✅ Yes                      │
└──────────────────────┴────────────────┴─────────────────────────────┘

💡 When to use Lance over Parquet:
   • You need version control / time travel
   • You have frequent updates or deletes
   • You need vector similarity search
   • You want a single format for everything

💡 When Parquet is fine:
   • Append-only data (logs, events)
   • Pure analytics with no updates
   • Existing Parquet ecosystem integration
""")

if __name__ == "__main__":
    main()
