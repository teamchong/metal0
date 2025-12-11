/// exception_value - Exception Value Type
/// Mirrors cpython/Python/errors.c exception value representation
///
/// This module defines the ExceptionValue type which represents a Python exception instance.

const std = @import("std");

/// Represents a Python exception instance
pub const ExceptionValue = struct {
    /// Exception type name
    type_name: []const u8,

    /// Exception message
    message: []const u8,

    /// Exception args tuple (as strings for simplicity)
    args: []const []const u8 = &[_][]const u8{},

    /// Traceback (as formatted string for now)
    traceback: ?[]const u8 = null,

    /// Exception context (for implicit chaining - "During handling of...")
    context: ?*ExceptionValue = null,

    /// Exception cause (for explicit chaining - "raise X from Y")
    cause: ?*ExceptionValue = null,

    /// Allocator used to create this exception
    allocator: std.mem.Allocator,

    /// Create a new exception value
    pub fn create(allocator: std.mem.Allocator, type_name: []const u8, message: []const u8) !*ExceptionValue {
        const self = try allocator.create(ExceptionValue);
        self.* = .{
            .type_name = try allocator.dupe(u8, type_name),
            .message = try allocator.dupe(u8, message),
            .allocator = allocator,
        };
        return self;
    }

    /// Create from exception type and args
    pub fn createWithArgs(allocator: std.mem.Allocator, type_name: []const u8, args: []const []const u8) !*ExceptionValue {
        const self = try allocator.create(ExceptionValue);
        const args_copy = try allocator.alloc([]const u8, args.len);
        for (args, 0..) |arg, i| {
            args_copy[i] = try allocator.dupe(u8, arg);
        }
        const message = if (args.len > 0) args[0] else "";
        self.* = .{
            .type_name = try allocator.dupe(u8, type_name),
            .message = try allocator.dupe(u8, message),
            .args = args_copy,
            .allocator = allocator,
        };
        return self;
    }

    /// Free exception value memory
    pub fn destroy(self: *ExceptionValue) void {
        self.allocator.free(self.type_name);
        self.allocator.free(self.message);
        for (self.args) |arg| {
            self.allocator.free(arg);
        }
        if (self.args.len > 0) {
            self.allocator.free(self.args);
        }
        if (self.traceback) |tb| {
            self.allocator.free(tb);
        }
        // Note: context and cause are owned elsewhere, don't free
        self.allocator.destroy(self);
    }

    /// Get string representation
    pub fn toString(self: *const ExceptionValue, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}: {s}", .{ self.type_name, self.message });
    }

    /// Set traceback
    pub fn setTraceback(self: *ExceptionValue, tb: []const u8) !void {
        if (self.traceback) |old_tb| {
            self.allocator.free(old_tb);
        }
        self.traceback = try self.allocator.dupe(u8, tb);
    }

    /// Set exception context (implicit chaining)
    pub fn setContext(self: *ExceptionValue, ctx: ?*ExceptionValue) void {
        self.context = ctx;
    }

    /// Get exception context
    pub fn getContext(self: *const ExceptionValue) ?*ExceptionValue {
        return self.context;
    }

    /// Set exception cause (explicit chaining with "from")
    pub fn setCause(self: *ExceptionValue, c: ?*ExceptionValue) void {
        self.cause = c;
    }

    /// Get exception cause
    pub fn getCause(self: *const ExceptionValue) ?*ExceptionValue {
        return self.cause;
    }

    /// Get traceback
    pub fn getTraceback(self: *const ExceptionValue) ?[]const u8 {
        return self.traceback;
    }
};
