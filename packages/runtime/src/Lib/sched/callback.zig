//! Context for scheduled callbacks with user data.

const std = @import("std");

/// Context for a scheduled callback with associated user data
pub fn CallbackContext(comptime T: type) type {
    return struct {
        const Self = @This();

        data: T,
        callback: *const fn (*T) void,

        pub fn run(arg: ?*anyopaque, _: ?*anyopaque) void {
            if (arg) |ptr| {
                const ctx: *Self = @ptrCast(@alignCast(ptr));
                ctx.callback(&ctx.data);
            }
        }
    };
}
