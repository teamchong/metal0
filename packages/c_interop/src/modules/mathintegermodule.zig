/// mathintegermodule - Integer-specific Math Operations
const cpython = @import("../include/object.zig");

/// Compute floor of log base 2 of n
pub export fn _PyLong_FloorLog2(n: *cpython.PyObject) c_long {
    _ = n;
    return 0;
}

/// Compute gcd of two integers
pub export fn _PyLong_GCD(a: *cpython.PyObject, b: *cpython.PyObject) ?*cpython.PyObject {
    _ = a;
    _ = b;
    return null;
}
