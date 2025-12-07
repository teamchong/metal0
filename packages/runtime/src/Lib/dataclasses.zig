//! CPython source: Lib/dataclasses.py
//!
//! Provides a decorator and functions for automatically adding generated
//! special methods to classes.
//!
//! Mirrors: CPython Lib/dataclasses.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Sentinel value to detect missing values
pub const MISSING = struct {
    pub fn isMissing(value: anytype) bool {
        return @TypeOf(value) == @TypeOf(MISSING);
    }
};

/// Sentinel to indicate a field should use default_factory
pub const KW_ONLY = struct {};

// ============================================================================
// Field descriptor
// ============================================================================

/// Field configuration for a dataclass field
pub fn Field(comptime T: type) type {
    return struct {
        const Self = @This();

        name: []const u8,
        field_type: type = T,
        default: ?T = null,
        default_factory: ?*const fn () T = null,
        init: bool = true,
        repr: bool = true,
        hash: ?bool = null,
        compare: bool = true,
        metadata: ?*const anyopaque = null,
        kw_only: bool = false,

        pub fn init(name: []const u8) Self {
            return .{ .name = name };
        }

        pub fn withDefault(self: Self, default: T) Self {
            var new = self;
            new.default = default;
            return new;
        }

        pub fn withDefaultFactory(self: Self, factory: *const fn () T) Self {
            var new = self;
            new.default_factory = factory;
            return new;
        }

        pub fn withInit(self: Self, val: bool) Self {
            var new = self;
            new.init = val;
            return new;
        }

        pub fn withRepr(self: Self, val: bool) Self {
            var new = self;
            new.repr = val;
            return new;
        }

        pub fn withCompare(self: Self, val: bool) Self {
            var new = self;
            new.compare = val;
            return new;
        }

        pub fn withKwOnly(self: Self, val: bool) Self {
            var new = self;
            new.kw_only = val;
            return new;
        }
    };
}

/// Create a field with custom configuration
pub fn field(comptime T: type, name: []const u8) Field(T) {
    return Field(T).init(name);
}

// ============================================================================
// Dataclass options
// ============================================================================

/// Options for dataclass decorator
pub const DataclassOptions = struct {
    init: bool = true,
    repr: bool = true,
    eq: bool = true,
    order: bool = false,
    unsafe_hash: bool = false,
    frozen: bool = false,
    match_args: bool = true,
    kw_only: bool = false,
    slots: bool = false,
    weakref_slot: bool = false,
};

// ============================================================================
// Dataclass generator
// ============================================================================

