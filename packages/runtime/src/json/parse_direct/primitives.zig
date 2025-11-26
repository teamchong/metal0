/// Parse JSON primitives directly to PyObject: null → None, true/false → Bool
const std = @import("std");
const runtime = @import("runtime.zig");
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;

/// Parse 'null' directly to PyObject None
pub fn parseNull(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) {
    if (pos + 4 > data.len) return JsonError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos .. pos + 4], "null")) {
        return JsonError.UnexpectedToken;
    }

    // Create PyObject for None
    const none = try allocator.create(runtime.PyObject);
    none.* = .{
        .ref_count = 1,
        .type_id = .none,
        .data = undefined,
    };

    return ParseResult(*runtime.PyObject).init(none, 4);
}

/// Parse 'true' directly to PyObject Bool
pub fn parseTrue(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) {
    if (pos + 4 > data.len) return JsonError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos .. pos + 4], "true")) {
        return JsonError.UnexpectedToken;
    }

    // Create PyObject for bool (true = 1)
    const bool_obj = try allocator.create(runtime.PyObject);
    bool_obj.* = .{
        .ref_count = 1,
        .type_id = .bool,
        .data = undefined,
    };

    const data_ptr = try allocator.create(runtime.PyInt);
    data_ptr.* = .{ .value = 1 };
    bool_obj.data = @ptrCast(data_ptr);

    return ParseResult(*runtime.PyObject).init(bool_obj, 4);
}

/// Parse 'false' directly to PyObject Bool
pub fn parseFalse(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) {
    if (pos + 5 > data.len) return JsonError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos .. pos + 5], "false")) {
        return JsonError.UnexpectedToken;
    }

    // Create PyObject for bool (false = 0)
    const bool_obj = try allocator.create(runtime.PyObject);
    bool_obj.* = .{
        .ref_count = 1,
        .type_id = .bool,
        .data = undefined,
    };

    const data_ptr = try allocator.create(runtime.PyInt);
    data_ptr.* = .{ .value = 0 };
    bool_obj.data = @ptrCast(data_ptr);

    return ParseResult(*runtime.PyObject).init(bool_obj, 5);
}

/// Parse any primitive based on first character
pub fn parsePrimitive(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) {
    if (pos >= data.len) return JsonError.UnexpectedEndOfInput;

    const c = data[pos];
    return switch (c) {
        'n' => try parseNull(data, pos, allocator),
        't' => try parseTrue(data, pos, allocator),
        'f' => try parseFalse(data, pos, allocator),
        else => JsonError.UnexpectedToken,
    };
}
