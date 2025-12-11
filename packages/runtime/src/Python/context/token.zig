/// Token returned when setting a ContextVar
/// Used to reset the variable to its previous state

const std = @import("std");
const Allocator = std.mem.Allocator;

// Forward declarations
pub const Context = @import("context_impl.zig").Context;
pub const ContextVar = @import("context_var.zig").ContextVar;

/// Token returned when setting a ContextVar
/// Used to reset the variable to its previous state
pub const Token = struct {
    allocator: Allocator,
    context: *Context,
    var_ref: *ContextVar,
    old_value: ?*anyopaque,
    used: bool = false,

    const Self = @This();
    pub const MISSING: *anyopaque = @ptrFromInt(1);

    pub fn create(allocator: Allocator, ctx: *Context, var_ref: *ContextVar, old_val: ?*anyopaque) !*Self {
        const token = try allocator.create(Self);
        token.* = .{
            .allocator = allocator,
            .context = ctx,
            .var_ref = var_ref,
            .old_value = old_val,
        };
        return token;
    }

    pub fn destroy(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Check if token has been used
    pub fn isUsed(self: *Self) bool {
        return self.used;
    }

    /// Get the associated ContextVar
    pub fn getVar(self: *Self) *ContextVar {
        return self.var_ref;
    }

    /// Get the old value (or null if was missing)
    pub fn getOldValue(self: *Self) ?*anyopaque {
        if (self.old_value == MISSING) return null;
        return self.old_value;
    }
};
