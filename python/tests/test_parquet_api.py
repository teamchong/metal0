#!/usr/bin/env python3
"""
Unit tests for lanceql.parquet drop-in replacement API.

Tests adapted from pyarrow.parquet test suite to ensure correctness.
Reference: https://github.com/apache/arrow/tree/main/python/pyarrow/tests/parquet
"""

import pytest
import tempfile
import os
import numpy as np
import pyarrow as pa
import lancedb

# Import our drop-in replacement
from metal0.lanceql import parquet as pq


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
def sample_table():
    """Create a sample PyArrow table for testing."""
    return pa.table({
        "id": pa.array([1, 2, 3, 4, 5], type=pa.int64()),
        "value": pa.array([1.5, 2.5, 3.5, 4.5, 5.5], type=pa.float64()),
        "name": pa.array(["alice", "bob", "charlie", "david", "eve"]),
    })


@pytest.fixture
def large_table():
    """Create a larger table for testing."""
    np.random.seed(42)
    n = 10000
    return pa.table({
        "id": pa.array(range(n), type=pa.int64()),
        "int_col": pa.array(np.random.randint(0, 1000000, n), type=pa.int64()),
        "float_col": pa.array(np.random.randn(n), type=pa.float64()),
        "str_col": pa.array([f"value_{i % 100}" for i in range(n)]),
    })


@pytest.fixture
def lance_file(sample_table, tmp_path):
    """Create a Lance file from sample table."""
    db_path = tmp_path / "test_db"
    db = lancedb.connect(str(db_path))
    db.create_table("data", sample_table)

    # Find the .lance file
    for root, dirs, files in os.walk(db_path):
        for f in files:
            if f.endswith('.lance'):
                return os.path.join(root, f)
    pytest.fail("Could not create Lance file")


@pytest.fixture
def large_lance_file(large_table, tmp_path):
    """Create a larger Lance file for testing."""
    db_path = tmp_path / "large_db"
    db = lancedb.connect(str(db_path))
    db.create_table("data", large_table)

    for root, dirs, files in os.walk(db_path):
        for f in files:
            if f.endswith('.lance'):
                return os.path.join(root, f)
    pytest.fail("Could not create Lance file")


# ============================================================================
# Test: read_table()
# ============================================================================

class TestReadTable:
    """Tests for pq.read_table() function."""

    def test_read_table_basic(self, lance_file, sample_table):
        """Test basic read_table functionality."""
        result = pq.read_table(lance_file)

        assert isinstance(result, pa.Table)
        assert result.num_rows == sample_table.num_rows
        assert result.num_columns == sample_table.num_columns

    def test_read_table_column_names(self, lance_file):
        """Test that column names are preserved."""
        result = pq.read_table(lance_file)

        assert "id" in result.column_names
        assert "value" in result.column_names
        assert "name" in result.column_names

    def test_read_table_column_types(self, lance_file):
        """Test that column types are correct."""
        result = pq.read_table(lance_file)

        assert result.schema.field("id").type == pa.int64()
        assert result.schema.field("value").type == pa.float64()
        assert result.schema.field("name").type == pa.string()

    def test_read_table_values(self, lance_file, sample_table):
        """Test that values are correctly read."""
        result = pq.read_table(lance_file)

        # Check int64 values
        assert result.column("id").to_pylist() == [1, 2, 3, 4, 5]

        # Check float64 values
        assert result.column("value").to_pylist() == [1.5, 2.5, 3.5, 4.5, 5.5]

        # Check string values
        assert result.column("name").to_pylist() == ["alice", "bob", "charlie", "david", "eve"]

    def test_read_table_column_projection(self, lance_file):
        """Test reading specific columns only."""
        result = pq.read_table(lance_file, columns=["id", "name"])

        assert result.num_columns == 2
        assert "id" in result.column_names
        assert "name" in result.column_names
        assert "value" not in result.column_names

    def test_read_table_single_column(self, lance_file):
        """Test reading a single column."""
        result = pq.read_table(lance_file, columns=["value"])

        assert result.num_columns == 1
        assert result.column_names == ["value"]
        assert result.column("value").to_pylist() == [1.5, 2.5, 3.5, 4.5, 5.5]

    def test_read_table_invalid_source(self):
        """Test that invalid source raises appropriate error."""
        with pytest.raises((TypeError, ValueError, FileNotFoundError)):
            pq.read_table(None)

    def test_read_table_non_existing_file(self):
        """Test that non-existing file raises FileNotFoundError."""
        with pytest.raises((FileNotFoundError, ValueError)):
            pq.read_table("/nonexistent/path/file.lance")

    def test_read_table_large(self, large_lance_file, large_table):
        """Test reading larger files."""
        result = pq.read_table(large_lance_file)

        assert result.num_rows == large_table.num_rows
        assert result.num_columns == large_table.num_columns


