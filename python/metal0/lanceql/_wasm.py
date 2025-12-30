"""WASM runtime wrapper for LanceQL."""

import struct
from pathlib import Path
from typing import Optional, List, Tuple, Any
import numpy as np

try:
    from wasmtime import Engine, Store, Module, Instance, Memory, Func
except ImportError:
    raise ImportError(
        "wasmtime is required for lanceql. Install with: pip install wasmtime"
    )


class WasmRuntime:
    """Wrapper around the LanceQL WASM module."""

    _instance: Optional["WasmRuntime"] = None

    def __init__(self, wasm_path: Optional[Path] = None):
        """Initialize the WASM runtime.

        Args:
            wasm_path: Path to the WASM file. If None, uses the bundled WASM.
        """
        if wasm_path is None:
            wasm_path = Path(__file__).parent / "lanceql.wasm"

        if not wasm_path.exists():
            raise FileNotFoundError(
                f"WASM file not found at {wasm_path}. "
                "Build it with 'zig build wasm' and copy to python/lanceql/"
            )

        self.engine = Engine()
        self.store = Store(self.engine)
        self.module = Module.from_file(self.engine, str(wasm_path))
        self.instance = Instance(self.store, self.module, [])

        # Cache exported functions
        self._exports = self.instance.exports(self.store)
        self._memory: Memory = self._exports["memory"]

        # File state
        self._file_data: Optional[bytes] = None
        self._file_ptr: Optional[int] = None

    @classmethod
    def get_instance(cls) -> "WasmRuntime":
        """Get the singleton WASM runtime instance."""
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def _call(self, name: str, *args) -> Any:
        """Call an exported WASM function."""
        func: Func = self._exports[name]
        return func(self.store, *args)

    def _read_memory(self, ptr: int, length: int) -> bytes:
        """Read bytes from WASM memory."""
        data = self._memory.data_ptr(self.store)
        return bytes(data[ptr : ptr + length])

    def _write_memory(self, ptr: int, data: bytes) -> None:
        """Write bytes to WASM memory."""
        mem_data = self._memory.data_ptr(self.store)
        for i, b in enumerate(data):
            mem_data[ptr + i] = b

    def alloc(self, size: int) -> int:
        """Allocate memory in WASM heap."""
        ptr = self._call("alloc", size)
        if ptr == 0:
            raise MemoryError(f"Failed to allocate {size} bytes in WASM")
        return ptr

    def free(self, ptr: int, size: int) -> None:
        """Free memory in WASM heap."""
        self._call("free", ptr, size)

    def reset_heap(self) -> None:
        """Reset the WASM heap allocator."""
        self._call("resetHeap")

    def get_version(self) -> Tuple[int, int]:
        """Get LanceQL version as (major, minor)."""
        version = self._call("getVersion")
        major = (version >> 16) & 0xFFFF
        minor = version & 0xFFFF
        return (major, minor)

    def is_valid_lance_file(self, data: bytes) -> bool:
        """Check if data is a valid Lance file."""
        ptr = self.alloc(len(data))
        try:
            self._write_memory(ptr, data)
            result = self._call("isValidLanceFile", ptr, len(data))
            return result == 1
        finally:
            self.free(ptr, len(data))

    def open_file(self, data: bytes) -> bool:
        """Open a Lance file from bytes.

        Args:
            data: Complete Lance file data.

        Returns:
            True if file was opened successfully.
        """
        # Close any existing file
        self.close_file()

        # Allocate and copy data
        self._file_data = data
        self._file_ptr = self.alloc(len(data))
        self._write_memory(self._file_ptr, data)

        # Open the file
        # Note: openFile returns 1 for success, 0 for failure
        result = self._call("openFile", self._file_ptr, len(data))
        if result != 1:
            self.free(self._file_ptr, len(data))
            self._file_data = None
            self._file_ptr = None
            return False

        return True

    def close_file(self) -> None:
        """Close the currently open file."""
        if self._file_ptr is not None:
            self._call("closeFile")
            self.free(self._file_ptr, len(self._file_data))
            self._file_data = None
            self._file_ptr = None

    def get_num_columns(self) -> int:
        """Get number of columns in the open file."""
        return self._call("getNumColumns")

    def get_row_count(self, col_idx: int) -> int:
        """Get row count for a column."""
        return self._call("getRowCount", col_idx)

    def parse_footer(self, data: bytes) -> dict:
        """Parse Lance footer and return metadata."""
        ptr = self.alloc(len(data))
        try:
            self._write_memory(ptr, data)
            num_cols = self._call("parseFooterGetColumns", ptr, len(data))
            major = self._call("parseFooterGetMajorVersion", ptr, len(data))
            minor = self._call("parseFooterGetMinorVersion", ptr, len(data))
            col_meta_start = self._call("getColumnMetaStart", ptr, len(data))
            col_meta_offsets_start = self._call(
                "getColumnMetaOffsetsStart", ptr, len(data)
            )
            return {
                "num_columns": num_cols,
                "major_version": major,
                "minor_version": minor,
                "column_meta_start": col_meta_start,
                "column_meta_offsets_start": col_meta_offsets_start,
            }
        finally:
            self.free(ptr, len(data))

    def read_int64_column(self, col_idx: int) -> np.ndarray:
        """Read an int64 column as numpy array."""
        row_count = self.get_row_count(col_idx)
        if row_count == 0:
            return np.array([], dtype=np.int64)

        # Allocate output buffer
        out_ptr = self._call("allocInt64Buffer", row_count)
        if out_ptr == 0:
            raise MemoryError(f"Failed to allocate buffer for {row_count} int64s")

        try:
            # Read the column
            actual_count = self._call("readInt64Column", col_idx, out_ptr, row_count)
            if actual_count == 0:
                return np.array([], dtype=np.int64)

            # Read results from WASM memory
            data = self._read_memory(out_ptr, actual_count * 8)
            return np.frombuffer(data, dtype=np.int64).copy()
        finally:
            self._call("freeInt64Buffer", out_ptr, row_count)

    def read_float64_column(self, col_idx: int) -> np.ndarray:
        """Read a float64 column as numpy array."""
        row_count = self.get_row_count(col_idx)
        if row_count == 0:
            return np.array([], dtype=np.float64)

        out_ptr = self._call("allocFloat64Buffer", row_count)
        if out_ptr == 0:
            raise MemoryError(f"Failed to allocate buffer for {row_count} float64s")

        try:
            actual_count = self._call("readFloat64Column", col_idx, out_ptr, row_count)
            if actual_count == 0:
                return np.array([], dtype=np.float64)

            data = self._read_memory(out_ptr, actual_count * 8)
            return np.frombuffer(data, dtype=np.float64).copy()
        finally:
            self._call("freeFloat64Buffer", out_ptr, row_count)

    def read_float32_column(self, col_idx: int) -> np.ndarray:
        """Read a float32 column as numpy array."""
        row_count = self.get_row_count(col_idx)
        if row_count == 0:
            return np.array([], dtype=np.float32)

        out_ptr = self._call("allocFloat32Buffer", row_count)
        if out_ptr == 0:
            raise MemoryError(f"Failed to allocate buffer for {row_count} float32s")

        try:
            actual_count = self._call("readFloat32Column", col_idx, out_ptr, row_count)
            if actual_count == 0:
                return np.array([], dtype=np.float32)

            data = self._read_memory(out_ptr, actual_count * 4)
            return np.frombuffer(data, dtype=np.float32).copy()
        finally:
            self._call("freeFloat32Buffer", out_ptr, row_count)

    def read_int32_column(self, col_idx: int) -> np.ndarray:
        """Read an int32 column as numpy array."""
        row_count = self.get_row_count(col_idx)
        if row_count == 0:
            return np.array([], dtype=np.int32)

        out_ptr = self._call("allocInt32Buffer", row_count)
        if out_ptr == 0:
            raise MemoryError(f"Failed to allocate buffer for {row_count} int32s")

        try:
            actual_count = self._call("readInt32Column", col_idx, out_ptr, row_count)
            if actual_count == 0:
                return np.array([], dtype=np.int32)

            data = self._read_memory(out_ptr, actual_count * 4)
            return np.frombuffer(data, dtype=np.int32).copy()
        finally:
            self._call("freeInt32Buffer", out_ptr, row_count)

    def read_string_column(self, col_idx: int) -> List[str]:
        """Read a string column as list of strings."""
        string_count = self._call("getStringCount", col_idx)
        if string_count == 0:
            return []

        result = []
        # Allocate a buffer for reading strings
        max_string_len = 65536  # 64KB max string
        out_ptr = self._call("allocStringBuffer", max_string_len)
        if out_ptr == 0:
            raise MemoryError("Failed to allocate string buffer")

        try:
            for row_idx in range(string_count):
                length = self._call(
                    "readStringAt", col_idx, row_idx, out_ptr, max_string_len
                )
                if length > 0:
                    data = self._read_memory(out_ptr, length)
                    result.append(data.decode("utf-8"))
                else:
                    result.append("")
        finally:
            self._call("free", out_ptr, max_string_len)

        return result

    def sum_int64_column(self, col_idx: int) -> int:
        """Calculate sum of an int64 column."""
        return self._call("sumInt64Column", col_idx)

    def sum_float64_column(self, col_idx: int) -> float:
        """Calculate sum of a float64 column."""
        return self._call("sumFloat64Column", col_idx)

    def min_int64_column(self, col_idx: int) -> int:
        """Get minimum value of an int64 column."""
        return self._call("minInt64Column", col_idx)

    def max_int64_column(self, col_idx: int) -> int:
        """Get maximum value of an int64 column."""
        return self._call("maxInt64Column", col_idx)

    def avg_float64_column(self, col_idx: int) -> float:
        """Calculate average of a float64 column."""
        return self._call("avgFloat64Column", col_idx)

    def filter_int64_column(
        self, col_idx: int, op: int, value: int, max_results: int
    ) -> np.ndarray:
        """Filter an int64 column.

        Args:
            col_idx: Column index.
            op: Comparison operator (0=eq, 1=ne, 2=lt, 3=le, 4=gt, 5=ge).
            value: Value to compare against.
            max_results: Maximum number of matching indices to return.

        Returns:
            Array of matching row indices.
        """
        out_ptr = self._call("allocIndexBuffer", max_results)
        if out_ptr == 0:
            raise MemoryError(f"Failed to allocate index buffer for {max_results}")

        try:
            count = self._call(
                "filterInt64Column", col_idx, op, value, out_ptr, max_results
            )
            if count == 0:
                return np.array([], dtype=np.uint32)

            data = self._read_memory(out_ptr, count * 4)
            return np.frombuffer(data, dtype=np.uint32).copy()
        finally:
            self._call("free", out_ptr, max_results * 4)

    def filter_float64_column(
        self, col_idx: int, op: int, value: float, max_results: int
    ) -> np.ndarray:
        """Filter a float64 column.

        Args:
            col_idx: Column index.
            op: Comparison operator (0=eq, 1=ne, 2=lt, 3=le, 4=gt, 5=ge).
            value: Value to compare against.
            max_results: Maximum number of matching indices to return.

        Returns:
            Array of matching row indices.
        """
        out_ptr = self._call("allocIndexBuffer", max_results)
        if out_ptr == 0:
            raise MemoryError(f"Failed to allocate index buffer for {max_results}")

        try:
            count = self._call(
                "filterFloat64Column", col_idx, op, value, out_ptr, max_results
            )
            if count == 0:
                return np.array([], dtype=np.uint32)

            data = self._read_memory(out_ptr, count * 4)
            return np.frombuffer(data, dtype=np.uint32).copy()
        finally:
            self._call("free", out_ptr, max_results * 4)


# Filter operation constants
FILTER_EQ = 0
FILTER_NE = 1
FILTER_LT = 2
FILTER_LE = 3
FILTER_GT = 4
FILTER_GE = 5