/// Make a type into a dataclass with automatic method generation
pub fn Dataclass(comptime T: type, comptime options: DataclassOptions) type {
    const type_info = @typeInfo(T);

    if (type_info != .@"struct") {
        @compileError("Dataclass requires a struct type");
    }

    return struct {
        const Self = @This();
        const OriginalType = T;

        data: T,

        /// Generated __init__ method
        pub fn init(args: T) Self {
            return .{ .data = args };
        }

        /// Default constructor with default values
        pub fn initDefault() Self {
            var result: T = undefined;
            inline for (@typeInfo(T).@"struct".fields) |fld| {
                if (fld.default_value_ptr) |ptr| {
                    @field(result, fld.name) = @as(*const fld.type, @ptrCast(@alignCast(ptr))).*;
                }
            }
            return .{ .data = result };
        }

        /// Generated __repr__ method
        pub fn repr(self: Self, allocator: std.mem.Allocator) ![]u8 {
            if (!options.repr) {
                return allocator.dupe(u8, @typeName(T));
            }

            var result = std.ArrayList(u8).init(allocator);
            errdefer result.deinit();

            try result.appendSlice(@typeName(T));
            try result.append('(');

            const fields = @typeInfo(T).@"struct".fields;
            inline for (fields, 0..) |fld, i| {
                if (i > 0) {
                    try result.appendSlice(", ");
                }
                try result.appendSlice(fld.name);
                try result.append('=');

                const field_value = @field(self.data, fld.name);
                try formatField(&result, field_value);
            }

            try result.append(')');
            return result.toOwnedSlice();
        }

        fn formatField(result: *std.ArrayList(u8), value: anytype) !void {
            const VT = @TypeOf(value);
            const vt_info = @typeInfo(VT);

            switch (vt_info) {
                .int, .comptime_int => {
                    var buf: [32]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
                    try result.appendSlice(str);
                },
                .float, .comptime_float => {
                    var buf: [32]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
                    try result.appendSlice(str);
                },
                .bool => {
                    try result.appendSlice(if (value) "True" else "False");
                },
                .pointer => |ptr| {
                    if (ptr.size == .Slice and ptr.child == u8) {
                        try result.append('\'');
                        try result.appendSlice(value);
                        try result.append('\'');
                    } else {
                        try result.appendSlice("<pointer>");
                    }
                },
                .optional => {
                    if (value) |v| {
                        try formatField(result, v);
                    } else {
                        try result.appendSlice("None");
                    }
                },
                else => {
                    try result.appendSlice("<...>");
                },
            }
        }

        /// Generated __eq__ method
        pub fn eql(self: Self, other: Self) bool {
            if (!options.eq) return false;

            const fields = @typeInfo(T).@"struct".fields;
            inline for (fields) |fld| {
                const a = @field(self.data, fld.name);
                const b = @field(other.data, fld.name);
                if (!fieldsEqual(a, b)) return false;
            }
            return true;
        }

        fn fieldsEqual(a: anytype, b: @TypeOf(a)) bool {
            const AT = @TypeOf(a);
            const at_info = @typeInfo(AT);

            switch (at_info) {
                .pointer => |ptr| {
                    if (ptr.size == .Slice) {
                        return std.mem.eql(ptr.child, a, b);
                    }
                    return a == b;
                },
                .optional => {
                    if (a == null and b == null) return true;
                    if (a == null or b == null) return false;
                    return fieldsEqual(a.?, b.?);
                },
                else => return a == b,
            }
        }

        /// Generated __hash__ method (if hashable)
        pub fn hash(self: Self) u64 {
            var h: u64 = 0;
            const fields = @typeInfo(T).@"struct".fields;
            inline for (fields) |fld| {
                const field_value = @field(self.data, fld.name);
                h = hashCombine(h, hashField(field_value));
            }
            return h;
        }

        fn hashField(value: anytype) u64 {
            const VT = @TypeOf(value);
            const vt_info = @typeInfo(VT);

            switch (vt_info) {
                .int, .comptime_int => return @as(u64, @intCast(@abs(value))),
                .float => return @as(u64, @bitCast(@as(i64, @intFromFloat(value * 1000000)))),
                .bool => return if (value) 1 else 0,
                .pointer => |ptr| {
                    if (ptr.size == .Slice and ptr.child == u8) {
                        var h: u64 = 0;
                        for (value) |c| {
                            h = hashCombine(h, c);
                        }
                        return h;
                    }
                    return @intFromPtr(value);
                },
                .optional => {
                    if (value) |v| {
                        return hashField(v);
                    }
                    return 0;
                },
                else => return 0,
            }
        }

        fn hashCombine(h1: u64, h2: u64) u64 {
            return h1 ^ (h2 +% 0x9e3779b9 +% (h1 << 6) +% (h1 >> 2));
        }

        /// Generated comparison methods (if order=true)
        pub fn lessThan(self: Self, other: Self) bool {
            if (!options.order) return false;

            const fields = @typeInfo(T).@"struct".fields;
            inline for (fields) |fld| {
                const a = @field(self.data, fld.name);
                const b = @field(other.data, fld.name);
                if (compareFields(a, b)) |cmp| {
                    if (cmp < 0) return true;
                    if (cmp > 0) return false;
                }
            }
            return false;
        }

        fn compareFields(a: anytype, b: @TypeOf(a)) ?i32 {
            const AT = @TypeOf(a);
            const at_info = @typeInfo(AT);

            switch (at_info) {
                .int, .comptime_int, .float, .comptime_float => {
                    if (a < b) return -1;
                    if (a > b) return 1;
                    return 0;
                },
                .pointer => |ptr| {
                    if (ptr.size == .Slice and ptr.child == u8) {
                        return switch (std.mem.order(u8, a, b)) {
                            .lt => -1,
                            .gt => 1,
                            .eq => 0,
                        };
                    }
                    return null;
                },
                else => return null,
            }
        }

        pub fn lessThanOrEqual(self: Self, other: Self) bool {
            return self.lessThan(other) or self.eql(other);
        }

        pub fn greaterThan(self: Self, other: Self) bool {
            return other.lessThan(self);
        }

        pub fn greaterThanOrEqual(self: Self, other: Self) bool {
            return !self.lessThan(other);
        }

        /// Access fields directly
        pub fn get(self: Self, comptime field_name: []const u8) @TypeOf(@field(self.data, field_name)) {
            return @field(self.data, field_name);
        }

        /// Get the list of fields
        pub fn fields() []const std.builtin.Type.StructField {
            return @typeInfo(T).@"struct".fields;
        }

        /// Convert to tuple of field values
        pub fn astuple(self: Self) AsTupleType(T) {
            var result: AsTupleType(T) = undefined;
            const struct_fields = @typeInfo(T).@"struct".fields;
            inline for (struct_fields, 0..) |fld, i| {
                result[i] = @field(self.data, fld.name);
            }
            return result;
        }
    };
}

/// Create a dataclass with default options
pub fn dataclass(comptime T: type) type {
    return Dataclass(T, .{});
}

// ============================================================================
// Utility functions
// ============================================================================

/// Get the tuple type for a struct's fields
fn AsTupleType(comptime T: type) type {
    const fields = @typeInfo(T).@"struct".fields;
    var types: [fields.len]type = undefined;
    for (fields, 0..) |fld, i| {
        types[i] = fld.type;
    }
    return std.meta.Tuple(&types);
}

