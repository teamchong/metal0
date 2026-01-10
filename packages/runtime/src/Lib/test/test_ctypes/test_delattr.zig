//! test.test_ctypes.test_delattr - Tests for attribute deletion
//! Reference: cpython/Lib/test/test_ctypes/test_delattr.py
//!
//! Tests for deleting attributes from ctypes objects including
//! field deletion, resettable attributes, and error handling.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Deletable Attribute Container
// ============================================================================

/// An object that supports attribute deletion
pub fn DeletableObject(comptime max_attrs: usize) type {
    return struct {
        const Self = @This();

        const AttrEntry = struct {
            name: []const u8,
            value: i64,
            deleted: bool,
        };

        attrs: [max_attrs]?AttrEntry = [_]?AttrEntry{null} ** max_attrs,
        attr_count: usize = 0,

        pub fn init() Self {
            return .{};
        }

        /// Set an attribute
        pub fn setAttr(self: *Self, name: []const u8, value: i64) !void {
            // Check if attribute exists
            for (&self.attrs) |*entry| {
                if (entry.*) |*e| {
                    if (std.mem.eql(u8, e.name, name)) {
                        e.value = value;
                        e.deleted = false;
                        return;
                    }
                }
            }

            // Add new attribute
            if (self.attr_count >= max_attrs) {
                return error.TooManyAttributes;
            }

            for (&self.attrs) |*entry| {
                if (entry.* == null) {
                    entry.* = .{ .name = name, .value = value, .deleted = false };
                    self.attr_count += 1;
                    return;
                }
            }
        }

        /// Get an attribute
        pub fn getAttr(self: *const Self, name: []const u8) ?i64 {
            for (self.attrs) |entry| {
                if (entry) |e| {
                    if (std.mem.eql(u8, e.name, name) and !e.deleted) {
                        return e.value;
                    }
                }
            }
            return null;
        }

        /// Delete an attribute
        pub fn delAttr(self: *Self, name: []const u8) !void {
            for (&self.attrs) |*entry| {
                if (entry.*) |*e| {
                    if (std.mem.eql(u8, e.name, name)) {
                        if (e.deleted) {
                            return error.AttributeDeleted;
                        }
                        e.deleted = true;
                        return;
                    }
                }
            }
            return error.AttributeNotFound;
        }

        /// Check if attribute exists (not deleted)
        pub fn hasAttr(self: *const Self, name: []const u8) bool {
            return self.getAttr(name) != null;
        }

        /// List all active attributes
        pub fn listAttrs(self: *const Self) []const []const u8 {
            var result: [max_attrs][]const u8 = undefined;
            var count: usize = 0;

            for (self.attrs) |entry| {
                if (entry) |e| {
                    if (!e.deleted) {
                        result[count] = e.name;
                        count += 1;
                    }
                }
            }

            return result[0..count];
        }
    };
}

// ============================================================================
// Structure with Deletable Fields
// ============================================================================

/// Structure that tracks field deletion
pub fn DeletableStruct(comptime fields: []const FieldInfo) type {
    return struct {
        const Self = @This();
        pub const _fields_ = fields;

        values: [fields.len]?i64 = [_]?i64{null} ** fields.len,

        pub fn init() Self {
            return .{};
        }

        /// Set a field value
        pub fn setField(self: *Self, comptime name: []const u8) *?i64 {
            inline for (fields, 0..) |field, i| {
                if (std.mem.eql(u8, field.name, name)) {
                    return &self.values[i];
                }
            }
            @compileError("Unknown field: " ++ name);
        }

        /// Get a field value
        pub fn getField(self: *const Self, comptime name: []const u8) ?i64 {
            inline for (fields, 0..) |field, i| {
                if (std.mem.eql(u8, field.name, name)) {
                    return self.values[i];
                }
            }
            @compileError("Unknown field: " ++ name);
        }

        /// Delete a field (set to null)
        pub fn delField(self: *Self, comptime name: []const u8) void {
            inline for (fields, 0..) |field, i| {
                if (std.mem.eql(u8, field.name, name)) {
                    self.values[i] = null;
                    return;
                }
            }
            @compileError("Unknown field: " ++ name);
        }
    };
}

pub const FieldInfo = struct {
    name: []const u8,
    deletable: bool = true,
};

// ============================================================================
// Example Types
// ============================================================================

