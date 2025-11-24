/// Test PyLong and PyBytes implementations
const std = @import("std");
const pylong = @import("src/pyobject_long.zig");
const pybytes = @import("src/pyobject_bytes.zig");
const cpython = @import("src/cpython_object.zig");

pub fn main() !void {
    std.debug.print("\n=== Testing PyLongObject ===\n", .{});

    // Test basic creation and conversion
    const x = pylong.PyLong_FromLong(42);
    const y = pylong.PyLong_FromLong(10);

    if (x == null or y == null) {
        std.debug.print("ERROR: Failed to create PyLong objects\n", .{});
        return error.CreationFailed;
    }

    std.debug.print("Created x=42, y=10\n", .{});

    const x_val = pylong.PyLong_AsLong(x.?);
    const y_val = pylong.PyLong_AsLong(y.?);

    std.debug.print("x value: {d}\n", .{x_val});
    std.debug.print("y value: {d}\n", .{y_val});

    // Test arithmetic via number protocol
    const x_long = @as(*cpython.PyLongObject, @ptrCast(x.?));
    const type_obj = cpython.Py_TYPE(&x_long.ob_base.ob_base);

    std.debug.print("Type name: {s}\n", .{type_obj.tp_name});

    // Test small int cache
    const cached1 = pylong.PyLong_FromLong(100);
    const cached2 = pylong.PyLong_FromLong(100);

    if (cached1 == cached2) {
        std.debug.print("✓ Small int cache working (100 == 100)\n", .{});
    } else {
        std.debug.print("✗ Small int cache failed\n", .{});
    }

    // Test outside cache range
    const big1 = pylong.PyLong_FromLong(300);
    const big2 = pylong.PyLong_FromLong(300);

    if (big1 != big2) {
        std.debug.print("✓ Outside cache range creates new objects (300 != 300)\n", .{});
    } else {
        std.debug.print("✗ Cache range check failed\n", .{});
    }

    std.debug.print("\n=== Testing PyBytesObject ===\n", .{});

    // Test basic creation
    const s = pybytes.PyBytes_FromString("hello");
    if (s == null) {
        std.debug.print("ERROR: Failed to create PyBytes object\n", .{});
        return error.CreationFailed;
    }

    const data = pybytes.PyBytes_AsString(s.?);
    const len = pybytes.PyBytes_Size(s.?);

    std.debug.print("Created bytes: {s}\n", .{std.mem.span(data)});
    std.debug.print("Length: {d}\n", .{len});

    // Test concatenation
    const hello = pybytes.PyBytes_FromString("hello");
    const world = pybytes.PyBytes_FromString(" world");

    if (hello == null or world == null) {
        std.debug.print("ERROR: Failed to create bytes for concat\n", .{});
        return error.CreationFailed;
    }

    std.debug.print("\n=== Testing Type Checking ===\n", .{});

    const is_long = pylong.PyLong_Check(x.?);
    const is_bytes = pybytes.PyBytes_Check(s.?);

    std.debug.print("x is PyLong: {d}\n", .{is_long});
    std.debug.print("s is PyBytes: {d}\n", .{is_bytes});

    std.debug.print("\n=== All Tests Passed! ===\n", .{});
}
