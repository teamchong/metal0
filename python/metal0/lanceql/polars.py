"""Polars DataFrame integration for Lance files.

This module provides Polars DataFrame support for reading Lance files,
leveraging the zero-copy Arrow C Data Interface.

Usage:
    import metal0.lanceql.polars as lqpl

    # Read entire file as DataFrame
    df = lqpl.read_table('data.lance')

    # Read with column selection
    df = lqpl.read_table('data.lance', columns=['id', 'name'])

    # Lazy evaluation
    lazy = lqpl.scan_lance('data.lance')
    result = lazy.filter(pl.col('value') > 100).collect()
"""

from pathlib import Path
from typing import Union, Optional, List, Dict, Any

try:
    import polars as pl
except ImportError:
    raise ImportError(
        "polars is required for this module. "
        "Install it with: pip install polars"
    )

from .parquet import ParquetFile


class LanceReader:
    """Reader for Lance files returning Polars DataFrames.

    Provides a Polars-native interface for reading Lance columnar files.
    """

    def __init__(
        self,
        source: Union[str, Path, bytes],
        **kwargs,
    ):
        """Open a Lance file.

        Args:
            source: File path or bytes containing file data.
            **kwargs: Additional arguments passed to ParquetFile.
        """
        self._pf = ParquetFile(source, **kwargs)
        self._source = source

    @property
    def schema(self) -> Dict[str, pl.DataType]:
        """Schema as Polars dtype mapping."""
        arrow_schema = self._pf.schema
        return {
            field.name: _arrow_to_polars_type(field.type)
            for field in arrow_schema
        }

    @property
    def columns(self) -> List[str]:
        """List of column names."""
        return [field.name for field in self._pf.schema]

    @property
    def num_rows(self) -> int:
        """Number of rows in the file."""
        return self._pf.metadata.num_rows

    @property
    def num_columns(self) -> int:
        """Number of columns in the file."""
        return self._pf.metadata.num_columns

    def read(
        self,
        columns: Optional[List[str]] = None,
    ) -> pl.DataFrame:
        """Read the file as a Polars DataFrame.

        Args:
            columns: Column names to read. If None, reads all columns.

        Returns:
            Polars DataFrame containing the file data.
        """
        table = self._pf.read(columns=columns)
        return pl.from_arrow(table)

    def to_lazy(
        self,
        columns: Optional[List[str]] = None,
    ) -> pl.LazyFrame:
        """Get a LazyFrame for deferred execution.

        Note: This currently reads the data eagerly and converts to lazy.
        True lazy evaluation would require deeper integration.

        Args:
            columns: Column names to read. If None, reads all columns.

        Returns:
            Polars LazyFrame for query optimization.
        """
        return self.read(columns=columns).lazy()

    def close(self) -> None:
        """Close the underlying file."""
        self._pf.close()

    def __enter__(self) -> "LanceReader":
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.close()

    def __repr__(self) -> str:
        return (
            f"<LanceReader columns={self.num_columns} "
            f"rows={self.num_rows}>"
        )


def _arrow_to_polars_type(arrow_type) -> pl.DataType:
    """Convert Arrow type to Polars type."""
    import pyarrow as pa

    if pa.types.is_int64(arrow_type):
        return pl.Int64
    elif pa.types.is_int32(arrow_type):
        return pl.Int32
    elif pa.types.is_float64(arrow_type):
        return pl.Float64
    elif pa.types.is_float32(arrow_type):
        return pl.Float32
    elif pa.types.is_string(arrow_type) or pa.types.is_large_string(arrow_type):
        return pl.Utf8
    elif pa.types.is_boolean(arrow_type):
        return pl.Boolean
    elif pa.types.is_null(arrow_type):
        return pl.Null
    else:
        # Fallback for unknown types
        return pl.Object


def read_table(
    source: Union[str, Path, bytes],
    columns: Optional[List[str]] = None,
    **kwargs,
) -> pl.DataFrame:
    """Read a Lance file into a Polars DataFrame.

    This is the primary function for reading Lance files with Polars.
    Uses zero-copy Arrow C Data Interface for efficient data transfer.

    Args:
        source: File path or bytes.
        columns: Column names to read. If None, reads all columns.
        **kwargs: Additional arguments (ignored for compatibility).

    Returns:
        Polars DataFrame containing the file data.

    Example:
        >>> import metal0.lanceql.polars as lqpl
        >>> df = lqpl.read_table('data.lance')
        >>> df = lqpl.read_table('data.lance', columns=['id', 'value'])
    """
    with LanceReader(source) as reader:
        return reader.read(columns=columns)


def scan_lance(
    source: Union[str, Path],
    columns: Optional[List[str]] = None,
    **kwargs,
) -> pl.LazyFrame:
    """Create a LazyFrame from a Lance file.

    Returns a LazyFrame for deferred query execution with optimizations.

    Note: Current implementation reads data eagerly. True lazy evaluation
    would require predicate pushdown support in the native reader.

    Args:
        source: File path.
        columns: Column names to read. If None, reads all columns.
        **kwargs: Additional arguments (ignored).

    Returns:
        Polars LazyFrame for query building.

    Example:
        >>> import metal0.lanceql.polars as lqpl
        >>> lazy = lqpl.scan_lance('data.lance')
        >>> result = lazy.filter(pl.col('value') > 100).select(['id', 'value']).collect()
    """
    with LanceReader(source) as reader:
        return reader.to_lazy(columns=columns)


def read_schema(
    source: Union[str, Path],
) -> Dict[str, pl.DataType]:
    """Read file schema without reading data.

    Args:
        source: File path.

    Returns:
        Dictionary mapping column names to Polars data types.

    Example:
        >>> schema = lqpl.read_schema('data.lance')
        >>> print(schema)
        {'id': Int64, 'name': Utf8, 'value': Float64}
    """
    with LanceReader(source) as reader:
        return reader.schema


def read_metadata(
    source: Union[str, Path],
) -> Dict[str, Any]:
    """Read file metadata without reading data.

    Args:
        source: File path.

    Returns:
        Dictionary with metadata (num_rows, num_columns, etc.).

    Example:
        >>> meta = lqpl.read_metadata('data.lance')
        >>> print(meta['num_rows'])
        1000000
    """
    with LanceReader(source) as reader:
        return {
            "num_rows": reader.num_rows,
            "num_columns": reader.num_columns,
            "columns": reader.columns,
            "schema": reader.schema,
        }
