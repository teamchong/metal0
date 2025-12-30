"""
PyArrow compatibility tests for lanceql.parquet

These tests verify that lanceql.parquet is a drop-in replacement for pyarrow.parquet.
Tests write files using pyarrow and read using lanceql to prove compatibility.
"""

import io
import tempfile
from pathlib import Path

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq_arrow  # Real PyArrow for writing
import pytest

# Import metal0.lanceql.parquet as pq (the drop-in replacement)
import metal0.lanceql.parquet as pq


class TestReadTable:
    """Test pq.read_table() compatibility."""

    def test_read_simple_table(self, tmp_path):
        """Basic table reading."""
        table = pa.table({'a': [1, 2, 3], 'b': [4.0, 5.0, 6.0]})
        path = tmp_path / 'simple.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path)
        assert result.equals(table)

    def test_read_table_with_columns(self, tmp_path):
        """Read specific columns."""
        table = pa.table({'a': [1, 2, 3], 'b': [4.0, 5.0, 6.0], 'c': ['x', 'y', 'z']})
        path = tmp_path / 'multicol.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path, columns=['a', 'c'])
        expected = pa.table({'a': [1, 2, 3], 'c': ['x', 'y', 'z']})
        assert result.equals(expected)

    def test_read_table_string_path(self, tmp_path):
        """Read using string path."""
        table = pa.table({'x': [1, 2, 3]})
        path = tmp_path / 'strpath.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(str(path))
        assert result.equals(table)

    def test_read_table_bytes_buffer(self):
        """Read from bytes buffer."""
        table = pa.table({'val': [10, 20, 30]})
        buf = io.BytesIO()
        pq_arrow.write_table(table, buf)
        buf.seek(0)
        data = buf.read()

        result = pq.read_table(data)
        assert result.equals(table)


class TestParquetFile:
    """Test pq.ParquetFile class compatibility."""

    def test_basic_read(self, tmp_path):
        """Basic ParquetFile reading."""
        table = pa.table({'a': range(100), 'b': range(100, 200)})
        path = tmp_path / 'file.parquet'
        pq_arrow.write_table(table, path)

        pf = pq.ParquetFile(path)
        result = pf.read()
        assert result.equals(table)
        pf.close()

    def test_context_manager(self, tmp_path):
        """ParquetFile as context manager."""
        table = pa.table({'x': [1, 2, 3]})
        path = tmp_path / 'ctx.parquet'
        pq_arrow.write_table(table, path)

        with pq.ParquetFile(path) as pf:
            result = pf.read()
            assert result.equals(table)

    def test_schema_property(self, tmp_path):
        """Access schema property."""
        table = pa.table({'int_col': pa.array([1, 2], type=pa.int64()),
                         'str_col': pa.array(['a', 'b'])})
        path = tmp_path / 'schema.parquet'
        pq_arrow.write_table(table, path)

        with pq.ParquetFile(path) as pf:
            schema = pf.schema
            assert 'int_col' in schema.names
            assert 'str_col' in schema.names

    def test_metadata_property(self, tmp_path):
        """Access metadata property."""
        table = pa.table({'a': range(1000)})
        path = tmp_path / 'meta.parquet'
        pq_arrow.write_table(table, path)

        with pq.ParquetFile(path) as pf:
            metadata = pf.metadata
            assert metadata.num_rows == 1000
            assert metadata.num_columns == 1

    def test_num_row_groups(self, tmp_path):
        """Access num_row_groups."""
        table = pa.table({'a': range(10000)})
        path = tmp_path / 'rowgroups.parquet'
        pq_arrow.write_table(table, path, row_group_size=2500)

        with pq.ParquetFile(path) as pf:
            assert pf.num_row_groups == 4

    def test_read_row_group(self, tmp_path):
        """Read single row group."""
        table = pa.table({'a': range(1000)})
        path = tmp_path / 'rg.parquet'
        pq_arrow.write_table(table, path, row_group_size=250)

        with pq.ParquetFile(path) as pf:
            rg0 = pf.read_row_group(0)
            assert rg0.num_rows == 250
            assert rg0['a'][0].as_py() == 0

    def test_read_row_groups(self, tmp_path):
        """Read multiple row groups."""
        table = pa.table({'a': range(1000)})
        path = tmp_path / 'rgs.parquet'
        pq_arrow.write_table(table, path, row_group_size=250)

        with pq.ParquetFile(path) as pf:
            result = pf.read_row_groups([0, 2])
            assert result.num_rows == 500

    def test_iter_batches(self, tmp_path):
        """Iterate over batches."""
        table = pa.table({'a': range(1000)})
        path = tmp_path / 'batches.parquet'
        pq_arrow.write_table(table, path)

        with pq.ParquetFile(path) as pf:
            batches = list(pf.iter_batches(batch_size=300))
            total_rows = sum(b.num_rows for b in batches)
            assert total_rows == 1000

    def test_iter_batches_with_columns(self, tmp_path):
        """Iterate with column selection."""
        table = pa.table({'a': range(100), 'b': range(100, 200)})
        path = tmp_path / 'batch_cols.parquet'
        pq_arrow.write_table(table, path)

        with pq.ParquetFile(path) as pf:
            batches = list(pf.iter_batches(batch_size=50, columns=['a']))
            assert all(b.num_columns == 1 for b in batches)
            assert all('a' in b.schema.names for b in batches)


