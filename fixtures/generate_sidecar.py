#!/usr/bin/env python3
"""
Generate sidecar manifest (.meta.json) for Lance datasets.

This script creates a JSON file with pre-calculated metadata that browsers
can fetch in parallel with the manifest, reducing RTTs for column info.

Usage:
    python generate_sidecar.py <dataset_path> [output_path]

Example:
    # Local dataset
    python generate_sidecar.py /path/to/images.lance
    # Creates /path/to/images.lance/.meta.json

    python generate_sidecar.py /path/to/images.lance ./meta.json
    # Creates ./meta.json

    # Remote dataset (HTTP/S3)
    python generate_sidecar.py https://data.metal0.dev/laion-1m/images.lance ./meta.json
    python generate_sidecar.py s3://bucket/dataset.lance ./meta.json

The sidecar file contains:
- Schema with column names, types, and field IDs
- Fragment info with row counts and data file paths
- Column statistics (min/max/null_count where available)
- Version info for cache invalidation
"""

import json
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import lance
import pyarrow as pa


def arrow_type_to_string(arrow_type: pa.DataType) -> str:
    """Convert PyArrow type to simple string representation."""
    if pa.types.is_int64(arrow_type):
        return "int64"
    elif pa.types.is_int32(arrow_type):
        return "int32"
    elif pa.types.is_int16(arrow_type):
        return "int16"
    elif pa.types.is_int8(arrow_type):
        return "int8"
    elif pa.types.is_float64(arrow_type):
        return "float64"
    elif pa.types.is_float32(arrow_type):
        return "float32"
    elif pa.types.is_string(arrow_type) or pa.types.is_large_string(arrow_type):
        return "string"
    elif pa.types.is_boolean(arrow_type):
        return "boolean"
    elif pa.types.is_fixed_size_list(arrow_type):
        inner = arrow_type_to_string(arrow_type.value_type)
        return f"vector[{arrow_type.list_size}]<{inner}>"
    elif pa.types.is_list(arrow_type):
        inner = arrow_type_to_string(arrow_type.value_type)
        return f"list<{inner}>"
    elif pa.types.is_struct(arrow_type):
        return "struct"
    else:
        return str(arrow_type)


def get_column_stats(ds: lance.LanceDataset, col_name: str) -> dict[str, Any]:
    """Get statistics for a column if available (dataset-level)."""
    stats = {}
    try:
        # Try to compute basic stats for numeric columns
        schema = ds.schema
        field = schema.field(col_name)

        if pa.types.is_integer(field.type) or pa.types.is_floating(field.type):
            # Sample first 1000 rows for stats
            sample = ds.head(1000).column(col_name)
            if len(sample) > 0:
                non_null = [v.as_py() for v in sample if v.is_valid]
                if non_null:
                    stats["min"] = min(non_null)
                    stats["max"] = max(non_null)
                    stats["null_count_sample"] = len(sample) - len(non_null)
    except Exception:
        pass
    return stats


def get_fragment_column_stats(frag, col_name: str, field_type: pa.DataType) -> dict[str, Any] | None:
    """Get statistics for a column within a specific fragment."""
    try:
        # Only compute stats for numeric and string columns
        if not (pa.types.is_integer(field_type) or
                pa.types.is_floating(field_type) or
                pa.types.is_string(field_type) or
                pa.types.is_large_string(field_type)):
            return None

        # Read the column from this fragment
        scanner = frag.scanner(columns=[col_name])
        table = scanner.to_table()

        if table.num_rows == 0:
            return None

        col = table.column(col_name)
        stats = {
            "rowCount": table.num_rows,
            "nullCount": col.null_count,
        }

        # For numeric columns, compute min/max
        if pa.types.is_integer(field_type) or pa.types.is_floating(field_type):
            # Use pyarrow compute for efficient min/max
            import pyarrow.compute as pc
            min_val = pc.min(col).as_py()
            max_val = pc.max(col).as_py()
            if min_val is not None:
                stats["min"] = min_val
            if max_val is not None:
                stats["max"] = max_val

        # For string columns, just track null count (min/max less useful)
        # Could add distinct count later for cardinality estimation

        return stats
    except Exception as e:
        print(f"  Warning: Could not compute stats for {col_name}: {e}")
        return None


def compute_fragment_statistics(frag, schema: pa.Schema, verbose: bool = False) -> dict[str, dict]:
    """Compute statistics for all columns in a fragment."""
    statistics = {}

    for field in schema:
        # Skip vector/list columns (too expensive to compute stats)
        if (pa.types.is_fixed_size_list(field.type) or
            pa.types.is_list(field.type) or
            pa.types.is_struct(field.type)):
            continue

        stats = get_fragment_column_stats(frag, field.name, field.type)
        if stats:
            statistics[field.name] = stats
            if verbose:
                print(f"    {field.name}: min={stats.get('min')}, max={stats.get('max')}, nulls={stats.get('nullCount')}")

    return statistics


