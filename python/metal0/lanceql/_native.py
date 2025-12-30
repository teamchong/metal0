"""Native ctypes bindings for lanceql shared library.

Supports two data transfer modes:
1. Copy mode (default): Data is copied through ctypes - slower but always works
2. Zero-copy mode: Uses Arrow C Data Interface for direct memory sharing

Zero-copy requires pyarrow to be installed. When available, use read_column_arrow()
for best performance - the data stays in Zig-allocated memory and is imported
directly into PyArrow without copying.
"""

import ctypes
from pathlib import Path
import sys
import numpy as np
from typing import Optional, TYPE_CHECKING

if TYPE_CHECKING:
    import pyarrow as pa


# Platform-specific library name
if sys.platform == "darwin":
    lib_name = "liblanceql.dylib"
elif sys.platform == "win32":
    lib_name = "lanceql.dll"
else:
    lib_name = "liblanceql.so"

lib_path = Path(__file__).parent / lib_name
if not lib_path.exists():
    raise RuntimeError(f"Native library not found at {lib_path}")

_lib = ctypes.CDLL(str(lib_path))

# Function signatures
_lib.lance_open_memory.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
_lib.lance_open_memory.restype = ctypes.c_void_p

_lib.lance_close.argtypes = [ctypes.c_void_p]
_lib.lance_close.restype = None

_lib.lance_column_count.argtypes = [ctypes.c_void_p]
_lib.lance_column_count.restype = ctypes.c_uint32

_lib.lance_row_count.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
_lib.lance_row_count.restype = ctypes.c_uint64

_lib.lance_column_name.argtypes = [
    ctypes.c_void_p,
    ctypes.c_uint32,
    ctypes.POINTER(ctypes.c_uint8),
    ctypes.c_size_t,
]
_lib.lance_column_name.restype = ctypes.c_size_t

_lib.lance_column_type.argtypes = [
    ctypes.c_void_p,
    ctypes.c_uint32,
    ctypes.POINTER(ctypes.c_uint8),
    ctypes.c_size_t,
]
_lib.lance_column_type.restype = ctypes.c_size_t

# String column still uses copy-based API (no Arrow string export yet)
_lib.lance_read_string.argtypes = [
    ctypes.c_void_p,
    ctypes.c_uint32,
    ctypes.POINTER(ctypes.POINTER(ctypes.c_uint8)),
    ctypes.POINTER(ctypes.c_size_t),
    ctypes.c_size_t,
]
_lib.lance_read_string.restype = ctypes.c_size_t

# Arrow C Data Interface functions for zero-copy export
_lib.lance_export_int64_column.argtypes = [
    ctypes.c_void_p,  # handle
    ctypes.c_uint32,  # col_idx
    ctypes.POINTER(ctypes.c_void_p),  # out_schema
    ctypes.POINTER(ctypes.c_void_p),  # out_array
]
_lib.lance_export_int64_column.restype = ctypes.c_uint32

_lib.lance_export_float64_column.argtypes = [
    ctypes.c_void_p,  # handle
    ctypes.c_uint32,  # col_idx
    ctypes.POINTER(ctypes.c_void_p),  # out_schema
    ctypes.POINTER(ctypes.c_void_p),  # out_array
]
_lib.lance_export_float64_column.restype = ctypes.c_uint32

_lib.lance_release_schema.argtypes = [ctypes.c_void_p]
_lib.lance_release_schema.restype = None

_lib.lance_release_array.argtypes = [ctypes.c_void_p]
_lib.lance_release_array.restype = None

_lib.lance_export_string_column.argtypes = [
    ctypes.c_void_p,  # handle
    ctypes.c_uint32,  # col_idx
    ctypes.POINTER(ctypes.c_void_p),  # out_schema
    ctypes.POINTER(ctypes.c_void_p),  # out_array
]
_lib.lance_export_string_column.restype = ctypes.c_uint32


