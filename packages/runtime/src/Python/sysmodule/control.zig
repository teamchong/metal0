/// control - Exit and Exception Handling
/// Program exit and exception info functions

const std = @import("std");

// ============================================================================
// Exit Handling
// ============================================================================

/// Exit the program with the given status code
/// Mirrors: sys.exit()
pub fn exit(status: anytype) noreturn {
    const code: u8 = switch (@typeInfo(@TypeOf(status))) {
        .int, .comptime_int => @intCast(@min(255, @max(0, status))),
        .optional => if (status) |s| @intCast(@min(255, @max(0, s))) else 0,
        else => 0,
    };
    std.process.exit(code);
}

// ============================================================================
// Exception Information
// ============================================================================

/// Get last exception info (type, value, traceback)
/// Mirrors: sys.exc_info()
pub fn exc_info() struct { ?[]const u8, ?[]const u8, ?[]const u8 } {
    const errors = @import("../errors.zig");
    const fetched = errors.fetch();
    return .{ fetched.type_name, fetched.value, fetched.traceback };
}

/// Get current exception (Python 3.11+ style)
/// Mirrors: sys.exception()
pub fn exception() ?[]const u8 {
    const errors = @import("../errors.zig");
    return errors.occurredType();
}
