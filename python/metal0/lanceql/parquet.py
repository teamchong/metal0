"""PyArrow-compatible Parquet/Lance file reading API.

This module provides a drop-in replacement for pyarrow.parquet,
supporting both .lance and .parquet files.

Usage:
    import lanceql.parquet as pq

    # Read entire file as table
    table = pq.read_table('data.lance')

    # Use ParquetFile for more control
    pf = pq.ParquetFile('data.lance')
    table = pf.read()

    # Iterate in batches
    for batch in pf.iter_batches(batch_size=1000):
        process(batch)
"""

from pathlib import Path
from typing import Union, Optional, List, Iterator, Any
import warnings
import pyarrow as pa
import numpy as np

from ._native import LanceFile


class FileMetaData:
    """Metadata for a Parquet/Lance file."""

    def __init__(
        self,
        num_columns: int,
        num_rows: int,
        num_row_groups: int,
        schema: "pa.Schema",
        version: tuple,
    ):
        self._num_columns = num_columns
        self._num_rows = num_rows
        self._num_row_groups = num_row_groups
        self._schema = schema
        self._version = version

    @property
    def num_columns(self) -> int:
        """Number of columns in the file."""
        return self._num_columns

    @property
    def num_rows(self) -> int:
        """Total number of rows in the file."""
        return self._num_rows

    @property
    def num_row_groups(self) -> int:
        """Number of row groups in the file."""
        return self._num_row_groups

    @property
    def schema(self) -> "pa.Schema":
        """Arrow schema of the file."""
        return self._schema

    @property
    def format_version(self) -> str:
        """Format version string."""
        return f"{self._version[0]}.{self._version[1]}"

    def to_dict(self) -> dict:
        """Convert metadata to dictionary."""
        return {
            "num_columns": self._num_columns,
            "num_rows": self._num_rows,
            "num_row_groups": self._num_row_groups,
            "format_version": self.format_version,
        }

    def __repr__(self) -> str:
        return (
            f"<FileMetaData num_columns={self._num_columns} "
            f"num_rows={self._num_rows} num_row_groups={self._num_row_groups}>"
        )


class RowGroupMetaData:
    """Metadata for a single row group."""

    def __init__(self, index: int, num_rows: int, num_columns: int):
        self._index = index
        self._num_rows = num_rows
        self._num_columns = num_columns

    @property
    def num_rows(self) -> int:
        """Number of rows in this row group."""
        return self._num_rows

    @property
    def num_columns(self) -> int:
        """Number of columns in this row group."""
        return self._num_columns

    def __repr__(self) -> str:
        return f"<RowGroupMetaData index={self._index} num_rows={self._num_rows}>"


