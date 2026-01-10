//! test.test_ctypes.test_functions - Tests for ctypes functions
//! Reference: cpython/Lib/test/test_ctypes/test_functions.py

const std = @import("std");
const _support = @import("_support.zig");

pub fn CFUNCTYPE(comptime ReturnType: type, comptime ArgTypes: anytype) type {
    _ = ArgTypes;
    return struct {
        const Self = @This();
        const Return = ReturnType;
        ptr: ?*anyopaque = null,

        pub fn init(p: ?*anyopaque) Self { return .{ .ptr = p }; }
        pub fn isValid(self: Self) bool { return self.ptr != null; }
    };
}

pub fn PYFUNCTYPE(comptime ReturnType: type, comptime ArgTypes: anytype) type {
    return CFUNCTYPE(ReturnType, ArgTypes);
}

pub const FunctionInfo = struct {
    name: []const u8,
    restype: []const u8 = "c_int",
    argtypes: []const []const u8 = &.{},
    errcheck: ?*const fn (anytype) anytype = null,
};

pub const LibraryFunction = struct {
    name: []const u8,
    ptr: ?*anyopaque = null,
    
    pub fn init(name: []const u8) @This() { return .{ .name = name }; }
    pub fn isLoaded(self: @This()) bool { return self.ptr != null; }
};

test "cfunctype" {
    const AddFunc = CFUNCTYPE(i32, .{ i32, i32 });
    const f = AddFunc.init(null);
    try std.testing.expect(!f.isValid());
}

test "function_info" {
    const info = FunctionInfo{ .name = "printf", .restype = "c_int" };
    try std.testing.expectEqualStrings("printf", info.name);
}
