/// Parse JSON numbers directly to PyInt/PyFloat - uses shared primitives
const std = @import("std");
const runtime = @import("../../../runtime.zig");
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;
const json = @import("json");
const primitives = json.primitives;

/// Parse number directly to PyInt/PyFloat (delegates to shared primitives)
pub fn parseNumber(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) {
    const result = primitives.parseNumber(data, pos) catch |err| {
        return switch (err) {
            error.InvalidNumber => JsonError.InvalidNumber,
            error.NumberOutOfRange => JsonError.NumberOutOfRange,
            error.UnexpectedEndOfInput => JsonError.UnexpectedEndOfInput,
            else => JsonError.InvalidNumber,
        };
    };

    const py_obj: *runtime.PyObject = switch (result.value) {
        .int => |v| try runtime.PyInt.create(allocator, v),
        .float => |v| try runtime.PyFloat.create(allocator, v),
    };

    return ParseResult(*runtime.PyObject).init(py_obj, result.consumed);
}
