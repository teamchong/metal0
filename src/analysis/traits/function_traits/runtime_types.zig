/// Runtime type categories and comptime patterns for type dispatch
/// Helpers for generating comptime type checks when exact type isn't known
const std = @import("std");

/// Categories of runtime types that need special handling in codegen
pub const RuntimeTypeCategory = enum {
    /// Standard slice/array - use direct indexing and .len
    slice,
    /// ArrayList - use .items for indexing and .items.len for length
    array_list,
    /// BigInt - needs .toInt() conversion
    big_int,
    /// PyValue union - needs accessor methods or switch
    py_value,
    /// HashMap/AutoHashMap - use .get()/.put()/.count()
    hash_map,
    /// Iterator - has .next() method
    iterator,
    /// Standard integer - direct arithmetic
    integer,
    /// Unknown - need full comptime dispatch
    unknown,
};

/// Helper to generate comptime type check code for a given category
/// Returns Zig code that evaluates to true if the type matches
pub fn comptimeTypeCheck(category: RuntimeTypeCategory) []const u8 {
    return switch (category) {
        .slice => "@typeInfo(@TypeOf(__val)) == .pointer and @typeInfo(@TypeOf(__val)).pointer.size == .slice",
        .array_list => "@typeInfo(@TypeOf(__val)) == .@\"struct\" and @hasField(@TypeOf(__val), \"items\") and @hasField(@TypeOf(__val), \"capacity\")",
        .big_int => "@TypeOf(__val) == bigint.BigInt",
        .py_value => "@TypeOf(__val) == runtime.PyValue",
        .hash_map => "@typeInfo(@TypeOf(__val)) == .@\"struct\" and @hasDecl(@TypeOf(__val), \"count\")",
        .iterator => "@typeInfo(@TypeOf(__val)) == .@\"struct\" and @hasDecl(@TypeOf(__val), \"next\")",
        .integer => "@typeInfo(@TypeOf(__val)) == .int or @typeInfo(@TypeOf(__val)) == .comptime_int",
        .unknown => "true",
    };
}

/// Generate a comptime dispatch expression that handles multiple type categories
/// Usage: genComptimeDispatch("my_var", &.{.array_list, .slice}, &.{".items[idx]", "[idx]"})
/// Returns code like: if (comptime is_arraylist) __val.items[idx] else __val[idx]
pub fn genComptimeDispatch(
    allocator: std.mem.Allocator,
    var_name: []const u8,
    categories: []const RuntimeTypeCategory,
    expressions: []const []const u8,
) ![]const u8 {
    if (categories.len != expressions.len) return error.InvalidArgument;
    if (categories.len == 0) return "";
    if (categories.len == 1) {
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ var_name, expressions[0] });
    }

    var result = std.ArrayList(u8).init(allocator);
    const writer = result.writer();

    // Generate nested if-else chain
    try writer.print("blk: {{ const __val = {s}; break :blk ", .{var_name});

    for (categories[0 .. categories.len - 1], expressions[0 .. expressions.len - 1], 0..) |cat, expr, i| {
        if (i > 0) try writer.writeAll(" else ");
        try writer.print("if ({s}) __val{s}", .{ comptimeTypeCheck(cat), expr });
    }

    // Final else case
    try writer.print(" else __val{s}; }}", .{expressions[expressions.len - 1]});

    return result.toOwnedSlice();
}

/// Standard comptime patterns for common operations
pub const ComptimePatterns = struct {
    /// Get length of a value (handles slice, ArrayList, HashMap, PyValue)
    pub const length =
        \\blk: { const __t = @TypeOf(__val); break :blk if (@typeInfo(__t) == .@"struct" and @hasField(__t, "items")) __val.items.len else if (@typeInfo(__t) == .@"struct" and @hasDecl(__t, "count")) __val.count() else if (__t == runtime.PyValue) __val.pyLen() else __val.len; }
    ;

    /// Index into a value (handles slice, ArrayList, PyValue)
    pub const index =
        \\blk: { const __t = @TypeOf(__val); break :blk if (@typeInfo(__t) == .@"struct" and @hasField(__t, "items")) __val.items[__idx] else if (__t == runtime.PyValue) __val.pyAt(__idx) else __val[__idx]; }
    ;

    /// Convert to i64 (handles int, BigInt, PyValue)
    pub const to_int =
        \\blk: { const __t = @TypeOf(__val); break :blk if (__t == bigint.BigInt) __val.toInt() else if (__t == runtime.PyValue) __val.asInt() else @as(i64, @intCast(__val)); }
    ;

    /// Convert to f64 (handles float, int, BigInt, PyValue)
    pub const to_float =
        \\blk: { const __t = @TypeOf(__val); break :blk if (__t == bigint.BigInt) __val.toFloat() else if (__t == runtime.PyValue) __val.asFloat() else if (@typeInfo(__t) == .int) @as(f64, @floatFromInt(__val)) else @as(f64, @floatCast(__val)); }
    ;

    /// Safe shift amount (converts i64 to u6 for bit shifts)
    pub const shift_amount =
        \\@as(u6, @intCast(@mod(__val, 64)))
    ;

    /// Iterator slice (handles ArrayList vs slice)
    pub const iter_slice =
        \\blk: { const __t = @TypeOf(__val); break :blk if (@typeInfo(__t) == .@"struct" and @hasField(__t, "items")) __val.items else __val; }
    ;
};
