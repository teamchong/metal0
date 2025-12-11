/// Warning Actions
/// Mirrors cpython/Python/_warnings.c - warning action handling

const std = @import("std");

/// Actions for handling warnings
pub const WarningAction = enum {
    error_action, // Turn into exception
    ignore, // Ignore completely
    always, // Always show
    default, // Show first occurrence per location
    module, // Show first occurrence per module
    once, // Show first occurrence globally

    pub fn fromString(s: []const u8) ?WarningAction {
        if (std.mem.eql(u8, s, "error")) return .error_action;
        if (std.mem.eql(u8, s, "ignore")) return .ignore;
        if (std.mem.eql(u8, s, "always")) return .always;
        if (std.mem.eql(u8, s, "default")) return .default;
        if (std.mem.eql(u8, s, "module")) return .module;
        if (std.mem.eql(u8, s, "once")) return .once;
        return null;
    }

    pub fn toString(self: WarningAction) []const u8 {
        return switch (self) {
            .error_action => "error",
            .ignore => "ignore",
            .always => "always",
            .default => "default",
            .module => "module",
            .once => "once",
        };
    }
};
