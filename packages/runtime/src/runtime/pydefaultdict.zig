//! PyDefaultDict - Python-compatible defaultdict implementation
//!
//! Mirrors Python's collections.defaultdict behavior:
//! - default_factory can be None, list, int, or any callable
//! - __missing__(key) creates default value and inserts it
//! - Subscript access auto-creates missing keys

const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;

/// Factory type - stores which factory to use
/// Stores the factory name for Python-compatible comparison
pub const FactoryType = union(enum) {
    none: void,
    list: void,
    int: void,
    str: void,
    dict: void,
    set: void,
    custom: []const u8, // Custom callable name for comparison

    pub fn eql(self: FactoryType, other: anytype) bool {
        const T = @TypeOf(other);
        if (T == FactoryType) {
            return std.meta.eql(self, other);
        }
        if (T == @TypeOf(null)) {
            return self == .none;
        }
        // Compare with string type names like "list", "int"
        if (T == []const u8) {
            return switch (self) {
                .none => std.mem.eql(u8, other, "None") or other.len == 0,
                .list => std.mem.eql(u8, other, "list"),
                .int => std.mem.eql(u8, other, "int"),
                .str => std.mem.eql(u8, other, "str"),
                .dict => std.mem.eql(u8, other, "dict"),
                .set => std.mem.eql(u8, other, "set"),
                .custom => |n| std.mem.eql(u8, n, other),
            };
        }
        return false;
    }

    pub fn isNone(self: FactoryType) bool {
        return self == .none;
    }

    /// Get factory name for Python repr()
    pub fn name(self: FactoryType) []const u8 {
        return switch (self) {
            .none => "None",
            .list => "list",
            .int => "int",
            .str => "str",
            .dict => "dict",
            .set => "set",
            .custom => |n| n,
        };
    }
};

/// Python-compatible defaultdict with string keys
pub fn PyDefaultDict(comptime V: type) type {
    return struct {
        const Self = @This();
        const HashMap = std.ArrayHashMap([]const u8, V, std.array_hash_map.StringContext, true);

        /// The underlying hashmap storage
        map: HashMap,
        /// The allocator for creating new values
        allocator: std.mem.Allocator,
        /// The default factory type
        default_factory: FactoryType,

        /// Initialize with no factory (None)
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .map = HashMap.init(allocator),
                .allocator = allocator,
                .default_factory = .none,
            };
        }

        /// Initialize with a factory
        pub fn initWithFactory(allocator: std.mem.Allocator, factory: FactoryType) Self {
            return .{
                .map = HashMap.init(allocator),
                .allocator = allocator,
                .default_factory = factory,
            };
        }

        /// Get existing value or null
        pub fn get(self: *const Self, key: []const u8) ?V {
            return self.map.get(key);
        }

        /// Get value, creating default if missing (Python subscript behavior)
        pub fn getOrCreate(self: *Self, key: []const u8) !V {
            if (self.map.get(key)) |existing| {
                return existing;
            }
            return try self.@"__missing__"(key);
        }

        /// Python's __missing__ - called when key not in dict
        pub fn @"__missing__"(self: *Self, key: []const u8) !V {
            if (self.default_factory.isNone()) {
                return error.KeyError;
            }

            const value = self.callFactory();
            try self.map.put(self.allocator, key, value);
            return value;
        }

        fn callFactory(self: *Self) V {
            return switch (self.default_factory) {
                .none => if (V == PyValue) PyValue.none else @as(V, undefined),
                .list => {
                    if (V == std.ArrayListUnmanaged(PyValue)) {
                        return std.ArrayListUnmanaged(PyValue){};
                    }
                    if (V == PyValue) {
                        var list = std.ArrayListUnmanaged(PyValue){};
                        return PyValue{ .list = &list };
                    }
                    return @as(V, undefined);
                },
                .int => {
                    if (V == i64) return @as(i64, 0);
                    if (V == PyValue) return PyValue{ .int = 0 };
                    return @as(V, undefined);
                },
                .str => {
                    if (V == []const u8) return "";
                    if (V == PyValue) return PyValue{ .string = "" };
                    return @as(V, undefined);
                },
                .dict, .set, .custom => if (V == PyValue) PyValue.none else @as(V, undefined),
            };
        }

        /// Put a key-value pair
        pub fn put(self: *Self, key: []const u8, value: V) !void {
            try self.map.put(self.allocator, key, value);
        }

        /// Check if key exists
        pub fn contains(self: *const Self, key: []const u8) bool {
            return self.map.contains(key);
        }

        /// Get keys slice
        pub fn keys(self: *const Self) [][]const u8 {
            return self.map.keys();
        }

        /// Get values slice
        pub fn values(self: *const Self) []V {
            return self.map.values();
        }

        /// Get entry count
        pub fn count(self: *const Self) usize {
            return self.map.count();
        }

        /// Copy to new defaultdict
        pub fn copy(self: *const Self) !Self {
            var new_dict = Self{
                .map = HashMap.init(self.allocator),
                .allocator = self.allocator,
                .default_factory = self.default_factory,
            };
            for (self.map.keys(), self.map.values()) |k, v| {
                try new_dict.map.put(self.allocator, k, v);
            }
            return new_dict;
        }
    };
}