class ParquetFile:
    """Reader for Parquet/Lance files.

    Provides PyArrow-compatible API for reading Lance columnar files.
    """

    def __init__(
        self,
        source: Union[str, Path, bytes],
        *,
        memory_map: bool = False,
        buffer_size: int = 0,
        **kwargs,
    ):
        """Open a Parquet/Lance file.

        Args:
            source: File path or bytes containing file data.
            memory_map: Ignored (for PyArrow compatibility).
            buffer_size: Ignored (for PyArrow compatibility).
            **kwargs: Additional arguments (ignored for compatibility).
        """
        self._source = source
        self._closed = False
        self._use_fallback = False
        self._fallback = None
        self._is_empty = False
        self._file = None

        # Load file data
        if isinstance(source, bytes):
            self._data = source
            self._path = None
        else:
            self._path = Path(source)
            if self._path.is_dir():
                # Lance dataset directory - find data file
                data_files = list(self._path.glob("**/*.lance"))
                if not data_files:
                    # Empty Lance dataset
                    self._is_empty = True
                    self._data = b""
                    self._num_columns = 0
                    self._num_rows = 0
                    self._schema = pa.schema([])
                    self._column_names = []
                    self._column_types = []
                    return
                self._path = data_files[0]
            self._data = self._path.read_bytes()

        # Check for Parquet magic number "PAR1" at start - delegate to PyArrow
        is_parquet = (
            (self._path and self._path.suffix == ".parquet") or
            (len(self._data) >= 4 and self._data[:4] == b'PAR1')
        )
        if is_parquet:
            import pyarrow.parquet as pq
            import io

            if self._path:
                self._fallback = pq.ParquetFile(str(self._path))
            else:
                # Bytes input
                self._fallback = pq.ParquetFile(io.BytesIO(self._data))
            self._use_fallback = True
            return

        # Validate Lance file magic
        if len(self._data) < 40 or self._data[-4:] != b'LANC':
            raise ValueError("Not a valid Lance file")

        # Open with native library
        self._file = LanceFile(self._data)

        # Get metadata
        self._num_columns = self._file.column_count()
        self._num_rows = self._file.row_count(0) if self._num_columns > 0 else 0

        # Get REAL column names and types
        self._column_names = [
            self._file.column_name(i) for i in range(self._num_columns)
        ]
        self._column_types = [
            self._file.column_type(i) for i in range(self._num_columns)
        ]

        # Filter to only valid columns (non-empty names and types)
        # This handles nested fields, schema mismatches, or unsupported structures
        self._valid_column_indices = [
            i for i in range(self._num_columns)
            if self._column_names[i] and self._column_types[i]
        ]
        self._num_valid_columns = len(self._valid_column_indices)

        # Warn if columns were skipped
        skipped_count = self._num_columns - self._num_valid_columns
        if skipped_count > 0:
            warnings.warn(
                f"Skipped {skipped_count} column(s) with empty names or types "
                f"(likely nested fields or schema mismatches)",
                UserWarning,
                stacklevel=2
            )

        self._schema = self._infer_schema()

    def _infer_schema(self) -> pa.Schema:
        """Infer Arrow schema from Lance file."""
        fields = []
        # Use only valid column indices (non-empty names and types)
        for i in self._valid_column_indices:
            name = self._column_names[i]
            col_type = self._column_types[i]

            # Map Lance types to PyArrow types
            if col_type in ("int64", "Int64"):
                pa_type = pa.int64()
            elif col_type in ("float64", "double", "Float64"):
                pa_type = pa.float64()
            elif col_type in ("int32", "Int32"):
                pa_type = pa.int32()
            elif col_type in ("float32", "Float32"):
                pa_type = pa.float32()
            elif col_type in ("string", "utf8", "String"):
                pa_type = pa.string()
            elif col_type in ("bool", "Boolean"):
                pa_type = pa.bool_()
            else:
                # Unknown/unsupported type - use null type as placeholder
                pa_type = pa.null()

            fields.append(pa.field(name, pa_type))

        return pa.schema(fields)

    @property
    def schema(self) -> pa.Schema:
        """Arrow schema of the file."""
        if self._use_fallback:
            return self._fallback.schema
        return self._schema

    @property
    def schema_arrow(self) -> pa.Schema:
        """Arrow schema (alias for schema)."""
        return self.schema

    @property
    def metadata(self) -> FileMetaData:
        """File metadata."""
        if self._use_fallback:
            fm = self._fallback.metadata
            return FileMetaData(
                num_columns=fm.num_columns,
                num_rows=fm.num_rows,
                num_row_groups=fm.num_row_groups,
                schema=self._fallback.schema,
                version=(2, 0),
            )
        if self._is_empty:
            return FileMetaData(
                num_columns=0,
                num_rows=0,
                num_row_groups=0,
                schema=pa.schema([]),
                version=(2, 0),
            )
        return FileMetaData(
            num_columns=self._num_valid_columns,  # Only count valid columns
            num_rows=self._num_rows,
            num_row_groups=1,  # Lance doesn't have row groups in the same way
            schema=self._schema,
            version=(2, 0),  # Lance file format version
        )

    @property
    def num_row_groups(self) -> int:
        """Number of row groups."""
        if self._use_fallback:
            return self._fallback.metadata.num_row_groups
        return 1

    def read(
        self,
        columns: Optional[List[str]] = None,
        use_threads: bool = True,
        use_pandas_metadata: bool = False,
    ) -> pa.Table:
        """Read the entire file as an Arrow Table.

        Args:
            columns: Column names to read. If None, reads all columns.
            use_threads: Ignored (for PyArrow compatibility).
            use_pandas_metadata: Ignored (for PyArrow compatibility).

        Returns:
            Arrow Table containing the file data.
        """
        if self._use_fallback:
            return self._fallback.read(columns=columns)

        if self._closed:
            raise ValueError("I/O operation on closed file")

        # Handle empty datasets
        if self._is_empty:
            return pa.table({})

        arrays = []
        names = []

        # Use valid column indices (non-empty names and types)
        col_indices = self._valid_column_indices

        if columns is not None:
            # Map column names to indices (only valid columns)
            col_name_to_idx = {
                self._column_names[i]: i
                for i in self._valid_column_indices
            }
            col_indices = [
                col_name_to_idx.get(c)
                for c in columns
                if c in col_name_to_idx
            ]

        for col_idx in col_indices:
            name = self._column_names[col_idx]
            col_type = self._column_types[col_idx]

            # Use zero-copy Arrow C Data Interface for numeric types
            if col_type in ("int64", "Int64"):
                arr = self._file.read_int64_column_arrow(col_idx)
                arrays.append(arr)
            elif col_type in ("float64", "double", "Float64"):
                arr = self._file.read_float64_column_arrow(col_idx)
                arrays.append(arr)
            elif col_type in ("string", "utf8", "String"):
                # Zero-copy via Arrow C Data Interface (data buffer is zero-copy)
                arr = self._file.read_string_column_arrow(col_idx)
                arrays.append(arr)
            else:
                # Unsupported type - create null array with expected row count
                row_count = self._file.row_count(col_idx)
                schema_field = self._schema.field(name)
                arrays.append(pa.array([None] * row_count, type=schema_field.type))

            names.append(name)

        return pa.table(dict(zip(names, arrays)))

    def read_row_group(
        self,
        i: int,
        columns: Optional[List[str]] = None,
        use_threads: bool = True,
        use_pandas_metadata: bool = False,
    ) -> pa.Table:
        """Read a single row group as an Arrow Table.

        Args:
            i: Row group index.
            columns: Column names to read.
            use_threads: Ignored.
            use_pandas_metadata: Ignored.

        Returns:
            Arrow Table containing the row group data.
        """
        if self._use_fallback:
            return self._fallback.read_row_group(i, columns=columns)

        if i != 0:
            raise IndexError(f"Row group {i} out of range (have 1)")

        return self.read(columns=columns)

    def read_row_groups(
        self,
        row_groups: List[int],
        columns: Optional[List[str]] = None,
        use_threads: bool = True,
        use_pandas_metadata: bool = False,
    ) -> pa.Table:
        """Read multiple row groups as an Arrow Table.

        Args:
            row_groups: List of row group indices.
            columns: Column names to read.
            use_threads: Ignored.
            use_pandas_metadata: Ignored.

        Returns:
            Arrow Table containing the combined row groups.
        """
        if self._use_fallback:
            return self._fallback.read_row_groups(row_groups, columns=columns)

        if any(i != 0 for i in row_groups):
            raise IndexError("Row group index out of range")

        return self.read(columns=columns)

    def iter_batches(
        self,
        batch_size: int = 65536,
        row_groups: Optional[List[int]] = None,
        columns: Optional[List[str]] = None,
        use_threads: bool = True,
        use_pandas_metadata: bool = False,
    ) -> Iterator[pa.RecordBatch]:
        """Iterate over record batches.

        Args:
            batch_size: Number of rows per batch.
            row_groups: Row groups to read (ignored for Lance).
            columns: Column names to read.
            use_threads: Ignored.
            use_pandas_metadata: Ignored.

        Yields:
            Arrow RecordBatch objects.
        """
        if self._use_fallback:
            yield from self._fallback.iter_batches(
                batch_size=batch_size, columns=columns
            )
            return

        table = self.read(columns=columns)
        for batch in table.to_batches(max_chunksize=batch_size):
            yield batch

    def close(self) -> None:
        """Close the file."""
        if not self._closed and not self._use_fallback and not self._is_empty:
            if self._file:
                self._file.close()
        self._closed = True

    def __enter__(self) -> "ParquetFile":
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.close()

    def __del__(self) -> None:
        if not self._closed:
            self.close()


