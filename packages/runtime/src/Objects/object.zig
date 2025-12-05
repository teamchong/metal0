/// Dynamic value type for runtime attribute storage
/// Supports comptime SIMD operations for string comparisons
const std = @import("std");

/// PyValue - Runtime-typed value for dynamic attributes
/// Uses tagged union for type safety
pub const PyValue = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    bytes: @import("../runtime/builtins.zig").PyBytes, // Python bytes type
    bool: bool,
    none: void,
    list: []const PyValue,
    tuple: []const PyValue,
    ptr: *anyopaque, // For types that can't be represented

    /// Format value for printing
    pub fn format(
        self: PyValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .int => |v| try writer.print("{d}", .{v}),
            .float => |v| try writer.print("{d}", .{v}),
            .string => |v| try writer.print("{s}", .{v}),
            .bytes => |v| try writer.print("{s}", .{v.data}),
            .bool => |v| try writer.print("{}", .{v}),
            .none => try writer.writeAll("None"),
            .list => |items| {
                try writer.writeAll("[");
                for (items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format(fmt, options, writer);
                }
                try writer.writeAll("]");
            },
            .tuple => |items| {
                try writer.writeAll("(");
                for (items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format(fmt, options, writer);
                }
                if (items.len == 1) try writer.writeAll(",");
                try writer.writeAll(")");
            },
            .ptr => try writer.writeAll("<ptr>"),
        }
    }

    /// Convert to integer (if possible)
    pub fn toInt(self: PyValue) ?i64 {
        return switch (self) {
            .int => |v| v,
            .float => |v| @intFromFloat(v),
            .bool => |v| if (v) @as(i64, 1) else @as(i64, 0),
            else => null,
        };
    }

    /// Convert to float (if possible)
    pub fn toFloat(self: PyValue) ?f64 {
        return switch (self) {
            .float => |v| v,
            .int => |v| @floatFromInt(v),
            else => null,
        };
    }

    /// Check if value is truthy
    pub fn isTruthy(self: PyValue) bool {
        return switch (self) {
            .bool => |v| v,
            .int => |v| v != 0,
            .float => |v| v != 0.0,
            .string => |v| v.len > 0,
            .none => false,
            .list => |v| v.len > 0,
            .tuple => |v| v.len > 0,
            .ptr => true,
        };
    }

    /// Get length for list/tuple/string PyValues
    pub fn pyLen(self: PyValue) usize {
        return switch (self) {
            .list => |v| v.len,
            .tuple => |v| v.len,
            .string => |v| v.len,
            else => 0,
        };
    }

    /// Get Python type name for this value
    pub fn typeName(self: PyValue) []const u8 {
        return switch (self) {
            .int => "int",
            .float => "float",
            .string => "str",
            .bool => "bool",
            .none => "NoneType",
            .list => "list",
            .tuple => "tuple",
            .ptr => "object",
        };
    }

    /// Index into list/tuple PyValue
    pub fn pyAt(self: PyValue, idx: usize) PyValue {
        return switch (self) {
            .list => |v| v[idx],
            .tuple => |v| v[idx],
            else => .{ .none = {} },
        };
    }

    /// Get from dict-wrapped PyValue (ptr to StringHashMap)
    /// For fmtdict['@'][fmt] where fmtdict['@'] is a PyValue wrapping a dict
    pub fn pyDictGet(self: PyValue, key: []const u8) ?PyValue {
        if (self != .ptr) return null;
        const hashmap_helper = @import("hashmap_helper");
        const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(self.ptr));
        return map_ptr.get(key);
    }

    /// Get mutable ptr from dict-wrapped PyValue (ptr to StringHashMap)
    /// For assigning to fmtdict['@'][fmt]
    pub fn pyDictGetPtr(self: PyValue, key: []const u8) ?*PyValue {
        if (self != .ptr) return null;
        const hashmap_helper = @import("hashmap_helper");
        const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(self.ptr));
        return map_ptr.getPtr(key);
    }

    /// Put into dict-wrapped PyValue (ptr to StringHashMap)
    pub fn pyDictPut(self: PyValue, allocator: std.mem.Allocator, key: []const u8, value: PyValue) !void {
        _ = allocator; // Allocator kept for API compatibility but not used for in-place put
        if (self != .ptr) return;
        const hashmap_helper = @import("hashmap_helper");
        const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(self.ptr));
        try map_ptr.put(key, value);
    }

    /// Unwrap to string (for code that expects []const u8)
    pub fn asString(self: PyValue) []const u8 {
        return switch (self) {
            .string => |v| v,
            else => "",
        };
    }

    /// Unwrap to int (for code that expects i64)
    pub fn asInt(self: PyValue) i64 {
        return switch (self) {
            .int => |v| v,
            else => 0,
        };
    }

    /// Unwrap to float (for code that expects f64)
    pub fn asFloat(self: PyValue) f64 {
        return switch (self) {
            .float => |v| v,
            .int => |v| @floatFromInt(v),
            else => 0.0,
        };
    }

    /// Unwrap to bool (for code that expects bool)
    pub fn asBool(self: PyValue) bool {
        return self.isTruthy();
    }

    /// Create PyValue from any type (runtime version)
    /// Only supports simple types that don't need allocation for tuples/structs
    /// For tuples/structs, use fromAlloc() which properly allocates
    pub fn from(value: anytype) PyValue {
        const T = @TypeOf(value);
        if (T == i64 or T == i32 or T == i16 or T == i8 or T == u64 or T == u32 or T == u16 or T == u8 or T == usize or T == isize or T == comptime_int) {
            return .{ .int = @intCast(value) };
        } else if (T == f64 or T == f32 or T == comptime_float) {
            return .{ .float = @floatCast(value) };
        } else if (T == bool) {
            return .{ .bool = value };
        } else if (T == []const u8 or T == []u8) {
            return .{ .string = value };
        } else if (T == PyValue) {
            return value;
        } else if (T == []const PyValue or T == []PyValue) {
            return .{ .list = value };
        } else if (@typeInfo(T) == .pointer) {
            const ptr_info = @typeInfo(T).pointer;
            // Check for sentinel-terminated pointer to u8 (C strings)
            if (ptr_info.child == u8 and ptr_info.sentinel() != null) {
                return .{ .string = std.mem.span(value) };
            }
            // Handle pointer to fixed-size array of u8 (string literals)
            if (@typeInfo(ptr_info.child) == .array) {
                const arr_info = @typeInfo(ptr_info.child).array;
                if (arr_info.child == u8) {
                    // Convert array pointer to slice
                    return .{ .string = value[0..arr_info.len] };
                }
            }
            // Store as ptr for unknown pointer types
            return .{ .ptr = @ptrCast(@constCast(value)) };
        } else {
            return .{ .none = {} };
        }
    }

    /// Allocating version of from() for runtime tuples/structs
    /// Use this when you need to convert runtime values to PyValue
    pub fn fromAlloc(allocator: std.mem.Allocator, value: anytype) !PyValue {
        const T = @TypeOf(value);
        if (T == i64 or T == i32 or T == i16 or T == i8 or T == u64 or T == u32 or T == u16 or T == u8 or T == usize or T == isize) {
            return .{ .int = @intCast(value) };
        } else if (T == f64 or T == f32) {
            return .{ .float = @floatCast(value) };
        } else if (T == bool) {
            return .{ .bool = value };
        } else if (T == []const u8 or T == []u8) {
            return .{ .string = value };
        } else if (T == PyValue) {
            return value;
        } else if (T == []const PyValue or T == []PyValue) {
            return .{ .list = value };
        } else if (@typeInfo(T) == .pointer) {
            const ptr_info = @typeInfo(T).pointer;
            // Check for sentinel-terminated pointer to u8 (C strings)
            if (ptr_info.child == u8 and ptr_info.sentinel() != null) {
                return .{ .string = std.mem.span(value) };
            }
            // Handle pointer to fixed-size array of u8 (string literals)
            if (@typeInfo(ptr_info.child) == .array) {
                const arr_info = @typeInfo(ptr_info.child).array;
                if (arr_info.child == u8) {
                    // Convert array pointer to slice
                    return .{ .string = value[0..arr_info.len] };
                }
            }
            if (ptr_info.size == .slice) {
                // Allocate and convert slice elements
                const result = try allocator.alloc(PyValue, value.len);
                for (value, 0..) |item, i| {
                    result[i] = try fromAlloc(allocator, item);
                }
                return .{ .list = result };
            }
            return .{ .ptr = @ptrCast(@constCast(value)) };
        } else if (@typeInfo(T) == .array) {
            // Handle fixed-size arrays - convert to tuple
            const arr_info = @typeInfo(T).array;
            const result = try allocator.alloc(PyValue, arr_info.len);
            for (0..arr_info.len) |i| {
                result[i] = try fromAlloc(allocator, value[i]);
            }
            return .{ .tuple = result };
        } else if (@typeInfo(T) == .@"struct") {
            const info = @typeInfo(T).@"struct";
            // Handle StringHashMap/AutoHashMap - store as pointer
            // These have unmanaged and entries fields
            if (@hasField(T, "unmanaged") and @hasField(T, "entries")) {
                // HashMap - store pointer to the map
                // We allocate a copy of the struct on heap so it survives
                const ptr = try allocator.create(T);
                ptr.* = value;
                return .{ .ptr = @ptrCast(ptr) };
            }
            // Handle ArrayList - convert to list using items
            if (@hasField(T, "items") and @hasField(T, "capacity")) {
                const items_slice = value.items;
                const result = try allocator.alloc(PyValue, items_slice.len);
                for (items_slice, 0..) |item, i| {
                    result[i] = try fromAlloc(allocator, item);
                }
                return .{ .list = result };
            }
            // Handle tuples
            if (info.is_tuple) {
                const result = try allocator.alloc(PyValue, info.fields.len);
                inline for (0..info.fields.len) |i| {
                    result[i] = try fromAlloc(allocator, value[i]);
                }
                return .{ .tuple = result };
            }
            // Non-tuple struct - convert to tuple of fields
            const result = try allocator.alloc(PyValue, info.fields.len);
            inline for (0..info.fields.len) |i| {
                result[i] = try fromAlloc(allocator, @field(value, info.fields[i].name));
            }
            return .{ .tuple = result };
        } else {
            return .{ .none = {} };
        }
    }

    /// Convert to string representation
    pub fn toString(self: PyValue, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .int => |v| try std.fmt.allocPrint(allocator, "{d}", .{v}),
            .float => |v| blk: {
                // Python convention: nan never has sign, inf shows sign
                if (std.math.isNan(v)) break :blk try allocator.dupe(u8, "nan");
                if (std.math.isInf(v)) break :blk try allocator.dupe(u8, if (v < 0) "-inf" else "inf");
                break :blk try std.fmt.allocPrint(allocator, "{d}", .{v});
            },
            .string => |v| v,
            .bool => |v| if (v) "True" else "False",
            .none => "None",
            .list, .tuple, .ptr => try std.fmt.allocPrint(allocator, "{}", .{self}),
        };
    }

    /// Convert to repr representation (with quotes for strings)
    pub fn toRepr(self: PyValue, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .int => |v| try std.fmt.allocPrint(allocator, "{d}", .{v}),
            .float => |v| blk: {
                // Python convention: nan never has sign, inf shows sign
                if (std.math.isNan(v)) break :blk try allocator.dupe(u8, "nan");
                if (std.math.isInf(v)) break :blk try allocator.dupe(u8, if (v < 0) "-inf" else "inf");
                break :blk try std.fmt.allocPrint(allocator, "{d}", .{v});
            },
            .string => |v| try std.fmt.allocPrint(allocator, "'{s}'", .{v}),
            .bool => |v| if (v) "True" else "False",
            .none => "None",
            .list, .tuple, .ptr => try std.fmt.allocPrint(allocator, "{}", .{self}),
        };
    }
};