# ============================================================================
# Test: ParquetFile class
# ============================================================================

class TestParquetFile:
    """Tests for pq.ParquetFile class."""

    def test_parquet_file_basic(self, lance_file):
        """Test basic ParquetFile creation."""
        pf = pq.ParquetFile(lance_file)
        assert pf is not None
        pf.close()

    def test_parquet_file_context_manager(self, lance_file):
        """Test ParquetFile as context manager."""
        with pq.ParquetFile(lance_file) as pf:
            result = pf.read()
            assert isinstance(result, pa.Table)

    def test_parquet_file_read(self, lance_file, sample_table):
        """Test ParquetFile.read() method."""
        with pq.ParquetFile(lance_file) as pf:
            result = pf.read()

            assert result.num_rows == sample_table.num_rows
            assert result.num_columns == sample_table.num_columns

    def test_parquet_file_read_columns(self, lance_file):
        """Test ParquetFile.read() with column selection."""
        with pq.ParquetFile(lance_file) as pf:
            result = pf.read(columns=["id", "value"])

            assert result.num_columns == 2
            assert "id" in result.column_names
            assert "value" in result.column_names

    def test_parquet_file_schema(self, lance_file):
        """Test ParquetFile.schema property."""
        with pq.ParquetFile(lance_file) as pf:
            schema = pf.schema

            assert isinstance(schema, pa.Schema)
            assert len(schema) == 3
            assert schema.field("id").type == pa.int64()

    def test_parquet_file_schema_arrow(self, lance_file):
        """Test ParquetFile.schema_arrow property (alias)."""
        with pq.ParquetFile(lance_file) as pf:
            assert pf.schema_arrow == pf.schema

    def test_parquet_file_metadata(self, lance_file, sample_table):
        """Test ParquetFile.metadata property."""
        with pq.ParquetFile(lance_file) as pf:
            meta = pf.metadata

            assert meta.num_rows == sample_table.num_rows
            assert meta.num_columns == sample_table.num_columns
            assert meta.num_row_groups >= 1

    def test_parquet_file_num_row_groups(self, lance_file):
        """Test ParquetFile.num_row_groups property."""
        with pq.ParquetFile(lance_file) as pf:
            assert pf.num_row_groups >= 1

    def test_parquet_file_iter_batches(self, lance_file, sample_table):
        """Test ParquetFile.iter_batches() method."""
        with pq.ParquetFile(lance_file) as pf:
            batches = list(pf.iter_batches(batch_size=2))

            assert len(batches) >= 1
            total_rows = sum(len(batch) for batch in batches)
            assert total_rows == sample_table.num_rows

    def test_parquet_file_iter_batches_all_at_once(self, lance_file, sample_table):
        """Test iter_batches with large batch size."""
        with pq.ParquetFile(lance_file) as pf:
            batches = list(pf.iter_batches(batch_size=1000))

            # Should be 1 batch since table is small
            assert len(batches) >= 1
            assert sum(len(b) for b in batches) == sample_table.num_rows

    def test_parquet_file_read_row_group(self, lance_file, sample_table):
        """Test ParquetFile.read_row_group() method."""
        with pq.ParquetFile(lance_file) as pf:
            result = pf.read_row_group(0)

            assert isinstance(result, pa.Table)
            assert result.num_rows == sample_table.num_rows

    def test_parquet_file_read_row_group_invalid(self, lance_file):
        """Test read_row_group with invalid index raises error."""
        with pq.ParquetFile(lance_file) as pf:
            with pytest.raises(IndexError):
                pf.read_row_group(999)

    def test_parquet_file_closed_error(self, lance_file):
        """Test that operations on closed file raise error."""
        pf = pq.ParquetFile(lance_file)
        pf.close()

        with pytest.raises(ValueError):
            pf.read()


# ============================================================================
# Test: read_metadata()
# ============================================================================

