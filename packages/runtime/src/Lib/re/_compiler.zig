//! re._compiler - Regular expression compiler
//! Reference: cpython/Lib/re/_compiler.py
//!
//! Internal module that compiles regex patterns to opcodes.
//! The actual compilation is handled by the native regex engine.

const std = @import("std");
const constants = @import("_constants.zig");

/// Opcode types for compiled regex
pub const Opcode = enum(u8) {
    // Matching opcodes
    LITERAL, // Match literal character
    NOT_LITERAL, // Match any character except literal
    ANY, // Match any character (except newline)
    ANY_ALL, // Match any character (including newline)

    // Character classes
    IN, // Match character in set
    NOT_IN, // Match character not in set
    RANGE, // Character range [a-z]
    CATEGORY, // Unicode category

    // Anchors
    AT_BEGINNING, // ^ at start
    AT_BEGINNING_STRING, // \A
    AT_END, // $ at end
    AT_END_STRING, // \Z
    AT_BOUNDARY, // \b word boundary
    AT_NON_BOUNDARY, // \B non-word boundary

    // Quantifiers
    REPEAT, // General repeat {n,m}
    MIN_REPEAT, // Non-greedy repeat {n,m}?
    MAX_REPEAT, // Greedy repeat {n,m}

    // Groups
    SUBPATTERN, // Capturing group
    GROUPREF, // Back reference \1
    GROUPREF_EXISTS, // Conditional on group

    // Control flow
    BRANCH, // Alternation |
    JUMP, // Jump to offset
    MARK, // Mark group boundary

    // Assertions
    ASSERT, // Lookahead (?=...)
    ASSERT_NOT, // Negative lookahead (?!...)

    // End
    SUCCESS, // Match succeeded
    FAILURE, // Match failed
};

/// Compiled pattern instruction
pub const Instruction = struct {
    opcode: Opcode,
    arg: i32 = 0,
    data: ?[]const u8 = null,
};

/// Compiler state
pub const Compiler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    code: std.ArrayList(Instruction),
    flags: u32,

    pub fn init(allocator: std.mem.Allocator, flags: u32) Self {
        return .{
            .allocator = allocator,
            .code = std.ArrayList(Instruction).init(allocator),
            .flags = flags,
        };
    }

    pub fn deinit(self: *Self) void {
        self.code.deinit();
    }

    /// Emit an instruction
    pub fn emit(self: *Self, opcode: Opcode, arg: i32) !void {
        try self.code.append(.{ .opcode = opcode, .arg = arg });
    }

    /// Emit a literal match
    pub fn emitLiteral(self: *Self, char: u21) !void {
        try self.emit(.LITERAL, @intCast(char));
    }

    /// Emit an anchor
    pub fn emitAnchor(self: *Self, anchor: Opcode) !void {
        try self.emit(anchor, 0);
    }

    /// Get current code position
    pub fn position(self: *Self) usize {
        return self.code.items.len;
    }

    /// Patch a jump instruction
    pub fn patch(self: *Self, pos: usize, target: usize) void {
        self.code.items[pos].arg = @intCast(target);
    }
};

/// Compile a parsed pattern tree to instructions
pub fn compile(allocator: std.mem.Allocator, pattern: []const u8, flags: u32) !std.ArrayList(Instruction) {
    var compiler = Compiler.init(allocator, flags);
    errdefer compiler.deinit();

    // Simple compilation: just emit literals for now
    // Full implementation would parse the pattern tree
    for (pattern) |c| {
        try compiler.emitLiteral(c);
    }

    try compiler.emit(.SUCCESS, 0);

    return compiler.code;
}

/// Check if pattern is a literal string (no special regex chars)
pub fn isLiteral(pattern: []const u8) bool {
    for (pattern) |c| {
        switch (c) {
            '.', '^', '$', '*', '+', '?', '{', '}', '[', ']', '\\', '|', '(', ')' => return false,
            else => {},
        }
    }
    return true;
}

// ============================================================================
// Tests
// ============================================================================

test "Compiler emit" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator, 0);
    defer compiler.deinit();

    try compiler.emitLiteral('a');
    try compiler.emit(.SUCCESS, 0);

    try std.testing.expectEqual(@as(usize, 2), compiler.code.items.len);
    try std.testing.expectEqual(Opcode.LITERAL, compiler.code.items[0].opcode);
    try std.testing.expectEqual(Opcode.SUCCESS, compiler.code.items[1].opcode);
}

test "isLiteral" {
    try std.testing.expect(isLiteral("hello"));
    try std.testing.expect(!isLiteral("hel.o"));
    try std.testing.expect(!isLiteral("hello*"));
    try std.testing.expect(!isLiteral("[abc]"));
}