def read_table(
    source: Union[str, Path, bytes],
    columns: Optional[List[str]] = None,
    use_threads: bool = True,
    memory_map: bool = False,
    use_pandas_metadata: bool = False,
    filters: Optional[List] = None,
    **kwargs,
) -> pa.Table:
    """Read a Parquet/Lance file into an Arrow Table.

    Args:
        source: File path or bytes.
        columns: Column names to read.
        use_threads: Ignored (for compatibility).
        memory_map: Ignored (for compatibility).
        use_pandas_metadata: Ignored (for compatibility).
        filters: Row filters (not yet implemented).
        **kwargs: Additional arguments (ignored).

    Returns:
        Arrow Table containing the file data.
    """
    with ParquetFile(source) as pf:
        return pf.read(columns=columns)


def read_metadata(
    source: Union[str, Path],
    memory_map: bool = False,
) -> FileMetaData:
    """Read file metadata without reading the data.

    Args:
        source: File path.
        memory_map: Ignored.

    Returns:
        FileMetaData object.
    """
    with ParquetFile(source) as pf:
        return pf.metadata


def read_schema(
    source: Union[str, Path],
    memory_map: bool = False,
) -> pa.Schema:
    """Read file schema without reading the data.

    Args:
        source: File path.
        memory_map: Ignored.

    Returns:
        Arrow Schema object.
    """
    with ParquetFile(source) as pf:
        return pf.schema


# Compatibility aliases
ParquetDataset = ParquetFile  # Simplified alias