def get_storage_options(dataset_path: str) -> dict | None:
    """Get storage options for S3/R2 access if needed."""
    parsed = urlparse(dataset_path)
    if parsed.scheme != "s3":
        return None

    # Check for R2 endpoint in environment or use known endpoint
    import subprocess

    # Try to get R2 credentials from aws profile
    try:
        result = subprocess.run(
            ["aws", "configure", "get", "aws_access_key_id", "--profile", "r2"],
            capture_output=True,
            text=True,
        )
        access_key = result.stdout.strip()

        result = subprocess.run(
            ["aws", "configure", "get", "aws_secret_access_key", "--profile", "r2"],
            capture_output=True,
            text=True,
        )
        secret_key = result.stdout.strip()

        if access_key and secret_key:
            return {
                "endpoint": "https://36498dc359676cbbcf8c3616e6c07e94.r2.cloudflarestorage.com",
                "region": "auto",
                "aws_access_key_id": access_key,
                "aws_secret_access_key": secret_key,
            }
    except Exception:
        pass

    return None


def generate_sidecar(dataset_path: str, output_path: str | None = None, compute_stats: bool = True) -> dict:
    """Generate sidecar manifest for a Lance dataset.

    Args:
        dataset_path: Path to Lance dataset (local, HTTP, or S3)
        output_path: Output path for .meta.json (defaults to dataset/.meta.json)
        compute_stats: If True, compute per-fragment column statistics (slower but enables fragment pruning)
    """
    storage_options = get_storage_options(dataset_path)
    if storage_options:
        ds = lance.dataset(dataset_path, storage_options=storage_options)
    else:
        ds = lance.dataset(dataset_path)

    # Schema info
    schema_info = []
    for i, field in enumerate(ds.schema):
        col_info = {
            "name": field.name,
            "type": arrow_type_to_string(field.type),
            "index": i,
        }

        # Add dataset-level stats for numeric columns
        stats = get_column_stats(ds, field.name)
        if stats:
            col_info["stats"] = stats

        schema_info.append(col_info)

    # Fragment info with per-fragment statistics
    fragments_info = []
    fragments = list(ds.get_fragments())
    total_frags = len(fragments)

    for idx, frag in enumerate(fragments):
        frag_info = {
            "id": frag.fragment_id,
            "num_rows": frag.count_rows(),
            "physical_rows": frag.metadata.num_rows,
        }

        # Get data file paths
        data_files = []
        for df in frag.data_files():
            data_files.append(df.path())
        if data_files:
            frag_info["data_files"] = data_files

        # Check for deletion file
        if frag.deletion_file():
            frag_info["has_deletions"] = True
            frag_info["deleted_rows"] = frag.metadata.num_rows - frag.count_rows()

        # Compute per-fragment column statistics
        if compute_stats:
            print(f"  Computing stats for fragment {idx + 1}/{total_frags} (id={frag.fragment_id})...")
            statistics = compute_fragment_statistics(frag, ds.schema, verbose=False)
            if statistics:
                frag_info["statistics"] = statistics

        fragments_info.append(frag_info)

    # Build sidecar manifest
    sidecar = {
        "version": 2,  # Bumped version for statistics support
        "lance_version": ds.version,
        "schema": schema_info,
        "fragments": fragments_info,
        "total_rows": ds.count_rows(),
        "num_columns": len(ds.schema),
        "has_statistics": compute_stats,
    }

    # Determine output path
    if output_path is None:
        output_path = Path(dataset_path) / ".meta.json"
    else:
        output_path = Path(output_path)

    # Write sidecar file
    with open(output_path, "w") as f:
        json.dump(sidecar, f, indent=2)

    print(f"Generated sidecar manifest: {output_path}")
    print(f"  Schema: {len(schema_info)} columns")
    print(f"  Fragments: {len(fragments_info)}")
    print(f"  Total rows: {sidecar['total_rows']:,}")
    if compute_stats:
        stats_cols = sum(1 for f in fragments_info if f.get("statistics"))
        print(f"  Fragments with statistics: {stats_cols}")

    return sidecar


def is_remote_path(path: str) -> bool:
    """Check if path is a remote URL (HTTP, S3, etc.)."""
    parsed = urlparse(path)
    return parsed.scheme in ("http", "https", "s3", "gs", "az")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        print("\nError: Please provide a dataset path")
        sys.exit(1)

    dataset_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else None

    # For remote paths, require explicit output path
    if is_remote_path(dataset_path):
        if output_path is None:
            print("Error: Remote datasets require an explicit output path")
            print(f"  Example: python {sys.argv[0]} {dataset_path} ./meta.json")
            sys.exit(1)
    elif not Path(dataset_path).exists():
        print(f"Error: Dataset not found: {dataset_path}")
        sys.exit(1)

    generate_sidecar(dataset_path, output_path)


if __name__ == "__main__":
    main()