class TestReadMetadata:
    """Test pq.read_metadata() compatibility."""

    def test_read_metadata(self, tmp_path):
        """Read metadata without reading data."""
        table = pa.table({'x': range(500)})
        path = tmp_path / 'meta.parquet'
        pq_arrow.write_table(table, path)

        metadata = pq.read_metadata(path)
        assert metadata.num_rows == 500
        assert metadata.num_columns == 1


class TestReadSchema:
    """Test pq.read_schema() compatibility."""

    def test_read_schema(self, tmp_path):
        """Read schema without reading data."""
        table = pa.table({'int_col': pa.array([1, 2], type=pa.int32()),
                         'float_col': pa.array([1.0, 2.0], type=pa.float64())})
        path = tmp_path / 'schema.parquet'
        pq_arrow.write_table(table, path)

        schema = pq.read_schema(path)
        assert len(schema) == 2
        assert 'int_col' in schema.names
        assert 'float_col' in schema.names


class TestDataTypes:
    """Test reading various data types."""

    def test_integers(self, tmp_path):
        """Read integer columns."""
        table = pa.table({
            'int8': pa.array([1, 2, 3], type=pa.int8()),
            'int16': pa.array([1, 2, 3], type=pa.int16()),
            'int32': pa.array([1, 2, 3], type=pa.int32()),
            'int64': pa.array([1, 2, 3], type=pa.int64()),
        })
        path = tmp_path / 'ints.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path)
        assert result.equals(table)

    def test_unsigned_integers(self, tmp_path):
        """Read unsigned integer columns."""
        table = pa.table({
            'uint8': pa.array([1, 2, 3], type=pa.uint8()),
            'uint16': pa.array([1, 2, 3], type=pa.uint16()),
            'uint32': pa.array([1, 2, 3], type=pa.uint32()),
            'uint64': pa.array([1, 2, 3], type=pa.uint64()),
        })
        path = tmp_path / 'uints.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path)
        assert result.equals(table)

    def test_floats(self, tmp_path):
        """Read float columns."""
        table = pa.table({
            'float32': pa.array([1.0, 2.0, 3.0], type=pa.float32()),
            'float64': pa.array([1.0, 2.0, 3.0], type=pa.float64()),
        })
        path = tmp_path / 'floats.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path)
        assert result.equals(table)

    def test_strings(self, tmp_path):
        """Read string columns."""
        table = pa.table({
            'str': ['hello', 'world', 'test'],
            'large_str': pa.array(['a' * 1000, 'b' * 1000, 'c' * 1000], type=pa.large_string()),
        })
        path = tmp_path / 'strings.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path)
        assert result['str'].to_pylist() == ['hello', 'world', 'test']

    def test_booleans(self, tmp_path):
        """Read boolean columns."""
        table = pa.table({'bool': [True, False, True, False]})
        path = tmp_path / 'bools.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path)
        assert result.equals(table)

    def test_nulls(self, tmp_path):
        """Read columns with nulls."""
        table = pa.table({
            'nullable_int': pa.array([1, None, 3], type=pa.int64()),
            'nullable_str': pa.array(['a', None, 'c']),
        })
        path = tmp_path / 'nulls.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path)
        assert result['nullable_int'].to_pylist() == [1, None, 3]
        assert result['nullable_str'].to_pylist() == ['a', None, 'c']

    def test_nested_types(self, tmp_path):
        """Read nested types (lists, structs)."""
        table = pa.table({
            'list_col': [[1, 2], [3, 4, 5], [6]],
            'struct_col': [{'a': 1, 'b': 'x'}, {'a': 2, 'b': 'y'}, {'a': 3, 'b': 'z'}],
        })
        path = tmp_path / 'nested.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path)
        assert result['list_col'].to_pylist() == [[1, 2], [3, 4, 5], [6]]


class TestLargeFiles:
    """Test reading larger files."""

    def test_large_row_count(self, tmp_path):
        """Read file with many rows."""
        n = 100000
        table = pa.table({
            'id': range(n),
            'value': np.random.randn(n),
        })
        path = tmp_path / 'large.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path)
        assert result.num_rows == n

    def test_many_columns(self, tmp_path):
        """Read file with many columns."""
        n_cols = 100
        data = {f'col_{i}': range(100) for i in range(n_cols)}
        table = pa.table(data)
        path = tmp_path / 'wide.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path)
        assert result.num_columns == n_cols


class TestEdgeCases:
    """Test edge cases and error handling."""

    def test_empty_table(self, tmp_path):
        """Read empty table."""
        schema = pa.schema([('a', pa.int64()), ('b', pa.string())])
        table = pa.table({'a': pa.array([], type=pa.int64()),
                         'b': pa.array([], type=pa.string())})
        path = tmp_path / 'empty.parquet'
        pq_arrow.write_table(table, path)

        result = pq.read_table(path)
        assert result.num_rows == 0
        assert result.num_columns == 2

    def test_file_not_found(self):
        """Error on missing file."""
        with pytest.raises((FileNotFoundError, OSError)):
            pq.read_table('/nonexistent/path.parquet')

    def test_invalid_file(self, tmp_path):
        """Error on invalid parquet file."""
        path = tmp_path / 'invalid.parquet'
        path.write_text('not a parquet file')

        with pytest.raises((pa.ArrowInvalid, ValueError, Exception)):
            pq.read_table(path)


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
