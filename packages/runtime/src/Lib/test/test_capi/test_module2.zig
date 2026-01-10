//! test.test_capi.test_module2 - C API Module Tests Part 2 - Type Objects
const std = @import("std");

/// Type object structure
pub const PyTypeObject = struct {
    name: []const u8,
    basicsize: usize,
    flags: TypeFlags = .{},
    base: ?*const PyTypeObject = null,
    dict: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, basicsize: usize) PyTypeObject {
        return .{
            .name = name,
            .basicsize = basicsize,
            .dict = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PyTypeObject) void {
        self.dict.deinit();
    }

    pub fn is_subtype(self: *const PyTypeObject, other: *const PyTypeObject) bool {
        if (self == other) return true;
        if (self.base) |base| {
            return base.is_subtype(other);
        }
        return false;
    }
};

/// Type flags
pub const TypeFlags = packed struct {
    heaptype: bool = false,
    basetype: bool = false,
    ready: bool = false,
    readying: bool = false,
    have_gc: bool = false,
    have_finalize: bool = false,
    have_vectorcall: bool = false,
    _padding: u1 = 0,
};

/// Number methods
pub const PyNumberMethods = struct {
    add: ?*const fn (a: i64, b: i64) i64 = null,
    sub: ?*const fn (a: i64, b: i64) i64 = null,
    mul: ?*const fn (a: i64, b: i64) i64 = null,
    neg: ?*const fn (a: i64) i64 = null,
    abs: ?*const fn (a: i64) i64 = null,
};

fn default_add(a: i64, b: i64) i64 {
    return a + b;
}

fn default_sub(a: i64, b: i64) i64 {
    return a - b;
}

fn default_mul(a: i64, b: i64) i64 {
    return a * b;
}

fn default_neg(a: i64) i64 {
    return -a;
}

fn default_abs(a: i64) i64 {
    return if (a < 0) -a else a;
}

/// Type ready check
pub fn PyType_Ready(type_obj: *PyTypeObject) !void {
    if (type_obj.flags.ready) return;
    if (type_obj.flags.readying) return error.RecursiveReady;

    type_obj.flags.readying = true;
    defer type_obj.flags.readying = false;

    if (type_obj.base) |base| {
        if (!base.flags.ready) {
            return error.BaseNotReady;
        }
    }

    type_obj.flags.ready = true;
}

test "PyTypeObject creation" {
    const allocator = std.testing.allocator;
    var type_obj = PyTypeObject.init(allocator, "TestType", 64);
    defer type_obj.deinit();

    try std.testing.expectEqualStrings("TestType", type_obj.name);
    try std.testing.expectEqual(@as(usize, 64), type_obj.basicsize);
}

test "PyType_Ready" {
    const allocator = std.testing.allocator;
    var type_obj = PyTypeObject.init(allocator, "ReadyType", 32);
    defer type_obj.deinit();

    try std.testing.expect(!type_obj.flags.ready);
    try PyType_Ready(&type_obj);
    try std.testing.expect(type_obj.flags.ready);
}

test "type inheritance" {
    const allocator = std.testing.allocator;
    var base_type = PyTypeObject.init(allocator, "BaseType", 16);
    defer base_type.deinit();
    try PyType_Ready(&base_type);

    var derived_type = PyTypeObject.init(allocator, "DerivedType", 32);
    defer derived_type.deinit();
    derived_type.base = &base_type;
    try PyType_Ready(&derived_type);

    try std.testing.expect(derived_type.is_subtype(&base_type));
    try std.testing.expect(!base_type.is_subtype(&derived_type));
}

test "PyNumberMethods" {
    const nm = PyNumberMethods{
        .add = default_add,
        .sub = default_sub,
        .mul = default_mul,
        .neg = default_neg,
        .abs = default_abs,
    };

    try std.testing.expectEqual(@as(i64, 5), nm.add.?(2, 3));
    try std.testing.expectEqual(@as(i64, -1), nm.sub.?(2, 3));
    try std.testing.expectEqual(@as(i64, 6), nm.mul.?(2, 3));
    try std.testing.expectEqual(@as(i64, -5), nm.neg.?(5));
    try std.testing.expectEqual(@as(i64, 5), nm.abs.?(-5));
}

test "TypeFlags" {
    var flags = TypeFlags{};
    try std.testing.expect(!flags.heaptype);
    try std.testing.expect(!flags.ready);

    flags.heaptype = true;
    flags.ready = true;
    try std.testing.expect(flags.heaptype);
    try std.testing.expect(flags.ready);
}
