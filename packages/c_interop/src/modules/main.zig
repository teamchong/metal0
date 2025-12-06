/// main - Python Main Program Entry
const cpython = @import("../include/object.zig");

/// Main entry point for Python interpreter
pub export fn Py_Main(argc: c_int, argv: [*][*:0]u8) c_int {
    _ = argc;
    _ = argv;
    return 0;
}

/// Byte-based main entry
pub export fn Py_BytesMain(argc: c_int, argv: [*][*:0]u8) c_int {
    _ = argc;
    _ = argv;
    return 0;
}
