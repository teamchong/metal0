/// Context variables module stub
/// Ported from CPython Modules/_contextvarsmodule.c
/// Provides context-local state for async code
const std = @import("std");

/// Context variable stub
pub const ContextVar = struct {
    name: []const u8,
    default: ?*anyopaque = null,

    pub fn init(name: []const u8) @This() {
        return .{ .name = name };
    }

    pub fn get(self: *const @This()) !*anyopaque {
        _ = self;
        return error.NotImplemented; // Stub
    }

    pub fn set(self: *@This(), value: *anyopaque) !void {
        _ = self;
        _ = value;
        return error.NotImplemented; // Stub
    }
};

/// Token for resetting context var
pub const Token = struct {
    var_ptr: *ContextVar,
    old_value: ?*anyopaque,
};

// DCE-friendly: Unused if async not used