pub const SimpleObject = DeletableObject(16);

pub const Point = DeletableStruct(&.{
    .{ .name = "x", .deletable = true },
    .{ .name = "y", .deletable = true },
});

// ============================================================================
// Test Cases
// ============================================================================

fn testSetAndGetAttr() !void {
    var obj = SimpleObject.init();

    try obj.setAttr("foo", 42);
    try std.testing.expectEqual(@as(?i64, 42), obj.getAttr("foo"));

    try obj.setAttr("bar", 100);
    try std.testing.expectEqual(@as(?i64, 100), obj.getAttr("bar"));
}

fn testDelAttr() !void {
    var obj = SimpleObject.init();

    try obj.setAttr("foo", 42);
    try std.testing.expectEqual(@as(?i64, 42), obj.getAttr("foo"));

    try obj.delAttr("foo");
    try std.testing.expectEqual(@as(?i64, null), obj.getAttr("foo"));
}

fn testDelAttrNotFound() !void {
    var obj = SimpleObject.init();
    try std.testing.expectError(error.AttributeNotFound, obj.delAttr("nonexistent"));
}

fn testDelAttrTwice() !void {
    var obj = SimpleObject.init();

    try obj.setAttr("foo", 42);
    try obj.delAttr("foo");
    try std.testing.expectError(error.AttributeDeleted, obj.delAttr("foo"));
}

fn testHasAttr() !void {
    var obj = SimpleObject.init();

    try std.testing.expect(!obj.hasAttr("foo"));

    try obj.setAttr("foo", 42);
    try std.testing.expect(obj.hasAttr("foo"));

    try obj.delAttr("foo");
    try std.testing.expect(!obj.hasAttr("foo"));
}

fn testResetAttr() !void {
    var obj = SimpleObject.init();

    try obj.setAttr("foo", 42);
    try obj.delAttr("foo");
    try obj.setAttr("foo", 100); // Re-add after delete

    try std.testing.expectEqual(@as(?i64, 100), obj.getAttr("foo"));
}

fn testStructFieldSet() !void {
    var pt = Point.init();

    pt.setField("x").* = 10;
    pt.setField("y").* = 20;

    try std.testing.expectEqual(@as(?i64, 10), pt.getField("x"));
    try std.testing.expectEqual(@as(?i64, 20), pt.getField("y"));
}

fn testStructFieldDel() !void {
    var pt = Point.init();

    pt.setField("x").* = 10;
    try std.testing.expectEqual(@as(?i64, 10), pt.getField("x"));

    pt.delField("x");
    try std.testing.expectEqual(@as(?i64, null), pt.getField("x"));
}

fn testListAttrs() !void {
    var obj = SimpleObject.init();

    try obj.setAttr("a", 1);
    try obj.setAttr("b", 2);
    try obj.setAttr("c", 3);

    const attrs = obj.listAttrs();
    try std.testing.expectEqual(@as(usize, 3), attrs.len);

    try obj.delAttr("b");
    const attrs2 = obj.listAttrs();
    try std.testing.expectEqual(@as(usize, 2), attrs2.len);
}

fn testTooManyAttrs() !void {
    var obj = DeletableObject(2).init();

    try obj.setAttr("a", 1);
    try obj.setAttr("b", 2);
    try std.testing.expectError(error.TooManyAttributes, obj.setAttr("c", 3));
}

fn testUpdateAttr() !void {
    var obj = SimpleObject.init();

    try obj.setAttr("foo", 42);
    try obj.setAttr("foo", 100); // Update existing

    try std.testing.expectEqual(@as(?i64, 100), obj.getAttr("foo"));
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "set_and_get_attr" {
    try testSetAndGetAttr();
}

test "del_attr" {
    try testDelAttr();
}

test "del_attr_not_found" {
    try testDelAttrNotFound();
}

test "del_attr_twice" {
    try testDelAttrTwice();
}

test "has_attr" {
    try testHasAttr();
}

test "reset_attr" {
    try testResetAttr();
}

test "struct_field_set" {
    try testStructFieldSet();
}

test "struct_field_del" {
    try testStructFieldDel();
}

test "list_attrs" {
    try testListAttrs();
}

test "too_many_attrs" {
    try testTooManyAttrs();
}

test "update_attr" {
    try testUpdateAttr();
}