class LanceFile:
    """Python wrapper for native Lance file reader."""

    def __init__(self, data: bytes):
        """Open a Lance file from bytes.

        Args:
            data: Raw bytes of the Lance file

        Raises:
            TypeError: If data is not bytes
            ValueError: If file cannot be opened
        """
        if not isinstance(data, bytes):
            raise TypeError(f"Expected bytes, got {type(data)}")

        # Create C array and keep reference to prevent garbage collection
        # The Zig code stores a pointer to this data, so it must stay alive
        self._c_data = (ctypes.c_uint8 * len(data)).from_buffer_copy(data)
        self._handle = _lib.lance_open_memory(self._c_data, len(data))

        if not self._handle:
            raise ValueError("Failed to open Lance file")

    def close(self):
        """Close the file and free resources."""
        if self._handle:
            _lib.lance_close(self._handle)
            self._handle = None

    def column_count(self) -> int:
        """Get the number of columns in the table."""
        return _lib.lance_column_count(self._handle)

    def row_count(self, col_idx: int) -> int:
        """Get the number of rows for a specific column.

        Args:
            col_idx: Column index (0-based)

        Returns:
            Number of rows in the column
        """
        return _lib.lance_row_count(self._handle, col_idx)

    def column_name(self, col_idx: int) -> str:
        """Get the name of a column.

        Args:
            col_idx: Column index (0-based)

        Returns:
            Column name as string
        """
        buf = (ctypes.c_uint8 * 256)()
        length = _lib.lance_column_name(self._handle, col_idx, buf, 256)
        if length == 0:
            return ""
        return bytes(buf[:length]).decode("utf-8")

    def column_type(self, col_idx: int) -> str:
        """Get the logical type of a column.

        Args:
            col_idx: Column index (0-based)

        Returns:
            Type string (e.g., "int64", "float64", "string")
        """
        buf = (ctypes.c_uint8 * 256)()
        length = _lib.lance_column_type(self._handle, col_idx, buf, 256)
        if length == 0:
            return ""
        return bytes(buf[:length]).decode("utf-8")

    def read_string_column(self, col_idx: int) -> list[str]:
        """Read a string column.

        Args:
            col_idx: Column index (0-based)

        Returns:
            List of strings
        """
        row_count = self.row_count(col_idx)
        if row_count == 0:
            return []

        # Allocate arrays for pointers and lengths
        string_ptrs = (ctypes.POINTER(ctypes.c_uint8) * row_count)()
        string_lens = (ctypes.c_size_t * row_count)()

        actual = _lib.lance_read_string(
            self._handle, col_idx, string_ptrs, string_lens, row_count
        )

        # Convert C strings to Python strings
        result = []
        for i in range(actual):
            # Create bytes from pointer and length, then decode UTF-8
            string_bytes = ctypes.string_at(string_ptrs[i], string_lens[i])
            result.append(string_bytes.decode("utf-8"))

        return result

    def read_int64_column_arrow(self, col_idx: int) -> "pa.Array":
        """Read an int64 column as a PyArrow array (zero-copy).

        This uses the Arrow C Data Interface to share memory directly
        between Zig and Python without copying.

        Args:
            col_idx: Column index (0-based)

        Returns:
            PyArrow Int64Array

        Raises:
            ImportError: If pyarrow is not installed
            ValueError: If column cannot be exported
        """
        import pyarrow as pa

        schema_ptr = ctypes.c_void_p()
        array_ptr = ctypes.c_void_p()

        result = _lib.lance_export_int64_column(
            self._handle,
            col_idx,
            ctypes.byref(schema_ptr),
            ctypes.byref(array_ptr),
        )

        if result == 0:
            raise ValueError(f"Failed to export column {col_idx} as Arrow")

        try:
            # Import via Arrow C Data Interface
            return pa.Array._import_from_c(array_ptr.value, schema_ptr.value)
        finally:
            # Release Zig-side allocations
            if schema_ptr.value:
                _lib.lance_release_schema(schema_ptr.value)
            if array_ptr.value:
                _lib.lance_release_array(array_ptr.value)

    def read_float64_column_arrow(self, col_idx: int) -> "pa.Array":
        """Read a float64 column as a PyArrow array (zero-copy).

        This uses the Arrow C Data Interface to share memory directly
        between Zig and Python without copying.

        Args:
            col_idx: Column index (0-based)

        Returns:
            PyArrow Float64Array

        Raises:
            ImportError: If pyarrow is not installed
            ValueError: If column cannot be exported
        """
        import pyarrow as pa

        schema_ptr = ctypes.c_void_p()
        array_ptr = ctypes.c_void_p()

        result = _lib.lance_export_float64_column(
            self._handle,
            col_idx,
            ctypes.byref(schema_ptr),
            ctypes.byref(array_ptr),
        )

        if result == 0:
            raise ValueError(f"Failed to export column {col_idx} as Arrow")

        try:
            # Import via Arrow C Data Interface
            return pa.Array._import_from_c(array_ptr.value, schema_ptr.value)
        finally:
            # Release Zig-side allocations
            if schema_ptr.value:
                _lib.lance_release_schema(schema_ptr.value)
            if array_ptr.value:
                _lib.lance_release_array(array_ptr.value)

    def read_string_column_arrow(self, col_idx: int) -> "pa.Array":
        """Read a string column as a PyArrow array (zero-copy for data buffer).

        This uses the Arrow C Data Interface. The string data buffer is
        zero-copy, only the offsets array needs conversion from Lance
        (end-offsets) to Arrow (start-offsets) format.

        Args:
            col_idx: Column index (0-based)

        Returns:
            PyArrow StringArray

        Raises:
            ImportError: If pyarrow is not installed
            ValueError: If column cannot be exported
        """
        import pyarrow as pa

        schema_ptr = ctypes.c_void_p()
        array_ptr = ctypes.c_void_p()

        result = _lib.lance_export_string_column(
            self._handle,
            col_idx,
            ctypes.byref(schema_ptr),
            ctypes.byref(array_ptr),
        )

        if result == 0:
            raise ValueError(f"Failed to export column {col_idx} as Arrow")

        try:
            # Import via Arrow C Data Interface
            return pa.Array._import_from_c(array_ptr.value, schema_ptr.value)
        finally:
            # Release Zig-side allocations
            if schema_ptr.value:
                _lib.lance_release_schema(schema_ptr.value)
            if array_ptr.value:
                _lib.lance_release_array(array_ptr.value)

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, *args):
        """Context manager exit."""
        self.close()

    def __del__(self):
        """Destructor - ensure resources are freed."""
        self.close()
