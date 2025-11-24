/// Tests for PyModule and PyImport systems

const std = @import("std");
const cpython_module = @import("../src/cpython_module.zig");
const cpython_import = @import("../src/cpython_import.zig");

test "module system compiles" {
    // This test just verifies that all the types and functions compile
    try std.testing.expect(@sizeOf(cpython_module.PyModuleObject) > 0);
    try std.testing.expect(@sizeOf(cpython_module.PyModuleDef) > 0);
    try std.testing.expect(@sizeOf(cpython_module.PyMethodDef) > 0);
}

test "import inittab" {
    const inittab = cpython_import.PyImport_Inittab{
        .name = "test",
        .initfunc = undefined,
    };

    try std.testing.expect(@sizeOf(@TypeOf(inittab)) > 0);
}
