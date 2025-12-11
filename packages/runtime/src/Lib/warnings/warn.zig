//! Core warning emission functions
//!
//! Functions for issuing warnings with stack-level tracking.

const std = @import("std");
const types = @import("types.zig");
const state = @import("state.zig");
const stack = @import("stack.zig");
const format = @import("format.zig");

/// Issue a warning
/// stacklevel: 1 = immediate caller, 2 = caller's caller, etc.
pub fn warn(
    allocator: std.mem.Allocator,
    message: []const u8,
    category: types.WarningCategory,
    stacklevel: usize,
) !void {
    // Get caller information based on stacklevel
    // In AOT context, we use a simplified approach with registered call stack
    var filename: []const u8 = "<module>";
    var lineno: usize = 0;

    // Use the registered call stack if available
    if (stack.getFrameAtLevel(stacklevel)) |frame| {
        filename = frame.filename;
        lineno = frame.lineno;
    }

    const warnings_state = state.getState(allocator);
    const action = warnings_state.getAction(message, category, filename, lineno);

    switch (action) {
        .ignore => return,
        .@"error" => return error.Warning,
        .always => {
            try format.printWarning(message, category, "<module>", 0);
        },
        .default, .module => {
            // Check if already shown (simplified)
            const key = message;
            if (!warnings_state.hasSeen(key)) {
                try warnings_state.markSeen(key);
                try format.printWarning(message, category, "<module>", 0);
            }
        },
        .once => {
            // Show only once ever
            if (!warnings_state.hasSeen(message)) {
                try warnings_state.markSeen(message);
                try format.printWarning(message, category, "<module>", 0);
            }
        },
    }
}

/// Issue a warning with explicit origin
pub fn warnExplicit(
    allocator: std.mem.Allocator,
    message: []const u8,
    category: types.WarningCategory,
    filename: []const u8,
    lineno: usize,
    module_name: ?[]const u8,
) !void {
    const warnings_state = state.getState(allocator);
    const mod = module_name orelse filename;
    const action = warnings_state.getAction(message, category, mod, lineno);

    switch (action) {
        .ignore => return,
        .@"error" => return error.Warning,
        else => {
            try format.printWarning(message, category, filename, lineno);
        },
    }
}
