//! Python 'reprlib' module - Alternate repr() implementation with size limits
//!
//! Provides a class that implements repr() methods with limits on object sizes
//! to avoid excessive memory usage or infinite recursion.
//!
//! Mirrors: CPython Lib/reprlib.py

const std = @import("std");

// ============================================================================
// Repr class
// ============================================================================

/// A class which provides repr() methods with configurable limits
pub const Repr = struct {
    allocator: std.mem.Allocator,

    // Limits for various types
    maxlevel: usize = 6,
    maxtuple: usize = 6,
    maxlist: usize = 6,
    maxarray: usize = 5,
    maxdict: usize = 4,
    maxset: usize = 6,
    maxfrozenset: usize = 6,
    maxdeque: usize = 6,
    maxstring: usize = 30,
    maxlong: usize = 40,
    maxother: usize = 30,

    /// Recursion depth tracking
    fillvalue: []const u8 = "...",

    pub fn init(allocator: std.mem.Allocator) Repr {
        return .{ .allocator = allocator };
    }

    /// Generate a repr with size limits
    pub fn repr(self: *const Repr, obj: anytype) ![]u8 {
        return self.repr1(obj, self.maxlevel);
    }

    /// Internal repr with level tracking
    fn repr1(self: *const Repr, obj: anytype, level: usize) ![]u8 {
        const T = @TypeOf(obj);

        if (level <= 0) {
            return self.allocator.dupe(u8, self.fillvalue);
        }

        // Handle different types
        if (T == []const u8 or T == []u8) {
            return self.repr_string(obj);
        } else if (@typeInfo(T) == .pointer) {
            if (@typeInfo(T).pointer.size == .Slice) {
                return self.repr_list(obj, level);
            }
        } else if (@typeInfo(T) == .int) {
            return self.repr_int(obj);
        } else if (@typeInfo(T) == .float) {
            return self.repr_float(obj);
        } else if (@typeInfo(T) == .bool) {
            return self.allocator.dupe(u8, if (obj) "True" else "False");
        }

        // Default: use standard formatting
        return std.fmt.allocPrint(self.allocator, "{any}", .{obj});
    }

    /// Repr for strings with length limit
    pub fn repr_string(self: *const Repr, s: []const u8) ![]u8 {
        if (s.len <= self.maxstring) {
            return std.fmt.allocPrint(self.allocator, "'{s}'", .{s});
        }

        // Truncate and add ellipsis
        const half = self.maxstring / 2;
        const prefix = s[0..half];
        const suffix = s[s.len - half ..];
        return std.fmt.allocPrint(self.allocator, "'{s}...{s}'", .{ prefix, suffix });
    }

    /// Repr for integers with digit limit
    pub fn repr_int(self: *const Repr, n: anytype) ![]u8 {
        const str = try std.fmt.allocPrint(self.allocator, "{d}", .{n});

        if (str.len <= self.maxlong) {
            return str;
        }

        defer self.allocator.free(str);

        // Truncate long integers
        const half = self.maxlong / 2;
        const prefix = str[0..half];
        const suffix = str[str.len - half ..];
        return std.fmt.allocPrint(self.allocator, "{s}...{s}", .{ prefix, suffix });
    }

    /// Repr for floats
    pub fn repr_float(self: *const Repr, f: anytype) ![]u8 {
        _ = self;
        return std.fmt.allocPrint(self.allocator, "{d}", .{f});
    }

    /// Repr for lists/slices with item limit
    pub fn repr_list(self: *const Repr, items: anytype, level: usize) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        try result.append('[');

        const max = @min(items.len, self.maxlist);
        for (items[0..max], 0..) |item, i| {
            if (i > 0) {
                try result.appendSlice(", ");
            }
            const item_repr = try self.repr1(item, level - 1);
            defer self.allocator.free(item_repr);
            try result.appendSlice(item_repr);
        }

        if (items.len > self.maxlist) {
            try result.appendSlice(", ...");
        }

        try result.append(']');
        return result.toOwnedSlice();
    }

    /// Repr for tuples with item limit
    pub fn repr_tuple(self: *const Repr, items: anytype, level: usize) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        try result.append('(');

        const max = @min(items.len, self.maxtuple);
        for (items[0..max], 0..) |item, i| {
            if (i > 0) {
                try result.appendSlice(", ");
            }
            const item_repr = try self.repr1(item, level - 1);
            defer self.allocator.free(item_repr);
            try result.appendSlice(item_repr);
        }

        if (items.len > self.maxtuple) {
            try result.appendSlice(", ...");
        } else if (items.len == 1) {
            try result.append(',');
        }

        try result.append(')');
        return result.toOwnedSlice();
    }

    /// Repr for sets with item limit
    pub fn repr_set(self: *const Repr, items: anytype, level: usize, frozen: bool) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        if (frozen) {
            try result.appendSlice("frozenset({");
        } else {
            try result.append('{');
        }

        const max_items = if (frozen) self.maxfrozenset else self.maxset;
        var count: usize = 0;

        for (items) |item| {
            if (count >= max_items) {
                try result.appendSlice(", ...");
                break;
            }
            if (count > 0) {
                try result.appendSlice(", ");
            }
            const item_repr = try self.repr1(item, level - 1);
            defer self.allocator.free(item_repr);
            try result.appendSlice(item_repr);
            count += 1;
        }

        if (frozen) {
            try result.appendSlice("})");
        } else {
            try result.append('}');
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Module-level functions
// ============================================================================

/// Default Repr instance
var default_repr: ?Repr = null;

/// Get the default Repr instance
fn getDefaultRepr(allocator: std.mem.Allocator) *Repr {
    if (default_repr == null) {
        default_repr = Repr.init(allocator);
    }
    return &default_repr.?;
}

/// Module-level repr function using default limits
pub fn repr(allocator: std.mem.Allocator, obj: anytype) ![]u8 {
    const r = getDefaultRepr(allocator);
    return r.repr(obj);
}

// ============================================================================
// recursive_repr decorator support
// ============================================================================

/// Thread-local set of objects currently being repr'd (for recursion detection)
threadlocal var repr_running: ?std.AutoHashMap(usize, void) = null;

/// Check if an object is currently being repr'd (recursion detection)
pub fn isReprRunning(ptr: usize) bool {
    if (repr_running) |*set| {
        return set.contains(ptr);
    }
    return false;
}

/// Mark an object as being repr'd
pub fn markReprRunning(allocator: std.mem.Allocator, ptr: usize) !void {
    if (repr_running == null) {
        repr_running = std.AutoHashMap(usize, void).init(allocator);
    }
    try repr_running.?.put(ptr, {});
}

/// Unmark an object as being repr'd
pub fn unmarkReprRunning(ptr: usize) void {
    if (repr_running) |*set| {
        _ = set.remove(ptr);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "Repr init" {
    const r = Repr.init(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 6), r.maxlevel);
    try std.testing.expectEqual(@as(usize, 30), r.maxstring);
}

test "repr_string short" {
    const r = Repr.init(std.testing.allocator);
    const result = try r.repr_string("hello");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("'hello'", result);
}

test "repr_string long" {
    var r = Repr.init(std.testing.allocator);
    r.maxstring = 10;
    const result = try r.repr_string("hello world this is a long string");
    defer std.testing.allocator.free(result);
    // Should truncate and add ellipsis
    try std.testing.expect(std.mem.indexOf(u8, result, "...") != null);
}

test "repr_int normal" {
    const r = Repr.init(std.testing.allocator);
    const result = try r.repr_int(@as(i32, 12345));
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("12345", result);
}

test "fillvalue" {
    const r = Repr.init(std.testing.allocator);
    try std.testing.expectEqualStrings("...", r.fillvalue);
}
