"""Tests for lanceql.parquet module.

These tests verify PyArrow-compatible API for reading Lance files.
Based on pyarrow.parquet test patterns from apache/arrow.
"""

import json
from pathlib import Path
import pytest
import numpy as np

import metal0.lanceql.parquet as pq

# Path to test fixtures
FIXTURES_DIR = Path(__file__).parent.parent.parent / "tests" / "fixtures"


def load_expected(name: str) -> dict:
    """Load expected values from JSON file."""
    path = FIXTURES_DIR / f"{name}.expected.json"
    if path.exists():
        with open(path) as f:
            return json.load(f)
    return {}


class TestReadTable:
    """Tests for pq.read_table()."""

    def test_read_simple_int64(self):
        """Test reading a simple int64 column."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        table = pq.read_table(path)
        assert table is not None
        assert table.num_rows == 5

    def test_read_simple_float64(self):
        """Test reading a simple float64 column."""
        path = FIXTURES_DIR / "simple_float64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        table = pq.read_table(path)
        assert table is not None
        assert table.num_rows == 5

    def test_read_empty_file(self):
        """Test reading an empty Lance file."""
        path = FIXTURES_DIR / "empty.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        table = pq.read_table(path)
        assert table is not None
        assert table.num_rows == 0

    def test_read_mixed_types(self):
        """Test reading a file with multiple column types."""
        path = FIXTURES_DIR / "mixed_types.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        table = pq.read_table(path)
        assert table is not None
        assert table.num_columns >= 1


class TestParquetFile:
    """Tests for pq.ParquetFile class."""

    def test_open_and_read(self):
        """Test opening a file and reading it."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        with pq.ParquetFile(path) as pf:
            assert pf.num_row_groups >= 1
            table = pf.read()
            assert table.num_rows == 5

    def test_metadata(self):
        """Test reading file metadata."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        with pq.ParquetFile(path) as pf:
            metadata = pf.metadata
            assert metadata.num_rows == 5
            assert metadata.num_columns >= 1
            assert metadata.num_row_groups >= 1

    def test_schema(self):
        """Test reading file schema."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        with pq.ParquetFile(path) as pf:
            schema = pf.schema
            assert schema is not None
            assert len(schema) >= 1

    def test_iter_batches(self):
        """Test iterating over record batches."""
        path = FIXTURES_DIR / "large.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        batches = []
        with pq.ParquetFile(path) as pf:
            for batch in pf.iter_batches(batch_size=100):
                batches.append(batch)

        assert len(batches) >= 1
        total_rows = sum(batch.num_rows for batch in batches)
        assert total_rows > 0

    def test_read_row_group(self):
        """Test reading a specific row group."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        with pq.ParquetFile(path) as pf:
            table = pf.read_row_group(0)
            assert table.num_rows == 5


class TestReadMetadata:
    """Tests for pq.read_metadata()."""

    def test_read_metadata(self):
        """Test reading metadata without reading data."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        metadata = pq.read_metadata(path)
        assert metadata.num_rows == 5
        assert metadata.num_columns >= 1


class TestReadSchema:
    """Tests for pq.read_schema()."""

    def test_read_schema(self):
        """Test reading schema without reading data."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        schema = pq.read_schema(path)
        assert schema is not None
        assert len(schema) >= 1


class TestDataTypes:
    """Tests for various data types."""

    def test_strings(self):
        """Test reading string columns."""
        path = FIXTURES_DIR / "strings_various.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        table = pq.read_table(path)
        assert table is not None

    def test_vectors(self):
        """Test reading vector columns."""
        path = FIXTURES_DIR / "vectors.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        table = pq.read_table(path)
        assert table is not None

    def test_basic_types(self):
        """Test reading various basic types."""
        path = FIXTURES_DIR / "basic_types.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        table = pq.read_table(path)
        assert table is not None


class TestContextManager:
    """Tests for context manager support."""

    def test_context_manager(self):
        """Test using ParquetFile as context manager."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        with pq.ParquetFile(path) as pf:
            table = pf.read()
            assert table.num_rows == 5

    def test_explicit_close(self):
        """Test explicit close."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        pf = pq.ParquetFile(path)
        table = pf.read()
        pf.close()
        assert table.num_rows == 5


class TestColumnSelection:
    """Tests for column selection."""

    def test_select_columns_by_name(self):
        """Test selecting specific columns."""
        path = FIXTURES_DIR / "mixed_types.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        with pq.ParquetFile(path) as pf:
            # Get column names
            schema = pf.schema
            if len(schema) > 1:
                columns = [schema.field(0).name]
                table = pf.read(columns=columns)
                assert table.num_columns == 1


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
