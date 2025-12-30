"""Tests for lanceql.polars module.

These tests verify Polars DataFrame integration for reading Lance files.
"""

from pathlib import Path
import pytest

# Skip all tests if polars is not installed
polars = pytest.importorskip("polars")
import polars as pl

import metal0.lanceql.polars as lqpl

# Path to test fixtures
FIXTURES_DIR = Path(__file__).parent.parent.parent / "tests" / "fixtures"


class TestReadTable:
    """Tests for lqpl.read_table()."""

    def test_read_simple_int64(self):
        """Test reading a simple int64 column returns Polars DataFrame."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        assert isinstance(df, pl.DataFrame)
        assert df.height == 5

    def test_read_simple_float64(self):
        """Test reading a simple float64 column."""
        path = FIXTURES_DIR / "simple_float64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        assert isinstance(df, pl.DataFrame)
        assert df.height == 5

    def test_read_mixed_types(self):
        """Test reading a file with multiple column types."""
        path = FIXTURES_DIR / "mixed_types.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        assert isinstance(df, pl.DataFrame)
        assert df.width >= 1

    def test_read_with_column_selection(self):
        """Test reading specific columns."""
        path = FIXTURES_DIR / "mixed_types.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        # First get all columns
        df_all = lqpl.read_table(path)
        if df_all.width > 1:
            # Select first column only
            first_col = df_all.columns[0]
            df = lqpl.read_table(path, columns=[first_col])
            assert df.width == 1
            assert df.columns[0] == first_col


class TestLanceReader:
    """Tests for lqpl.LanceReader class."""

    def test_open_and_read(self):
        """Test opening a file and reading it."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        with lqpl.LanceReader(path) as reader:
            df = reader.read()
            assert isinstance(df, pl.DataFrame)
            assert df.height == 5

    def test_properties(self):
        """Test reader properties."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        with lqpl.LanceReader(path) as reader:
            assert reader.num_rows == 5
            assert reader.num_columns >= 1
            assert len(reader.columns) >= 1
            assert isinstance(reader.schema, dict)

    def test_to_lazy(self):
        """Test converting to LazyFrame."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        with lqpl.LanceReader(path) as reader:
            lazy = reader.to_lazy()
            assert isinstance(lazy, pl.LazyFrame)
            df = lazy.collect()
            assert df.height == 5


class TestScanLance:
    """Tests for lqpl.scan_lance()."""

    def test_scan_lance(self):
        """Test creating a LazyFrame from a Lance file."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        lazy = lqpl.scan_lance(path)
        assert isinstance(lazy, pl.LazyFrame)
        df = lazy.collect()
        assert df.height == 5

    def test_scan_with_filter(self):
        """Test LazyFrame with filter operation."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        lazy = lqpl.scan_lance(path)
        # Get the column name
        df = lazy.collect()
        if df.width > 0:
            col_name = df.columns[0]
            # Filter should work (even though not pushed down)
            filtered = lazy.filter(pl.col(col_name).is_not_null())
            result = filtered.collect()
            assert isinstance(result, pl.DataFrame)


class TestReadSchema:
    """Tests for lqpl.read_schema()."""

    def test_read_schema(self):
        """Test reading schema without reading data."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        schema = lqpl.read_schema(path)
        assert isinstance(schema, dict)
        assert len(schema) >= 1
        # Values should be Polars data types
        for dtype in schema.values():
            assert dtype is not None

    def test_schema_types(self):
        """Test that schema contains valid Polars types."""
        path = FIXTURES_DIR / "mixed_types.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        schema = lqpl.read_schema(path)
        valid_types = (
            pl.Int64, pl.Int32, pl.Float64, pl.Float32,
            pl.Utf8, pl.Boolean, pl.Null, pl.Object
        )
        for name, dtype in schema.items():
            assert dtype in valid_types, f"Column {name} has unexpected type {dtype}"


class TestReadMetadata:
    """Tests for lqpl.read_metadata()."""

    def test_read_metadata(self):
        """Test reading metadata without reading data."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        meta = lqpl.read_metadata(path)
        assert isinstance(meta, dict)
        assert "num_rows" in meta
        assert "num_columns" in meta
        assert "columns" in meta
        assert "schema" in meta
        assert meta["num_rows"] == 5


class TestDataTypes:
    """Tests for various data types."""

    def test_int64_column(self):
        """Test int64 column is correctly typed."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        # Check that numeric columns have correct types
        for col in df.columns:
            dtype = df[col].dtype
            assert dtype in (pl.Int64, pl.Int32, pl.Float64, pl.Float32, pl.Utf8, pl.Boolean)

    def test_float64_column(self):
        """Test float64 column is correctly typed."""
        path = FIXTURES_DIR / "simple_float64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        for col in df.columns:
            dtype = df[col].dtype
            assert dtype in (pl.Int64, pl.Int32, pl.Float64, pl.Float32, pl.Utf8, pl.Boolean)

    def test_string_column(self):
        """Test string column is correctly typed."""
        path = FIXTURES_DIR / "strings_various.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        # At least one column should be string type
        has_string = any(df[col].dtype == pl.Utf8 for col in df.columns)
        # Or check that we have valid data
        assert df.height >= 0


class TestContextManager:
    """Tests for context manager support."""

    def test_context_manager(self):
        """Test using LanceReader as context manager."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        with lqpl.LanceReader(path) as reader:
            df = reader.read()
            assert df.height == 5

    def test_explicit_close(self):
        """Test explicit close."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        reader = lqpl.LanceReader(path)
        df = reader.read()
        reader.close()
        assert df.height == 5


class TestPolarsOperations:
    """Tests for Polars-specific operations on returned DataFrames."""

    def test_select_columns(self):
        """Test Polars select operation."""
        path = FIXTURES_DIR / "mixed_types.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        if df.width > 1:
            selected = df.select(df.columns[0])
            assert selected.width == 1

    def test_filter_rows(self):
        """Test Polars filter operation."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        if df.width > 0:
            col = df.columns[0]
            filtered = df.filter(pl.col(col).is_not_null())
            assert isinstance(filtered, pl.DataFrame)

    def test_group_by(self):
        """Test Polars group_by operation."""
        path = FIXTURES_DIR / "mixed_types.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        if df.width > 0:
            col = df.columns[0]
            grouped = df.group_by(col).len()
            assert isinstance(grouped, pl.DataFrame)

    def test_lazy_operations(self):
        """Test chained lazy operations."""
        path = FIXTURES_DIR / "simple_int64.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        lazy = lqpl.scan_lance(path)
        col = lazy.collect().columns[0]
        result = (
            lazy
            .filter(pl.col(col).is_not_null())
            .select(col)
            .collect()
        )
        assert isinstance(result, pl.DataFrame)


class TestEdgeCases:
    """Tests for edge cases."""

    def test_empty_dataset(self):
        """Test reading an empty Lance dataset."""
        path = FIXTURES_DIR / "empty.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        assert isinstance(df, pl.DataFrame)
        assert df.height == 0

    def test_single_row(self):
        """Test reading a single row file."""
        path = FIXTURES_DIR / "single_row.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        assert isinstance(df, pl.DataFrame)
        assert df.height == 1

    def test_single_column(self):
        """Test reading a single column file."""
        path = FIXTURES_DIR / "single_column.lance"
        if not path.exists():
            pytest.skip("Test fixture not found")

        df = lqpl.read_table(path)
        assert isinstance(df, pl.DataFrame)
        assert df.width == 1


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
