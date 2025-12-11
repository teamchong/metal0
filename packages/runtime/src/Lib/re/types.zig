/// Type definitions for the 're' module
const std = @import("std");
const runtime = @import("../../runtime.zig");

// Import the regex engine via build.zig module
const regex_impl = @import("regex");

pub const Regex = regex_impl.Regex;
pub const Match = regex_impl.Match;
pub const Span = regex_impl.Span;

/// Python Match object - returned by re.search(), re.match(), etc.
/// Can be null-like (is_match = false) or contain actual match data
pub const PyMatch = struct {
    matched_text: []const u8,
    full_text: []const u8,
    start: usize,
    end: usize,
    groups: []const []const u8,
    allocator: std.mem.Allocator,
    is_match: bool, // true if this is a real match, false for "None"

    /// Get the matched string (group 0) or a specific group
    pub fn group(self: *const PyMatch) []const u8 {
        return self.matched_text;
    }

    /// Get start position
    pub fn start_pos(self: *const PyMatch) usize {
        return self.start;
    }

    /// Get end position
    pub fn end_pos(self: *const PyMatch) usize {
        return self.end;
    }

    /// Get span as tuple
    pub fn getSpan(self: *const PyMatch) struct { usize, usize } {
        return .{ self.start, self.end };
    }

    /// Create a PyMatch from match result
    pub fn create(allocator: std.mem.Allocator, text: []const u8, m: Match) !*PyMatch {
        const matched = try allocator.dupe(u8, text[m.span.start..m.span.end]);
        const full = try allocator.dupe(u8, text);

        const obj = try allocator.create(PyMatch);
        obj.* = .{
            .matched_text = matched,
            .full_text = full,
            .start = m.span.start,
            .end = m.span.end,
            .groups = &.{},
            .allocator = allocator,
            .is_match = true,
        };
        return obj;
    }

    /// Create an empty/None match
    pub fn createNone(allocator: std.mem.Allocator) !*PyMatch {
        const obj = try allocator.create(PyMatch);
        obj.* = .{
            .matched_text = "",
            .full_text = "",
            .start = 0,
            .end = 0,
            .groups = &.{},
            .allocator = allocator,
            .is_match = false,
        };
        return obj;
    }

    pub fn deinit(self: *PyMatch) void {
        if (self.is_match) {
            self.allocator.free(self.matched_text);
            self.allocator.free(self.full_text);
        }
        self.allocator.destroy(self);
    }
};

/// Compiled regex object wrapper
pub const CompiledPattern = struct {
    regex: Regex,
    pattern: []const u8,
    flags: i64,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CompiledPattern) void {
        self.regex.deinit();
        self.allocator.free(self.pattern);
        self.allocator.destroy(self);
    }
};