/// Int-keyed defaultdict
pub fn IntDefaultDict(comptime V: type) type {
    return struct {
        const Self = @This();
        const HashMap = std.AutoArrayHashMap(i64, V);

        map: HashMap,
        allocator: std.mem.Allocator,
        default_factory: FactoryType,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .map = HashMap.init(allocator),
                .allocator = allocator,
                .default_factory = .none,
            };
        }

        pub fn initWithFactory(allocator: std.mem.Allocator, factory: FactoryType) Self {
            return .{
                .map = HashMap.init(allocator),
                .allocator = allocator,
                .default_factory = factory,
            };
        }

        pub fn get(self: *const Self, key: i64) ?V {
            return self.map.get(key);
        }

        pub fn getOrCreate(self: *Self, key: i64) !V {
            if (self.map.get(key)) |existing| {
                return existing;
            }
            return try self.@"__missing__"(key);
        }

        /// Python's __getitem__ - alias for getOrCreate (triggers __missing__ for missing keys)
        pub fn @"__getitem__"(self: *Self, key: i64) !V {
            return try self.getOrCreate(key);
        }

        pub fn @"__missing__"(self: *Self, key: i64) !V {
            if (self.default_factory.isNone()) {
                return error.KeyError;
            }

            const value = self.callFactory();
            try self.map.put(key, value);
            return value;
        }

        fn callFactory(self: *Self) V {
            return switch (self.default_factory) {
                .none => if (V == PyValue) PyValue.none else @as(V, undefined),
                .list => {
                    if (V == std.ArrayListUnmanaged(PyValue)) {
                        return std.ArrayListUnmanaged(PyValue){};
                    }
                    if (V == std.ArrayListUnmanaged(i64)) {
                        return std.ArrayListUnmanaged(i64){};
                    }
                    if (V == PyValue) {
                        var list = std.ArrayListUnmanaged(PyValue){};
                        return PyValue{ .list = &list };
                    }
                    return @as(V, undefined);
                },
                .int => {
                    if (V == i64) return @as(i64, 0);
                    if (V == PyValue) return PyValue{ .int = 0 };
                    return @as(V, undefined);
                },
                .str => {
                    if (V == []const u8) return "";
                    if (V == PyValue) return PyValue{ .string = "" };
                    return @as(V, undefined);
                },
                .dict, .set, .custom => if (V == PyValue) PyValue.none else @as(V, undefined),
            };
        }

        pub fn put(self: *Self, key: i64, value: V) !void {
            try self.map.put(key, value);
        }

        pub fn contains(self: *const Self, key: i64) bool {
            return self.map.contains(key);
        }

        pub fn keys(self: *const Self) []i64 {
            return self.map.keys();
        }

        pub fn values(self: *const Self) []V {
            return self.map.values();
        }

        pub fn count(self: *const Self) usize {
            return self.map.count();
        }

        pub fn copy(self: *const Self) !Self {
            var new_dict = Self{
                .map = HashMap.init(self.allocator),
                .allocator = self.allocator,
                .default_factory = self.default_factory,
            };
            for (self.map.keys(), self.map.values()) |k, v| {
                try new_dict.map.put(k, v);
            }
            return new_dict;
        }

        /// Iterator for the underlying map
        pub fn iterator(self: *const Self) HashMap.Iterator {
            return self.map.iterator();
        }
    };
}