/// Get all fields of a dataclass
pub fn getFields(comptime T: type) []const std.builtin.Type.StructField {
    const type_info = @typeInfo(T);
    if (type_info == .@"struct") {
        return type_info.@"struct".fields;
    }
    return &[_]std.builtin.Type.StructField{};
}

/// Check if a type is a dataclass
pub fn isDataclass(comptime T: type) bool {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") return false;

    // Check if it has the characteristic dataclass methods
    return @hasDecl(T, "data") or @hasDecl(T, "repr") or @hasDecl(T, "eql");
}

/// Convert a dataclass instance to a dict-like struct
pub fn asdict(comptime T: type, instance: T, allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
    var result = std.StringHashMap([]const u8).init(allocator);
    errdefer result.deinit();

    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields) |fld| {
        const value = @field(instance, fld.name);
        var buf: [64]u8 = undefined;
        const str = try formatValue(&buf, value);
        try result.put(fld.name, try allocator.dupe(u8, str));
    }

    return result;
}

fn formatValue(buf: []u8, value: anytype) ![]const u8 {
    const VT = @TypeOf(value);
    const vt_info = @typeInfo(VT);

    return switch (vt_info) {
        .int, .comptime_int => std.fmt.bufPrint(buf, "{d}", .{value}) catch "<int>",
        .float, .comptime_float => std.fmt.bufPrint(buf, "{d}", .{value}) catch "<float>",
        .bool => if (value) "True" else "False",
        .pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                return value;
            }
            return "<pointer>";
        },
        else => "<...>",
    };
}

/// Create a new dataclass with some fields replaced
pub fn replace(comptime T: type, instance: T, updates: anytype) T {
    var result = instance;
    const update_info = @typeInfo(@TypeOf(updates));

    if (update_info == .@"struct") {
        inline for (update_info.@"struct".fields) |fld| {
            if (@hasField(T, fld.name)) {
                @field(result, fld.name) = @field(updates, fld.name);
            }
        }
    }

    return result;
}

/// Create a shallow copy of a dataclass instance
pub fn copy(comptime T: type, instance: T) T {
    return instance;
}

// ============================================================================
// FrozenInstanceError for frozen dataclasses
// ============================================================================

pub const FrozenInstanceError = error{
    FrozenInstanceError,
};

// ============================================================================
// Tests
// ============================================================================

test "basic dataclass" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const DataPoint = dataclass(Point);

    const p = DataPoint.init(.{ .x = 10, .y = 20 });
    try std.testing.expectEqual(@as(i32, 10), p.get("x"));
    try std.testing.expectEqual(@as(i32, 20), p.get("y"));
}

test "dataclass equality" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const DataPoint = dataclass(Point);

    const p1 = DataPoint.init(.{ .x = 10, .y = 20 });
    const p2 = DataPoint.init(.{ .x = 10, .y = 20 });
    const p3 = DataPoint.init(.{ .x = 5, .y = 20 });

    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}

test "dataclass repr" {
    const allocator = std.testing.allocator;

    const Point = struct {
        x: i32,
        y: i32,
    };

    const DataPoint = dataclass(Point);
    const p = DataPoint.init(.{ .x = 10, .y = 20 });

    const r = try p.repr(allocator);
    defer allocator.free(r);

    // Just verify it contains the expected content
    try std.testing.expect(std.mem.indexOf(u8, r, "x=10") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "y=20") != null);
}

test "dataclass with ordering" {
    const Item = struct {
        priority: i32,
        name: []const u8,
    };

    const OrderedItem = Dataclass(Item, .{ .order = true });

    const a = OrderedItem.init(.{ .priority = 1, .name = "first" });
    const b = OrderedItem.init(.{ .priority = 2, .name = "second" });

    try std.testing.expect(a.lessThan(b));
    try std.testing.expect(!b.lessThan(a));
}

test "dataclass hash" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const DataPoint = dataclass(Point);

    const p1 = DataPoint.init(.{ .x = 10, .y = 20 });
    const p2 = DataPoint.init(.{ .x = 10, .y = 20 });
    const p3 = DataPoint.init(.{ .x = 5, .y = 20 });

    try std.testing.expectEqual(p1.hash(), p2.hash());
    try std.testing.expect(p1.hash() != p3.hash());
}

test "replace" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const p = Point{ .x = 10, .y = 20 };
    const p2 = replace(Point, p, .{ .x = 100 });

    try std.testing.expectEqual(@as(i32, 100), p2.x);
    try std.testing.expectEqual(@as(i32, 20), p2.y);
}

test "getFields" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const fields = getFields(Point);
    try std.testing.expectEqual(@as(usize, 2), fields.len);
}

test "astuple" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const DataPoint = dataclass(Point);
    const p = DataPoint.init(.{ .x = 10, .y = 20 });

    const tuple = p.astuple();
    try std.testing.expectEqual(@as(i32, 10), tuple[0]);
    try std.testing.expectEqual(@as(i32, 20), tuple[1]);
}
