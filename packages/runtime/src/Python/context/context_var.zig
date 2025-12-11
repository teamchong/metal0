/// Context Variable - a variable that can have different values in different contexts

const std = @import("std");
const Allocator = std.mem.Allocator;

// Forward declarations
pub const Context = @import("context_impl.zig").Context;
pub const Token = @import("token.zig").Token;
const global_state = @import("global_state.zig");

/// Context Variable - a variable that can have different values in different contexts
pub const ContextVar = struct {
    allocator: Allocator,
    name: []const u8,
    default_value: ?*anyopaque = null,
    has_default: bool = false,

    // Cached value for fast access in current context
    cached_value: ?*anyopaque = null,
    cached_context: ?*Context = null,

    const Self = @This();

    pub fn create(allocator: Allocator, name: []const u8, default: ?*anyopaque) !*Self {
        const cv = try allocator.create(Self);
        cv.* = .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .default_value = default,
            .has_default = default != null,
        };
        return cv;
    }

    pub fn destroy(self: *Self) void {
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    /// Get value in current context
    pub fn get(self: *Self) !?*anyopaque {
        const ctx = global_state.getCurrentContext() orelse return self.default_value;

        // Check cache
        if (self.cached_context == ctx) {
            return self.cached_value orelse self.default_value;
        }

        // Lookup in context
        if (ctx.getVar(self)) |value| {
            self.cached_value = value;
            self.cached_context = ctx;
            return value;
        }

        return self.default_value;
    }

    /// Set value in current context, return token for reset
    pub fn set(self: *Self, value: *anyopaque) !*Token {
        const ctx = global_state.getCurrentContext() orelse return error.NoContext;

        // Get old value for token
        const old_value = ctx.getVar(self) orelse Token.MISSING;

        // Create token before modifying context
        const token = try Token.create(self.allocator, ctx, self, old_value);

        // Set in context
        try ctx.setVar(self, value);

        // Update cache
        self.cached_value = value;
        self.cached_context = ctx;

        return token;
    }

    /// Reset to value from token
    pub fn reset(self: *Self, token: *Token) !void {
        if (token.used) {
            return error.TokenAlreadyUsed;
        }

        if (token.var_ref != self) {
            return error.WrongToken;
        }

        const ctx = global_state.getCurrentContext() orelse return error.NoContext;

        if (token.context != ctx) {
            return error.WrongContext;
        }

        // Reset value
        if (token.old_value == Token.MISSING) {
            try ctx.delVar(self);
        } else {
            try ctx.setVar(self, token.old_value.?);
        }

        // Invalidate cache
        self.cached_value = null;
        self.cached_context = null;

        token.used = true;
    }

    /// Get name
    pub fn getName(self: *Self) []const u8 {
        return self.name;
    }
};
