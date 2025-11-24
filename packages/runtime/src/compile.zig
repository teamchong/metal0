const std = @import("std");
const runtime = @import("runtime.zig");

pub fn compile_builtin(allocator: std.mem.Allocator, source: []const u8, filename: []const u8, mode: []const u8) !*runtime.PyObject {
    _ = filename; // unused for MVP
    _ = mode; // unused for MVP

    // For MVP: return source string as code object
    // Full implementation would return bytecode object
    const PyString = runtime.PyString;
    return try PyString.create(allocator, source);
}
