/// Pickle module stub for Python compatibility
/// Provides basic pickle protocol constants and functions
const std = @import("std");
const runtime = @import("runtime.zig");
const json = @import("json.zig");

/// Highest pickle protocol supported
pub const HIGHEST_PROTOCOL: i64 = 5;

/// Default protocol version
pub const DEFAULT_PROTOCOL: i64 = 4;

/// Pickle a Python object to bytes (uses JSON internally)
pub fn dumps(obj: anytype, allocator: std.mem.Allocator) ![]const u8 {
    // Use JSON as a simple serialization format
    return try json.dumpsDirect(obj, allocator);
}

/// Unpickle bytes back to a Python object
pub fn loads(data: []const u8, allocator: std.mem.Allocator) !*runtime.PyObject {
    // Use JSON deserialization
    const str_obj = try runtime.PyString.create(allocator, data);
    defer runtime.decref(str_obj, allocator);
    return try json.loads(str_obj, allocator);
}

/// Pickle to a file
pub fn dump(obj: anytype, file: anytype, allocator: std.mem.Allocator) !void {
    const data = try dumps(obj, allocator);
    defer allocator.free(data);
    try file.writeAll(data);
}

/// Unpickle from a file
pub fn load(file: anytype, allocator: std.mem.Allocator) !*runtime.PyObject {
    const data = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(data);
    return try loads(data, allocator);
}

/// Pickler class stub
pub const Pickler = struct {
    allocator: std.mem.Allocator,
    protocol: i64 = DEFAULT_PROTOCOL,

    pub fn init(allocator: std.mem.Allocator) Pickler {
        return .{ .allocator = allocator };
    }

    pub fn dump(self: *Pickler, obj: anytype) ![]const u8 {
        return try dumps(obj, self.allocator);
    }
};

/// Unpickler class stub
pub const Unpickler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Unpickler {
        return .{ .allocator = allocator };
    }

    pub fn load(self: *Unpickler, data: []const u8) !*runtime.PyObject {
        return try loads(data, self.allocator);
    }
};

/// PicklingError
pub const PicklingError = error.PicklingError;

/// UnpicklingError
pub const UnpicklingError = error.UnpicklingError;