/// Optimized string comparison using comptime SIMD if available
/// Falls back to std.mem.eql for smaller strings
pub fn eqlString(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    if (a.len == 0) return true;

    // Use comptime to select best comparison method
    const use_simd = comptime blk: {
        // SIMD is beneficial for strings >= 16 bytes on most platforms
        const min_simd_len = 16;
        // Check if platform supports SIMD
        const has_simd = @import("builtin").cpu.arch.endian() == .little;
        break :blk has_simd and a.len >= min_simd_len;
    };

    if (use_simd) {
        // For longer strings, use vectorized comparison
        return simdEql(a, b);
    } else {
        // For short strings, use standard comparison
        return std.mem.eql(u8, a, b);
    }
}

/// SIMD-optimized string equality check
fn simdEql(a: []const u8, b: []const u8) bool {
    const len = a.len;

    // Process 16 bytes at a time using @Vector
    const vec_len = 16;
    const Vec = @Vector(vec_len, u8);

    var i: usize = 0;
    while (i + vec_len <= len) : (i += vec_len) {
        const va: Vec = a[i..][0..vec_len].*;
        const vb: Vec = b[i..][0..vec_len].*;

        // Compare vectors element-wise
        if (!@reduce(.And, va == vb)) {
            return false;
        }
    }

    // Handle remaining bytes
    while (i < len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }

    return true;
}

test "PyValue basic operations" {
    const testing = std.testing;

    const v_int = PyValue{ .int = 42 };
    const v_float = PyValue{ .float = 3.14 };
    const v_bool = PyValue{ .bool = true };
    const v_none = PyValue{ .none = {} };

    try testing.expectEqual(@as(i64, 42), v_int.toInt().?);
    try testing.expectEqual(@as(f64, 3.14), v_float.toFloat().?);
    try testing.expect(v_bool.isTruthy());
    try testing.expect(!v_none.isTruthy());
}

test "SIMD string comparison" {
    const testing = std.testing;

    const str1 = "hello world from metal0 compiler!";
    const str2 = "hello world from metal0 compiler!";
    const str3 = "hello world from metal0 compiler?";

    try testing.expect(eqlString(str1, str2));
    try testing.expect(!eqlString(str1, str3));
    try testing.expect(eqlString("", ""));
    try testing.expect(!eqlString("a", ""));
}
