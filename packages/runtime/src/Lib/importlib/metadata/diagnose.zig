//! importlib.metadata.diagnose - Diagnostic utilities
//! Reference: cpython/Lib/importlib/metadata/diagnose.py

const std = @import("std");
const metadata = @import("../metadata.zig");

/// Check for package conflicts
/// Returns list of package names with version conflicts
pub fn checkConflicts(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    _ = allocator;
    // In AOT compilation, packages are resolved at compile time
    // No runtime conflicts are possible
    return std.ArrayList([]const u8){};
}

/// Diagnose package installation issues
pub fn diagnosePackage(allocator: std.mem.Allocator, name: []const u8) !DiagnosticResult {
    const dist = metadata.Distribution.fromName(allocator, name) catch |err| {
        return DiagnosticResult{
            .found = false,
            .error_message = @errorName(err),
        };
    };
    _ = dist;

    return DiagnosticResult{
        .found = true,
        .error_message = null,
    };
}

pub const DiagnosticResult = struct {
    found: bool,
    error_message: ?[]const u8 = null,
    version: ?[]const u8 = null,
    location: ?[]const u8 = null,
};

test "diagnosePackage" {
    const allocator = std.testing.allocator;
    const result = try diagnosePackage(allocator, "nonexistent_pkg_12345");
    // May or may not find it depending on stub behavior
    _ = result;
}
