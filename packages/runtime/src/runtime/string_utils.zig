const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;

/// Join a list of strings with a separator
/// Handles both static slices and PyValue lists
pub fn pyJoin(allocator: std.mem.Allocator, separator: []const u8, list: anytype) ![]u8 {
    const T = @TypeOf(list);
    const info = @typeInfo(T);

    // Handle PyValue union
    if (T == PyValue) {
        switch (list) {
            .list => |items| {
                return pyJoinSlice(allocator, separator, items);
            },
            .tuple => |items| {
                return pyJoinSlice(allocator, separator, items);
            },
            else => return error.TypeMismatch,
        }
    }
    // Handle slice of strings
    else if (info == .pointer and info.pointer.size == .slice) {
        return std.mem.join(allocator, separator, list);
    }
    // Handle array of strings
    else if (info == .array) {
        return std.mem.join(allocator, separator, &list);
    }
    // Handle ArrayList/struct with items field
    else if (info == .@"struct" and @hasField(T, "items")) {
        return pyJoinSlice(allocator, separator, list.items);
    }
    else {
        @compileError("pyJoin: unsupported type " ++ @typeName(T));
    }
}

/// Join a slice of PyValue items with separator
fn pyJoinSlice(allocator: std.mem.Allocator, separator: []const u8, items: []const PyValue) ![]u8 {
    if (items.len == 0) return try allocator.dupe(u8, "");

    // Calculate total length
    var total_len: usize = 0;
    for (items) |item| {
        switch (item) {
            .string => |s| total_len += s.len,
            .int => |n| {
                // Convert int to string length estimate
                var buf: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{n}) catch "";
                total_len += s.len;
            },
            else => {},
        }
    }
    total_len += separator.len * (items.len - 1);

    // Build result
    const result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (items, 0..) |item, idx| {
        switch (item) {
            .string => |s| {
                @memcpy(result[pos .. pos + s.len], s);
                pos += s.len;
            },
            .int => |n| {
                var buf: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{n}) catch "";
                @memcpy(result[pos .. pos + s.len], s);
                pos += s.len;
            },
            else => {},
        }

        if (idx < items.len - 1) {
            @memcpy(result[pos .. pos + separator.len], separator);
            pos += separator.len;
        }
    }

    return result[0..pos];
}

/// Allocates a new uppercase string
pub fn toUpper(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, input.len);
    for (input, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

/// Allocates a new lowercase string
pub fn toLower(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, input.len);
    for (input, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}
