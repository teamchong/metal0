//! Core types for the Python debugger
//!
//! Defines Breakpoint and Frame types used throughout the debugger.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Breakpoint
// ============================================================================

/// Breakpoint representation
pub const Breakpoint = struct {
    number: u32,
    file: []const u8,
    line: usize,
    temporary: bool,
    enabled: bool,
    hits: u32,
    ignore: u32,
    condition: ?[]const u8,

    pub fn init(number: u32, file: []const u8, line: usize, temporary: bool) Breakpoint {
        return .{
            .number = number,
            .file = file,
            .line = line,
            .temporary = temporary,
            .enabled = true,
            .hits = 0,
            .ignore = 0,
            .condition = null,
        };
    }

    pub fn enable(self: *Breakpoint) void {
        self.enabled = true;
    }

    pub fn disable(self: *Breakpoint) void {
        self.enabled = false;
    }

    pub fn bpformat(self: *const Breakpoint, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        const disp = if (self.temporary) "del" else "keep";
        const enab = if (self.enabled) "yes" else "no";

        try result.writer().print("{d:>4} breakpoint   {s} {s}   at {s}:{d}", .{
            self.number,
            disp,
            enab,
            self.file,
            self.line,
        });

        if (self.condition) |cond| {
            try result.writer().print("\n\tstop only if {s}", .{cond});
        }

        if (self.ignore > 0) {
            try result.writer().print("\n\tignore next {d} hits", .{self.ignore});
        }

        if (self.hits > 0) {
            const ss = if (self.hits > 1) "s" else "";
            try result.writer().print("\n\tbreakpoint already hit {d} time{s}", .{ self.hits, ss });
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Stack Frame
// ============================================================================

/// Stack frame representation
pub const Frame = struct {
    filename: []const u8,
    lineno: usize,
    function: []const u8,
    locals: hashmap_helper.StringHashMap([]const u8),
    globals: hashmap_helper.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, filename: []const u8, lineno: usize, function: []const u8) Frame {
        return .{
            .filename = filename,
            .lineno = lineno,
            .function = function,
            .locals = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .globals = hashmap_helper.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Frame) void {
        self.locals.deinit();
        self.globals.deinit();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Breakpoint init" {
    const bp = Breakpoint.init(1, "test.py", 10, false);
    try std.testing.expectEqual(@as(u32, 1), bp.number);
    try std.testing.expectEqualStrings("test.py", bp.file);
    try std.testing.expectEqual(@as(usize, 10), bp.line);
    try std.testing.expect(!bp.temporary);
    try std.testing.expect(bp.enabled);
}

test "Breakpoint enable/disable" {
    var bp = Breakpoint.init(1, "test.py", 10, false);

    try std.testing.expect(bp.enabled);
    bp.disable();
    try std.testing.expect(!bp.enabled);
    bp.enable();
    try std.testing.expect(bp.enabled);
}

test "Frame init" {
    const allocator = std.testing.allocator;
    var frame = Frame.init(allocator, "test.py", 10, "main");
    defer frame.deinit();

    try std.testing.expectEqualStrings("test.py", frame.filename);
    try std.testing.expectEqual(@as(usize, 10), frame.lineno);
    try std.testing.expectEqualStrings("main", frame.function);
}
