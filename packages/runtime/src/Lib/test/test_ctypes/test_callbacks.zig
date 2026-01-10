//! test.test_ctypes.test_callbacks - Tests for ctypes callbacks
//! Reference: cpython/Lib/test/test_ctypes/test_callbacks.py

const std = @import("std");
const _support = @import("_support.zig");

pub fn CallbackType(comptime ReturnType: type, comptime ArgsType: type) type {
    return struct {
        const Self = @This();
        callback_fn: ?*const fn (ArgsType) ReturnType = null,
        user_data: ?*anyopaque = null,

        pub fn init(func: *const fn (ArgsType) ReturnType) Self {
            return .{ .callback_fn = func };
        }

        pub fn call(self: Self, args: ArgsType) ?ReturnType {
            if (self.callback_fn) |f| return f(args);
            return null;
        }

        pub fn isValid(self: Self) bool {
            return self.callback_fn != null;
        }
    };
}

pub const IntCallback = CallbackType(i32, struct { value: i32 });

pub const CallbackRegistry = struct {
    allocator: std.mem.Allocator,
    callbacks: std.ArrayList(Entry),

    pub const Entry = struct { id: usize, ptr: *anyopaque };

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator, .callbacks = std.ArrayList(Entry).init(allocator) };
    }

    pub fn deinit(self: *@This()) void { self.callbacks.deinit(); }
    pub fn count(self: *const @This()) usize { return self.callbacks.items.len; }
};

test "int_callback" {
    const double_fn = struct {
        fn f(args: struct { value: i32 }) i32 { return args.value * 2; }
    }.f;
    const cb = IntCallback.init(double_fn);
    try std.testing.expectEqual(@as(?i32, 42), cb.call(.{ .value = 21 }));
}

test "callback_registry" {
    var reg = CallbackRegistry.init(std.testing.allocator);
    defer reg.deinit();
    try std.testing.expectEqual(@as(usize, 0), reg.count());
}
