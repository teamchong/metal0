/// Cross-platform print utilities
const std = @import("std");
const builtin = @import("builtin");

/// Browser WASM (freestanding) has no threading or OS support
pub const is_freestanding = builtin.os.tag == .freestanding;

/// Cross-platform print function
/// - Native/WASI: uses std.debug.print (stderr)
/// - Freestanding (browser): no-op (JS should use exported functions)
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (comptime !is_freestanding) {
        std.debug.print(fmt, args);
    }
}

/// Print a newline
pub fn println() void {
    print("\n", .{});
}
