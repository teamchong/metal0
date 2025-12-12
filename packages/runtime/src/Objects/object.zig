/// Dynamic value type for runtime attribute storage
/// Supports comptime SIMD operations for string comparisons
const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const bigint = @import("bigint");

/// PyValue - Runtime-typed value for dynamic attributes
/// Uses tagged union for type safety
pub const PyValue = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    bytes: @import("../runtime/builtins.zig").PyBytes, // Python bytes type
    bool: bool,
    none: void,
    list: *std.ArrayListUnmanaged(PyValue), // Mutable list (Two-Flow Phase 11)
    tuple: []const PyValue,
    bigint: bigint.BigInt, // For integers that don't fit in i64
    complex: Complex, // Python complex number
    ptr: *anyopaque, // For types that can't be represented

    pub const Complex = struct { real: f64, imag: f64 };

    /// Create a PyValue list from a slice (allocates ArrayList on heap)
    pub fn listFromSlice(allocator: std.mem.Allocator, items: []const PyValue) !PyValue {
        const al = try allocator.create(std.ArrayListUnmanaged(PyValue));
        al.* = .{};
        try al.appendSlice(allocator, items);
        return .{ .list = al };
    }

    /// Create an empty PyValue list
    pub fn emptyList(allocator: std.mem.Allocator) !PyValue {
        const al = try allocator.create(std.ArrayListUnmanaged(PyValue));
        al.* = .{};
        return .{ .list = al };
    }

    /// Static empty list for compile-time defaults (threadlocal, no allocation needed)
    /// Use this for default initializers where allocator isn't available
    const StaticEmpty = struct {
        threadlocal var empty_list: std.ArrayListUnmanaged(PyValue) = .{};
    };

    pub fn staticEmptyList() PyValue {
        return .{ .list = &StaticEmpty.empty_list };
    }

    /// Set element at index in list (for list[i] = val)
    pub fn pyListSet(self: PyValue, idx: usize, value: PyValue) void {
        if (self == .list) {
            self.list.items[idx] = value;
        }
    }

    /// Append element to list
    pub fn pyListAppend(self: PyValue, allocator: std.mem.Allocator, value: PyValue) !void {
        if (self == .list) {
            try self.list.append(allocator, value);
        }
    }

    /// Get list items as slice (for iteration)
    pub fn listItems(self: PyValue) []const PyValue {
        return if (self == .list) self.list.items else &[_]PyValue{};
    }

    /// Get mutable list items (for direct mutation)
    pub fn listItemsMut(self: PyValue) []PyValue {
        return if (self == .list) self.list.items else &[_]PyValue{};
    }

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
            .list => |list| {
                try writer.writeAll("[");
                for (list.items, 0..) |item, i| {
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
            .bigint => |v| try writer.print("{s}", .{v.toString(allocator_helper.fast_allocator, 10) catch "<bigint>"}),
            .complex => |v| {
                if (v.imag >= 0) {
                    try writer.print("({d}+{d}j)", .{ v.real, v.imag });
                } else {
                    try writer.print("({d}{d}j)", .{ v.real, v.imag });
                }
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
            .bigint => |v| v.toInt(i64) catch null,
            else => null,
        };
    }

    /// Convert to float (if possible)
    pub fn toFloat(self: PyValue) ?f64 {
        return switch (self) {
            .float => |v| v,
            .int => |v| @floatFromInt(v),
            .bigint => |v| v.toFloat(),
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
            .bytes => |v| v.data.len > 0,
            .none => false,
            .list => |list| list.items.len > 0,
            .tuple => |v| v.len > 0,
            .bigint => |v| !v.isZero(),
            .complex => |v| v.real != 0.0 or v.imag != 0.0, // 0j is falsy
            .ptr => true,
        };
    }

    /// Get length for list/tuple/string PyValues
    pub fn pyLen(self: PyValue) usize {
        return switch (self) {
            .list => |list| list.items.len,
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
            .bytes => "bytes",
            .bool => "bool",
            .none => "NoneType",
            .list => "list",
            .tuple => "tuple",
            .bigint => "int",
            .complex => "complex",
            .ptr => "object",
        };
    }

    /// Index into list/tuple PyValue
    pub fn pyAt(self: PyValue, idx: usize) PyValue {
        return switch (self) {
            .list => |list| list.items[idx],
            .tuple => |v| v[idx],
            else => .{ .none = {} },
        };
    }

    /// Get from dict-wrapped PyValue (ptr to StringHashMap)
    /// For fmtdict['@'][fmt] where fmtdict['@'] is a PyValue wrapping a dict
    pub fn pyDictGet(self: PyValue, key: []const u8) ?PyValue {
        if (self != .ptr) return null;
        const hashmap_helper = @import("utils.hashmap_helper");
        const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(self.ptr));
        return map_ptr.get(key);
    }

    /// Get mutable ptr from dict-wrapped PyValue (ptr to StringHashMap)
    /// For assigning to fmtdict['@'][fmt]
    pub fn pyDictGetPtr(self: PyValue, key: []const u8) ?*PyValue {
        if (self != .ptr) return null;
        const hashmap_helper = @import("utils.hashmap_helper");
        const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(self.ptr));
        return map_ptr.getPtr(key);
    }

    /// Put into dict-wrapped PyValue (ptr to StringHashMap)
    pub fn pyDictPut(self: PyValue, allocator: std.mem.Allocator, key: []const u8, value: PyValue) !void {
        _ = allocator; // Allocator kept for API compatibility but not used for in-place put
        if (self != .ptr) return;
        const hashmap_helper = @import("utils.hashmap_helper");
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
            @compileError("Cannot convert []PyValue to PyValue.list without allocator. Use PyValue.listFromSlice(allocator, slice) instead.");
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
        } else if (@typeInfo(T) == .@"struct") {
            // Handle float/int/str subclasses with __base_value__ field
            if (@hasField(T, "__base_value__")) {
                const base = value.__base_value__;
                const base_info = @typeInfo(@TypeOf(base));
                if (base_info == .float or base_info == .comptime_float) {
                    return .{ .float = @floatCast(base) };
                }
                if (base_info == .int or base_info == .comptime_int) {
                    return .{ .int = @intCast(base) };
                }
            }
            return .{ .none = {} };
        } else {
            return .{ .none = {} };
        }
    }

    /// Allocating version of from() for runtime tuples/structs
    /// Use this when you need to convert runtime values to PyValue
    pub fn fromAlloc(allocator: std.mem.Allocator, value: anytype) !PyValue {
        const T = @TypeOf(value);
        // Handle BigInt first (before general struct handling)
        if (T == bigint.BigInt) {
            return .{ .bigint = value };
        } else if (T == i64 or T == i32 or T == i16 or T == i8 or T == u64 or T == u32 or T == u16 or T == u8 or T == usize or T == isize) {
            return .{ .int = @intCast(value) };
        } else if (@typeInfo(T) == .comptime_int) {
            // Handle comptime_int values
            return .{ .int = @as(i64, value) };
        } else if (T == f64 or T == f32) {
            return .{ .float = @floatCast(value) };
        } else if (T == bool) {
            return .{ .bool = value };
        } else if (T == []const u8 or T == []u8) {
            return .{ .string = value };
        } else if (T == PyValue) {
            return value;
        } else if (T == []const PyValue or T == []PyValue) {
            @compileError("Cannot convert []PyValue to PyValue.list without allocator. Use PyValue.listFromSlice(allocator, slice) instead.");
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
            // Handle float/int/str subclasses with __base_value__ field
            if (@hasField(T, "__base_value__")) {
                const base = value.__base_value__;
                const base_info = @typeInfo(@TypeOf(base));
                if (base_info == .float or base_info == .comptime_float) {
                    return .{ .float = @floatCast(base) };
                }
                if (base_info == .int or base_info == .comptime_int) {
                    return .{ .int = @intCast(base) };
                }
            }
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
            .complex => |v| blk: {
                if (v.imag >= 0) {
                    break :blk try std.fmt.allocPrint(allocator, "({d}+{d}j)", .{ v.real, v.imag });
                } else {
                    break :blk try std.fmt.allocPrint(allocator, "({d}{d}j)", .{ v.real, v.imag });
                }
            },
            .list, .tuple, .bigint, .bytes, .ptr => try std.fmt.allocPrint(allocator, "{}", .{self}),
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
            .complex => |v| blk: {
                if (v.imag >= 0) {
                    break :blk try std.fmt.allocPrint(allocator, "({d}+{d}j)", .{ v.real, v.imag });
                } else {
                    break :blk try std.fmt.allocPrint(allocator, "({d}{d}j)", .{ v.real, v.imag });
                }
            },
            .list, .tuple, .bigint, .bytes, .ptr => try std.fmt.allocPrint(allocator, "{}", .{self}),
        };
    }

    // ============================================================================
    // Arithmetic Operations (for uncertain type safety)
    // ============================================================================

    /// Add two PyValues (returns PyValue to handle mixed types safely)
    pub fn add(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a +% b }, // Wrapping add for safety
                .float => |b| .{ .float = @as(f64, @floatFromInt(a)) + b },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| .{ .float = a + @as(f64, @floatFromInt(b)) },
                .float => |b| .{ .float = a + b },
                else => .{ .none = {} },
            },
            .string => |a| switch (other) {
                .string => |b| blk: {
                    // String concat - needs allocator, return none for now
                    // Callers should use addAlloc for strings
                    _ = a;
                    _ = b;
                    break :blk .{ .none = {} };
                },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Subtract two PyValues
    pub fn sub(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a -% b },
                .float => |b| .{ .float = @as(f64, @floatFromInt(a)) - b },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| .{ .float = a - @as(f64, @floatFromInt(b)) },
                .float => |b| .{ .float = a - b },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Multiply two PyValues
    pub fn mul(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a *% b },
                .float => |b| .{ .float = @as(f64, @floatFromInt(a)) * b },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| .{ .float = a * @as(f64, @floatFromInt(b)) },
                .float => |b| .{ .float = a * b },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Divide two PyValues (Python 3 true division - always returns float)
    pub fn div(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| if (b != 0) .{ .float = @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b)) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @as(f64, @floatFromInt(a)) / b } else .{ .none = {} },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| if (b != 0) .{ .float = a / @as(f64, @floatFromInt(b)) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = a / b } else .{ .none = {} },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Floor divide two PyValues (Python //)
    pub fn floordiv(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| if (b != 0) .{ .int = @divFloor(a, b) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @floor(@as(f64, @floatFromInt(a)) / b) } else .{ .none = {} },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| if (b != 0) .{ .float = @floor(a / @as(f64, @floatFromInt(b))) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @floor(a / b) } else .{ .none = {} },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Modulo two PyValues (Python %)
    pub fn mod(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| if (b != 0) .{ .int = @mod(a, b) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @mod(@as(f64, @floatFromInt(a)), b) } else .{ .none = {} },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| if (b != 0) .{ .float = @mod(a, @as(f64, @floatFromInt(b))) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @mod(a, b) } else .{ .none = {} },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Negate a PyValue
    pub fn neg(self: PyValue) PyValue {
        return switch (self) {
            .int => |a| .{ .int = -%a },
            .float => |a| .{ .float = -a },
            .bool => |a| .{ .int = if (a) -1 else 0 },
            else => .{ .none = {} },
        };
    }

    // ============================================================================
    // Bitwise Operations (for Two-Flow uncertain operands)
    // ============================================================================

    /// Bitwise AND of two PyValues (a & b)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyBitAnd(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a & b },
                .bool => |b| .{ .int = a & @as(i64, if (b) 1 else 0) },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| .{ .int = @as(i64, if (a) 1 else 0) & b },
                .bool => |b| .{ .bool = a and b },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Bitwise OR of two PyValues (a | b)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyBitOr(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a | b },
                .bool => |b| .{ .int = a | @as(i64, if (b) 1 else 0) },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| .{ .int = @as(i64, if (a) 1 else 0) | b },
                .bool => |b| .{ .bool = a or b },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Bitwise XOR of two PyValues (a ^ b)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyBitXor(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a ^ b },
                .bool => |b| .{ .int = a ^ @as(i64, if (b) 1 else 0) },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| .{ .int = @as(i64, if (a) 1 else 0) ^ b },
                .bool => |b| .{ .bool = a != b },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Bitwise left shift of two PyValues (a << b)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyLShift(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| blk: {
                    if (b < 0 or b >= 64) break :blk .{ .none = {} };
                    break :blk .{ .int = a << @as(u6, @intCast(b)) };
                },
                .bool => |b| .{ .int = if (b) a << 1 else a },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| blk: {
                    if (b < 0 or b >= 64) break :blk .{ .none = {} };
                    break :blk .{ .int = @as(i64, if (a) 1 else 0) << @as(u6, @intCast(b)) };
                },
                .bool => |b| .{ .int = if (a) (if (b) @as(i64, 2) else @as(i64, 1)) else 0 },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Bitwise right shift of two PyValues (a >> b)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyRShift(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| blk: {
                    if (b < 0 or b >= 64) break :blk .{ .none = {} };
                    break :blk .{ .int = a >> @as(u6, @intCast(b)) };
                },
                .bool => |b| .{ .int = if (b) a >> 1 else a },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| blk: {
                    if (b < 0 or b >= 64) break :blk .{ .none = {} };
                    break :blk .{ .int = @as(i64, if (a) 1 else 0) >> @as(u6, @intCast(b)) };
                },
                .bool => |b| .{ .int = if (a) (if (b) @as(i64, 0) else @as(i64, 1)) else 0 },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Bitwise invert of a PyValue (~a)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyInvert(self: PyValue) PyValue {
        return switch (self) {
            .int => |a| .{ .int = ~a },
            .bool => |a| .{ .int = if (a) -2 else -1 }, // ~True=-2, ~False=-1
            else => .{ .none = {} },
        };
    }

    /// Power of two PyValues (a ** b)
    /// For Two-Flow: handles uncertain numeric types at runtime
    pub fn pyPow(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| blk: {
                    if (b < 0) {
                        // Negative exponent returns float
                        break :blk .{ .float = std.math.pow(f64, @as(f64, @floatFromInt(a)), @as(f64, @floatFromInt(b))) };
                    }
                    // Positive exponent returns int (with overflow)
                    var result: i64 = 1;
                    var base = a;
                    var exp = b;
                    while (exp > 0) {
                        if (exp & 1 == 1) result *%= base;
                        base *%= base;
                        exp >>= 1;
                    }
                    break :blk .{ .int = result };
                },
                .float => |b| .{ .float = std.math.pow(f64, @as(f64, @floatFromInt(a)), b) },
                .bool => |b| .{ .int = if (b) a else 1 },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| .{ .float = std.math.pow(f64, a, @as(f64, @floatFromInt(b))) },
                .float => |b| .{ .float = std.math.pow(f64, a, b) },
                .bool => |b| .{ .float = if (b) a else 1.0 },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| blk: {
                    const base: i64 = if (a) 1 else 0;
                    if (b < 0) {
                        if (base == 0) break :blk .{ .none = {} }; // 0**-n is undefined
                        break :blk .{ .float = 1.0 }; // 1**-n = 1.0
                    }
                    break :blk .{ .int = if (a) 1 else (if (b == 0) @as(i64, 1) else @as(i64, 0)) };
                },
                .float => |b| .{ .float = std.math.pow(f64, if (a) 1.0 else 0.0, b) },
                .bool => |b| .{ .int = if (a) 1 else (if (b) 0 else 1) }, // 0**0=1, 0**1=0, 1**x=1
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Compare two PyValues (less than)
    pub fn lt(self: PyValue, other: PyValue) bool {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| a < b,
                .float => |b| @as(f64, @floatFromInt(a)) < b,
                else => false,
            },
            .float => |a| switch (other) {
                .int => |b| a < @as(f64, @floatFromInt(b)),
                .float => |b| a < b,
                else => false,
            },
            .string => |a| switch (other) {
                .string => |b| std.mem.order(u8, a, b) == .lt,
                else => false,
            },
            else => false,
        };
    }

    /// Compare two PyValues (less than or equal)
    pub fn le(self: PyValue, other: PyValue) bool {
        return self.lt(other) or self.eql(other);
    }

    /// Compare two PyValues (greater than)
    pub fn gt(self: PyValue, other: PyValue) bool {
        return other.lt(self);
    }

    /// Compare two PyValues (greater than or equal)
    pub fn ge(self: PyValue, other: PyValue) bool {
        return other.lt(self) or self.eql(other);
    }

    /// Check equality with another PyValue (single concrete function - no anytype)
    /// Implements Python's rich comparison semantics:
    /// - bool is subtype of int (True=1, False=0)
    /// - int and float are comparable
    /// - complex with zero imaginary part is comparable to real numbers
    pub fn eql(self: PyValue, other: PyValue) bool {
        const self_tag = std.meta.activeTag(self);
        const other_tag = std.meta.activeTag(other);

        // Same type - direct comparison
        if (self_tag == other_tag) {
            return switch (self) {
                .int => |v| v == other.int,
                .float => |v| v == other.float,
                .string => |v| std.mem.eql(u8, v, other.string),
                .bytes => |v| std.mem.eql(u8, v.data, other.bytes.data),
                .bool => |v| v == other.bool,
                .none => true,
                .list => |list| blk: {
                    const other_list = other.list;
                    if (list.items.len != other_list.items.len) break :blk false;
                    for (list.items, other_list.items) |a, b| {
                        if (!a.eql(b)) break :blk false;
                    }
                    break :blk true;
                },
                .tuple => |v| blk: {
                    const w = other.tuple;
                    if (v.len != w.len) break :blk false;
                    for (v, w) |a, b| {
                        if (!a.eql(b)) break :blk false;
                    }
                    break :blk true;
                },
                .bigint => |v| v.eql(&other.bigint),
                .complex => |v| v.real == other.complex.real and v.imag == other.complex.imag,
                .ptr => |v| v == other.ptr,
            };
        }

        // Python numeric coercion: bool < int < float < complex < bigint
        // Convert both to the "higher" type and compare

        // Special case: BigInt vs int - compare as BigInt for precision
        if (self_tag == .bigint and other_tag == .int) {
            return self.bigint.eqlInt(other.int);
        }
        if (self_tag == .int and other_tag == .bigint) {
            return other.bigint.eqlInt(self.int);
        }

        // Helper to get numeric value as complex (real, imag)
        // NOTE: BigInt.toFloat() may lose precision for very large numbers
        const self_num: ?struct { real: f64, imag: f64 } = switch (self) {
            .bool => |v| .{ .real = if (v) 1.0 else 0.0, .imag = 0.0 },
            .int => |v| .{ .real = @floatFromInt(v), .imag = 0.0 },
            .float => |v| .{ .real = v, .imag = 0.0 },
            .complex => |v| .{ .real = v.real, .imag = v.imag },
            .bigint => |v| .{ .real = v.toFloat(), .imag = 0.0 },
            else => null,
        };

        const other_num: ?struct { real: f64, imag: f64 } = switch (other) {
            .bool => |v| .{ .real = if (v) 1.0 else 0.0, .imag = 0.0 },
            .int => |v| .{ .real = @floatFromInt(v), .imag = 0.0 },
            .float => |v| .{ .real = v, .imag = 0.0 },
            .complex => |v| .{ .real = v.real, .imag = v.imag },
            .bigint => |v| .{ .real = v.toFloat(), .imag = 0.0 },
            else => null,
        };

        // If both are numeric types, compare as complex
        if (self_num != null and other_num != null) {
            return self_num.?.real == other_num.?.real and self_num.?.imag == other_num.?.imag;
        }

        // Non-numeric different types are not equal
        return false;
    }

    // ============================================================================
    // Aggregate Operations (for Two-Flow uncertain iterables)
    // ============================================================================

    /// Sum all values in a PyValue list
    /// For Two-Flow: handles uncertain iterables at runtime
    pub fn pySum(self: PyValue) PyValue {
        return switch (self) {
            .list => |list| {
                var total: PyValue = .{ .int = 0 };
                for (list.items) |item| {
                    total = total.add(item);
                }
                return total;
            },
            .tuple => |items| {
                var total: PyValue = .{ .int = 0 };
                for (items) |item| {
                    total = total.add(item);
                }
                return total;
            },
            // Single numeric value - return as is
            .int, .float => self,
            else => .{ .int = 0 },
        };
    }

    /// Check if all values in a PyValue list are truthy
    /// For Two-Flow: handles uncertain iterables at runtime
    pub fn pyAll(self: PyValue) bool {
        return switch (self) {
            .list => |list| {
                for (list.items) |item| {
                    if (!item.isTruthy()) return false;
                }
                return true;
            },
            .tuple => |items| {
                for (items) |item| {
                    if (!item.isTruthy()) return false;
                }
                return true;
            },
            // Single value - return its truthiness
            else => self.isTruthy(),
        };
    }

    /// Check if any value in a PyValue list is truthy
    /// For Two-Flow: handles uncertain iterables at runtime
    pub fn pyAny(self: PyValue) bool {
        return switch (self) {
            .list => |list| {
                for (list.items) |item| {
                    if (item.isTruthy()) return true;
                }
                return false;
            },
            .tuple => |items| {
                for (items) |item| {
                    if (item.isTruthy()) return true;
                }
                return false;
            },
            // Single value - return its truthiness
            else => self.isTruthy(),
        };
    }

    // ============================================================================
    // Math Operations (for Two-Flow uncertain operands)
    // ============================================================================

    /// Absolute value of a PyValue
    /// For Two-Flow: handles uncertain numeric types at runtime
    pub fn pyAbs(self: PyValue) PyValue {
        return switch (self) {
            .int => |v| .{ .int = if (v < 0) -v else v },
            .float => |v| .{ .float = @abs(v) },
            .bool => |v| .{ .int = if (v) 1 else 0 },
            else => .{ .int = 0 },
        };
    }

    /// Minimum of two PyValues
    /// For Two-Flow: handles uncertain operands at runtime
    pub fn pyMin(self: PyValue, other: PyValue) PyValue {
        // Use lt() for comparison
        if (self.lt(other)) {
            return self;
        } else {
            return other;
        }
    }

    /// Maximum of two PyValues
    /// For Two-Flow: handles uncertain operands at runtime
    pub fn pyMax(self: PyValue, other: PyValue) PyValue {
        // Use gt() for comparison
        if (self.gt(other)) {
            return self;
        } else {
            return other;
        }
    }

    /// Hash value of a PyValue
    /// For Two-Flow: handles uncertain types at runtime
    pub fn pyHash(self: PyValue) i64 {
        return switch (self) {
            .int => |v| v,
            .float => |v| blk: {
                // Python's float hash - if it's a whole number, use the int hash
                const int_val = @as(i64, @intFromFloat(v));
                if (@as(f64, @floatFromInt(int_val)) == v) {
                    break :blk int_val;
                }
                // Otherwise use bit cast
                break :blk @as(i64, @bitCast(v));
            },
            .bool => |v| if (v) 1 else 0,
            .string => |v| @as(i64, @bitCast(std.hash.Wyhash.hash(0, v))),
            .none => 0,
            else => 0,
        };
    }
};

/// Convert any value to PyValue (single-anytype function, O(n) instantiations)
/// Use this instead of pyAnyEql which has O(n²) instantiations
pub fn toPyValue(allocator: std.mem.Allocator, value: anytype) !PyValue {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Direct matches
    if (T == PyValue) return value;
    if (T == bigint.BigInt) return .{ .bigint = value };
    if (T == i64 or T == i32 or T == i16 or T == i8) return .{ .int = @intCast(value) };
    // Unsigned integers - check if they fit in i64, otherwise use BigInt
    if (T == u64 or T == usize) {
        if (value <= std.math.maxInt(i64)) {
            return .{ .int = @intCast(value) };
        } else {
            // Value exceeds i64 max, convert to BigInt
            return .{ .bigint = try bigint.BigInt.fromInt128(allocator, @as(i128, value)) };
        }
    }
    if (T == u32 or T == u16 or T == u8) return .{ .int = @intCast(value) };
    if (T == f64 or T == f32) return .{ .float = @floatCast(value) };
    if (T == bool) return .{ .bool = value };
    if (info == .comptime_int) return .{ .int = @intCast(value) };
    if (info == .comptime_float) return .{ .float = @floatCast(value) };

    // Complex numbers (PyComplex struct has .real and .imag fields)
    if (info == .@"struct" and @hasField(T, "real") and @hasField(T, "imag")) {
        return .{ .complex = .{ .real = value.real, .imag = value.imag } };
    }

    // PyObject pointer - extract the actual value from CPython-style object
    // This handles results from BytecodeVM.execute() which returns *PyObject
    if (info == .pointer and info.pointer.size == .one) {
        const Child = info.pointer.child;
        const runtime = @import("../runtime.zig");
        // Check if it's a *PyObject (the base type) or compatible pointer
        if (Child == runtime.PyObject or
            (@typeInfo(Child) == .@"struct" and @hasField(Child, "ob_base")))
        {
            // Cast to *PyObject and extract value based on type
            const obj: *runtime.PyObject = @ptrCast(@alignCast(value));
            if (runtime.PyLong_Check(obj)) {
                const PyInt = @import("intobject.zig").PyInt;
                return .{ .int = PyInt.getValue(obj) };
            }
            if (runtime.PyFloat_Check(obj)) {
                const PyFloat = @import("floatobject.zig").PyFloat;
                return .{ .float = PyFloat.getValue(obj) };
            }
            if (runtime.PyBool_Check(obj)) {
                const PyBool = @import("boolobject.zig").PyBool;
                return .{ .bool = PyBool.getValue(obj) };
            }
            if (runtime.PyUnicode_Check(obj)) {
                const PyString = @import("stringlib/core.zig").PyString;
                return .{ .string = PyString.getValue(obj) };
            }
            // Fall through to ptr for other PyObject types
        }
    }

    // String slices
    if (T == []const u8) return .{ .string = value };
    if (T == []u8) return .{ .string = value };

    // String literals: *const [N:0]u8 - pointer to null-terminated array
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array and child_info.array.child == u8) {
            // Convert *const [N]u8 or *const [N:0]u8 to []const u8
            return .{ .string = value[0..child_info.array.len] };
        }
    }

    // Fixed arrays of u8 (strings)
    if (info == .array and info.array.child == u8) {
        return .{ .string = &value };
    }

    // NativeList - special handling (has .items which is ArrayListUnmanaged)
    // NativeList.items contains PyValue items, so just return them directly
    if (info == .@"struct" and @hasDecl(T, "init") and @hasField(T, "items")) {
        // Check if items field is an ArrayListUnmanaged by checking for items.items
        const ItemsT = @TypeOf(value.items);
        if (@typeInfo(ItemsT) == .@"struct" and @hasField(ItemsT, "items")) {
            // This is NativeList or similar wrapper - items.items is the slice
            return try PyValue.listFromSlice(allocator, value.items.items);
        }
    }

    // ArrayLists - convert items to PyValue list
    if (info == .@"struct" and @hasField(T, "items") and @hasField(T, "capacity")) {
        const ElemT = std.meta.Elem(@TypeOf(value.items));
        var list = try allocator.alloc(PyValue, value.items.len);
        for (value.items, 0..) |item, i| {
            list[i] = try toPyValue(allocator, item);
            _ = ElemT; // Reference to avoid unused warning
        }
        return try PyValue.listFromSlice(allocator, list);
    }

    // Fixed arrays
    if (info == .array) {
        var list = try allocator.alloc(PyValue, info.array.len);
        for (value, 0..) |item, i| {
            list[i] = try toPyValue(allocator, item);
        }
        return try PyValue.listFromSlice(allocator, list);
    }

    // Slices of non-u8
    if (info == .pointer and info.pointer.size == .slice and info.pointer.child != u8) {
        var list = try allocator.alloc(PyValue, value.len);
        for (value, 0..) |item, i| {
            list[i] = try toPyValue(allocator, item);
        }
        // Use listFromSlice to properly allocate ArrayList on heap
        return try PyValue.listFromSlice(allocator, list);
    }

    // Tagged unions (IntResult, PyPowResult, etc.) - extract active field and convert
    // This handles unions like IntResult{ .small = 5 } -> PyValue{ .int = 5 }
    if (info == .@"union" and info.@"union".tag_type != null) {
        // Get the active tag and extract the value
        const tag = std.meta.activeTag(value);
        inline for (info.@"union".fields) |field| {
            if (tag == @field(std.meta.Tag(T), field.name)) {
                const field_value = @field(value, field.name);
                return try toPyValue(allocator, field_value);
            }
        }
    }

    // Fallback: store as opaque pointer
    return .{ .ptr = @ptrCast(@constCast(&value)) };
}

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
