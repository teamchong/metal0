/// Warning Filter
/// Mirrors cpython/Python/_warnings.c - warning filter matching

const std = @import("std");
const WarningAction = @import("action.zig").WarningAction;
const WarningCategory = @import("category.zig").WarningCategory;

/// A single warning filter entry
pub const WarningFilter = struct {
    action: WarningAction,
    message_pattern: ?[]const u8,
    category: ?WarningCategory,
    module_pattern: ?[]const u8,
    lineno: u32, // 0 = any line

    const Self = @This();

    pub fn init(
        action: WarningAction,
        message: ?[]const u8,
        category: ?WarningCategory,
        mod: ?[]const u8,
        lineno: u32,
    ) Self {
        return .{
            .action = action,
            .message_pattern = message,
            .category = category,
            .module_pattern = mod,
            .lineno = lineno,
        };
    }

    /// Check if filter matches a warning
    pub fn matches(
        self: *const Self,
        message: []const u8,
        category: WarningCategory,
        mod: []const u8,
        lineno: u32,
    ) bool {
        // Check lineno (0 means any)
        if (self.lineno != 0 and self.lineno != lineno) {
            return false;
        }

        // Check category
        if (self.category) |cat| {
            if (cat != category) return false;
        }

        // Check message pattern (simple substring for now)
        if (self.message_pattern) |pattern| {
            if (std.mem.indexOf(u8, message, pattern) == null) {
                return false;
            }
        }

        // Check module pattern (simple substring)
        if (self.module_pattern) |pattern| {
            if (std.mem.indexOf(u8, mod, pattern) == null) {
                return false;
            }
        }

        return true;
    }
};
