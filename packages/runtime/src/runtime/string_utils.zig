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

/// Python str.format() - replaces {key} or {} with argument values
/// Handles keyword args as .{.{name, value}, ...} tuples
pub fn pyStrFormat(allocator: std.mem.Allocator, template: []const u8, args: anytype) ![]u8 {
    var result = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    var positional_idx: usize = 0;

    while (i < template.len) {
        if (template[i] == '{' and i + 1 < template.len) {
            // Check for escaped brace {{
            if (template[i + 1] == '{') {
                try result.append(allocator, '{');
                i += 2;
                continue;
            }

            // Find closing brace
            var j = i + 1;
            while (j < template.len and template[j] != '}') : (j += 1) {}

            if (j < template.len) {
                const placeholder = template[i + 1 .. j];

                // Try to find matching argument
                const replacement = findArg(args, placeholder, &positional_idx);
                try result.appendSlice(allocator, replacement);
                i = j + 1;
                continue;
            }
        } else if (template[i] == '}' and i + 1 < template.len and template[i + 1] == '}') {
            // Escaped closing brace }}
            try result.append(allocator, '}');
            i += 2;
            continue;
        }

        try result.append(allocator, template[i]);
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

/// Find argument value by key name or positional index
fn findArg(args: anytype, placeholder: []const u8, positional_idx: *usize) []const u8 {
    const T = @TypeOf(args);
    const info = @typeInfo(T);

    // Handle tuple of key-value pairs: .{.{"key", "value"}, ...}
    if (info == .@"struct" and info.@"struct".is_tuple) {
        // Empty placeholder {} means positional argument
        if (placeholder.len == 0) {
            const idx = positional_idx.*;
            positional_idx.* += 1;

            // For positional, get the idx-th element's value (second item of tuple)
            inline for (info.@"struct".fields, 0..) |_, field_idx| {
                if (field_idx == idx) {
                    const kv = args[field_idx];
                    const kv_info = @typeInfo(@TypeOf(kv));
                    if (kv_info == .@"struct" and kv_info.@"struct".is_tuple) {
                        return kv[1]; // Value
                    }
                    return kv; // Direct value
                }
            }
            return "";
        }

        // Named placeholder {key} - search by key name
        inline for (info.@"struct".fields) |field| {
            const kv = @field(args, field.name);
            const kv_info = @typeInfo(@TypeOf(kv));
            if (kv_info == .@"struct" and kv_info.@"struct".is_tuple) {
                if (std.mem.eql(u8, kv[0], placeholder)) {
                    return kv[1]; // Value
                }
            }
        }
    }

    return "";
}