class TestReadMetadata:
    """Tests for pq.read_metadata() function."""

    def test_read_metadata_basic(self, lance_file, sample_table):
        """Test basic metadata reading."""
        meta = pq.read_metadata(lance_file)

        assert meta.num_rows == sample_table.num_rows
        assert meta.num_columns == sample_table.num_columns

    def test_read_metadata_row_groups(self, lance_file):
        """Test row group count in metadata."""
        meta = pq.read_metadata(lance_file)

        assert meta.num_row_groups >= 1

    def test_read_metadata_format_version(self, lance_file):
        """Test format version in metadata."""
        meta = pq.read_metadata(lance_file)

        assert hasattr(meta, 'format_version')
        assert isinstance(meta.format_version, str)

    def test_read_metadata_to_dict(self, lance_file):
        """Test metadata to_dict() method."""
        meta = pq.read_metadata(lance_file)

        d = meta.to_dict()
        assert isinstance(d, dict)
        assert "num_rows" in d
        assert "num_columns" in d

    def test_read_metadata_repr(self, lance_file):
        """Test metadata __repr__."""
        meta = pq.read_metadata(lance_file)

        repr_str = repr(meta)
        assert "FileMetaData" in repr_str
        assert "num_rows" in repr_str


# ============================================================================
# Test: read_schema()
# ============================================================================

class TestReadSchema:
    """Tests for pq.read_schema() function."""

    def test_read_schema_basic(self, lance_file):
        """Test basic schema reading."""
        schema = pq.read_schema(lance_file)

        assert isinstance(schema, pa.Schema)
        assert len(schema) == 3

    def test_read_schema_field_names(self, lance_file):
        """Test schema field names."""
        schema = pq.read_schema(lance_file)

        names = schema.names
        assert "id" in names
        assert "value" in names
        assert "name" in names

    def test_read_schema_field_types(self, lance_file):
        """Test schema field types."""
        schema = pq.read_schema(lance_file)

        assert schema.field("id").type == pa.int64()
        assert schema.field("value").type == pa.float64()
        assert schema.field("name").type == pa.string()


# ============================================================================
# Test: Data Type Support
# ============================================================================

class TestDataTypes:
    """Tests for various data type support."""

    @pytest.fixture
    def int_types_table(self):
        """Table with various int types."""
        return pa.table({
            "int64_col": pa.array([1, 2, 3], type=pa.int64()),
        })

    @pytest.fixture
    def float_types_table(self):
        """Table with various float types."""
        return pa.table({
            "float64_col": pa.array([1.1, 2.2, 3.3], type=pa.float64()),
        })

    @pytest.fixture
    def string_table(self):
        """Table with string data."""
        return pa.table({
            "str_col": pa.array(["hello", "world", "test"]),
        })

    def test_int64_roundtrip(self, int_types_table, tmp_path):
        """Test int64 values are preserved."""
        db_path = tmp_path / "int_db"
        db = lancedb.connect(str(db_path))
        db.create_table("data", int_types_table)

        lance_file = None
        for root, dirs, files in os.walk(db_path):
            for f in files:
                if f.endswith('.lance'):
                    lance_file = os.path.join(root, f)
                    break

        result = pq.read_table(lance_file)
        assert result.column("int64_col").to_pylist() == [1, 2, 3]

    def test_float64_roundtrip(self, float_types_table, tmp_path):
        """Test float64 values are preserved."""
        db_path = tmp_path / "float_db"
        db = lancedb.connect(str(db_path))
        db.create_table("data", float_types_table)

        lance_file = None
        for root, dirs, files in os.walk(db_path):
            for f in files:
                if f.endswith('.lance'):
                    lance_file = os.path.join(root, f)
                    break

        result = pq.read_table(lance_file)
        values = result.column("float64_col").to_pylist()
        assert len(values) == 3
        assert abs(values[0] - 1.1) < 0.0001
        assert abs(values[1] - 2.2) < 0.0001
        assert abs(values[2] - 3.3) < 0.0001

    def test_string_roundtrip(self, string_table, tmp_path):
        """Test string values are preserved."""
        db_path = tmp_path / "str_db"
        db = lancedb.connect(str(db_path))
        db.create_table("data", string_table)

        lance_file = None
        for root, dirs, files in os.walk(db_path):
            for f in files:
                if f.endswith('.lance'):
                    lance_file = os.path.join(root, f)
                    break

        result = pq.read_table(lance_file)
        assert result.column("str_col").to_pylist() == ["hello", "world", "test"]

    def test_unicode_strings(self, tmp_path):
        """Test Unicode string support."""
        table = pa.table({
            "text": pa.array(["hello", "世界", "🎉", "café"]),
        })

        db_path = tmp_path / "unicode_db"
        db = lancedb.connect(str(db_path))
        db.create_table("data", table)

        lance_file = None
        for root, dirs, files in os.walk(db_path):
            for f in files:
                if f.endswith('.lance'):
                    lance_file = os.path.join(root, f)
                    break

        result = pq.read_table(lance_file)
        assert result.column("text").to_pylist() == ["hello", "世界", "🎉", "café"]

    def test_empty_strings(self, tmp_path):
        """Test empty string handling."""
        table = pa.table({
            "text": pa.array(["", "hello", "", "world"]),
        })

        db_path = tmp_path / "empty_str_db"
        db = lancedb.connect(str(db_path))
        db.create_table("data", table)

        lance_file = None
        for root, dirs, files in os.walk(db_path):
            for f in files:
                if f.endswith('.lance'):
                    lance_file = os.path.join(root, f)
                    break

        result = pq.read_table(lance_file)
        assert result.column("text").to_pylist() == ["", "hello", "", "world"]


