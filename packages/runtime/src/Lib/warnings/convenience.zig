//! Convenience warning functions
//!
//! Shorthand functions for issuing specific warning types.

const std = @import("std");
const types = @import("types.zig");
const warn_mod = @import("warn.zig");

/// Issue a DeprecationWarning
pub fn deprecationWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn_mod.warn(allocator, message, .DeprecationWarning, 2);
}

/// Issue a PendingDeprecationWarning
pub fn pendingDeprecationWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn_mod.warn(allocator, message, .PendingDeprecationWarning, 2);
}

/// Issue a RuntimeWarning
pub fn runtimeWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn_mod.warn(allocator, message, .RuntimeWarning, 2);
}

/// Issue a SyntaxWarning
pub fn syntaxWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn_mod.warn(allocator, message, .SyntaxWarning, 2);
}

/// Issue a UserWarning
pub fn userWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn_mod.warn(allocator, message, .UserWarning, 2);
}

/// Issue a FutureWarning
pub fn futureWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn_mod.warn(allocator, message, .FutureWarning, 2);
}

/// Issue an ImportWarning
pub fn importWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn_mod.warn(allocator, message, .ImportWarning, 2);
}

/// Issue a ResourceWarning
pub fn resourceWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn_mod.warn(allocator, message, .ResourceWarning, 2);
}