# ============================================================================
# Test: Edge Cases
# ============================================================================

class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    def test_single_row(self, tmp_path):
        """Test reading a table with single row."""
        table = pa.table({"id": [1], "name": ["test"]})

        db_path = tmp_path / "single_db"
        db = lancedb.connect(str(db_path))
        db.create_table("data", table)

        lance_file = None
        for root, dirs, files in os.walk(db_path):
            for f in files:
                if f.endswith('.lance'):
                    lance_file = os.path.join(root, f)
                    break

        result = pq.read_table(lance_file)
        assert result.num_rows == 1
        assert result.column("id").to_pylist() == [1]

    def test_single_column(self, tmp_path):
        """Test reading a table with single column."""
        table = pa.table({"only_col": [1, 2, 3]})

        db_path = tmp_path / "single_col_db"
        db = lancedb.connect(str(db_path))
        db.create_table("data", table)

        lance_file = None
        for root, dirs, files in os.walk(db_path):
            for f in files:
                if f.endswith('.lance'):
                    lance_file = os.path.join(root, f)
                    break

        result = pq.read_table(lance_file)
        assert result.num_columns == 1
        assert result.column_names == ["only_col"]

    def test_many_columns(self, tmp_path):
        """Test reading a table with many columns."""
        data = {f"col_{i}": [i] for i in range(50)}
        table = pa.table(data)

        db_path = tmp_path / "many_cols_db"
        db = lancedb.connect(str(db_path))
        db.create_table("data", table)

        lance_file = None
        for root, dirs, files in os.walk(db_path):
            for f in files:
                if f.endswith('.lance'):
                    lance_file = os.path.join(root, f)
                    break

        result = pq.read_table(lance_file)
        assert result.num_columns == 50

    def test_read_from_bytes(self, lance_file):
        """Test reading from bytes instead of path."""
        with open(lance_file, 'rb') as f:
            data = f.read()

        result = pq.read_table(data)
        assert result.num_rows == 5


# ============================================================================
# Test: Compatibility with PyArrow
# ============================================================================

class TestPyArrowCompatibility:
    """Tests to ensure compatibility with PyArrow workflows."""

    def test_to_pandas(self, lance_file):
        """Test converting result to pandas DataFrame."""
        pytest.importorskip("pandas")

        result = pq.read_table(lance_file)
        df = result.to_pandas()

        assert len(df) == 5
        assert list(df.columns) == ["id", "value", "name"]

    def test_to_pydict(self, lance_file):
        """Test converting result to Python dict."""
        result = pq.read_table(lance_file)
        d = result.to_pydict()

        assert isinstance(d, dict)
        assert d["id"] == [1, 2, 3, 4, 5]
        assert d["name"] == ["alice", "bob", "charlie", "david", "eve"]

    def test_column_iteration(self, lance_file):
        """Test iterating over columns."""
        result = pq.read_table(lance_file)

        columns = list(result.columns)
        assert len(columns) == 3

        for col in columns:
            assert isinstance(col, pa.ChunkedArray)

    def test_schema_equals(self, lance_file):
        """Test schema comparison."""
        result = pq.read_table(lance_file)

        expected_schema = pa.schema([
            pa.field("id", pa.int64()),
            pa.field("value", pa.float64()),
            pa.field("name", pa.string()),
        ])

        assert result.schema.equals(expected_schema)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
