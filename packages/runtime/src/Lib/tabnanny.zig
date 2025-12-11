//! CPython source: Lib/tabnanny.py
//!
//! Checks Python source files for indentation consistency.
//! Detects mixed tabs and spaces that could cause issues.
//!
//! Mirrors: CPython Lib/tabnanny.py

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");

// ============================================================================
// Error Types
// ============================================================================

pub const TabnannyError = error{
    NannyNag,
    TokenError,
    IndentationError,
};

/// Indentation issue details
pub const NannyNag = struct {
    line_number: usize,
    message: []const u8,
    line: []const u8,

    pub fn format(self: NannyNag, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(
            allocator,
            "Line {d}: {s}\n{s}",
            .{ self.line_number, self.message, self.line },
        );
    }
};

// ============================================================================
// Whitespace representation
// ============================================================================

pub const Whitespace = struct {
    /// Raw whitespace string
    raw: []const u8,

    /// Number of spaces (tabs expanded to n spaces)
    spaces: usize,

    /// Number of tabs
    tabs: usize,

    /// Whether mixing occurred
    is_mixed: bool,

    pub fn init(s: []const u8) Whitespace {
        var spaces: usize = 0;
        var tabs: usize = 0;
        var is_mixed = false;
        var seen_space = false;
        var seen_tab = false;

        for (s) |c| {
            if (c == ' ') {
                spaces += 1;
                if (seen_tab) is_mixed = true;
                seen_space = true;
            } else if (c == '\t') {
                tabs += 1;
                if (seen_space) is_mixed = true;
                seen_tab = true;
            }
        }

        return .{
            .raw = s,
            .spaces = spaces,
            .tabs = tabs,
            .is_mixed = is_mixed,
        };
    }

    /// Compare two whitespace patterns for consistency
    pub fn isConsistent(self: Whitespace, other: Whitespace) bool {
        // If neither has tabs, they're consistent
        if (self.tabs == 0 and other.tabs == 0) return true;

        // If both have only tabs, they're consistent
        if (self.spaces == 0 and other.spaces == 0) return true;

        // Mixed usage - check if one is a prefix of the other
        if (self.raw.len <= other.raw.len) {
            return std.mem.startsWith(u8, other.raw, self.raw);
        } else {
            return std.mem.startsWith(u8, self.raw, other.raw);
        }
    }

    /// Expand tabs to spaces (default 8 spaces per tab)
    pub fn expandedLength(self: Whitespace, tabsize: usize) usize {
        var col: usize = 0;
        for (self.raw) |c| {
            if (c == '\t') {
                col = ((col / tabsize) + 1) * tabsize;
            } else {
                col += 1;
            }
        }
        return col;
    }
};

// ============================================================================
// check - Main checking function
// ============================================================================

/// Check a file for indentation issues
pub fn check(allocator: std.mem.Allocator, filename: []const u8) !?NannyNag {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    return checkString(content);
}

/// Check a string for indentation issues
pub fn checkString(content: []const u8) ?NannyNag {
    var prev_indent: ?Whitespace = null;
    var line_number: usize = 0;

    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        line_number += 1;

        // Skip empty lines and comments
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Get leading whitespace
        const indent_end = line.len - trimmed.len;
        const indent_str = line[0..indent_end];

        if (indent_str.len == 0) {
            prev_indent = null;
            continue;
        }

        const current = Whitespace.init(indent_str);

        // Check for mixed tabs and spaces in this line
        if (current.is_mixed) {
            return NannyNag{
                .line_number = line_number,
                .message = "indentation contains mixed spaces and tabs",
                .line = line,
            };
        }

        // Check consistency with previous indentation
        if (prev_indent) |prev| {
            if (!prev.isConsistent(current)) {
                return NannyNag{
                    .line_number = line_number,
                    .message = "indentation is inconsistent with previous lines",
                    .line = line,
                };
            }
        }

        prev_indent = current;
    }

    return null;
}

// ============================================================================
// process_tokens - Token-based checking
// ============================================================================

/// Token types we care about
pub const TokenType = enum {
    indent,
    dedent,
    newline,
    other,
};

/// Process tokens for indentation checking
pub fn processTokens(tokens: []const struct { type: TokenType, value: []const u8, line: usize }) ?NannyNag {
    var indent_stack = std.ArrayList(Whitespace).init(allocator_helper.fast_allocator);
    defer indent_stack.deinit();

    for (tokens) |token| {
        switch (token.type) {
            .indent => {
                const ws = Whitespace.init(token.value);
                if (ws.is_mixed) {
                    return NannyNag{
                        .line_number = token.line,
                        .message = "indentation contains mixed spaces and tabs",
                        .line = token.value,
                    };
                }

                if (indent_stack.items.len > 0) {
                    const prev = indent_stack.items[indent_stack.items.len - 1];
                    if (!prev.isConsistent(ws)) {
                        return NannyNag{
                            .line_number = token.line,
                            .message = "inconsistent use of tabs and spaces in indentation",
                            .line = token.value,
                        };
                    }
                }

                indent_stack.append(ws) catch continue;
            },
            .dedent => {
                if (indent_stack.items.len > 0) {
                    _ = indent_stack.pop();
                }
            },
            else => {},
        }
    }

    return null;
}

// ============================================================================
// Verbose mode helpers
// ============================================================================

var verbose_mode: bool = false;

/// Enable verbose output
pub fn setVerbose(v: bool) void {
    verbose_mode = v;
}

/// Get verbose mode status
pub fn isVerbose() bool {
    return verbose_mode;
}

// ============================================================================
// Tests
// ============================================================================

test "Whitespace init spaces only" {
    const ws = Whitespace.init("    ");
    try std.testing.expectEqual(@as(usize, 4), ws.spaces);
    try std.testing.expectEqual(@as(usize, 0), ws.tabs);
    try std.testing.expect(!ws.is_mixed);
}

test "Whitespace init tabs only" {
    const ws = Whitespace.init("\t\t");
    try std.testing.expectEqual(@as(usize, 0), ws.spaces);
    try std.testing.expectEqual(@as(usize, 2), ws.tabs);
    try std.testing.expect(!ws.is_mixed);
}

test "Whitespace init mixed" {
    const ws = Whitespace.init("\t ");
    try std.testing.expectEqual(@as(usize, 1), ws.spaces);
    try std.testing.expectEqual(@as(usize, 1), ws.tabs);
    try std.testing.expect(ws.is_mixed);
}

test "Whitespace expandedLength" {
    const ws = Whitespace.init("\t");
    try std.testing.expectEqual(@as(usize, 8), ws.expandedLength(8));

    const ws2 = Whitespace.init("   \t");
    try std.testing.expectEqual(@as(usize, 8), ws2.expandedLength(8));
}

test "Whitespace isConsistent" {
    const spaces = Whitespace.init("    ");
    const more_spaces = Whitespace.init("        ");
    try std.testing.expect(spaces.isConsistent(more_spaces));

    const tabs = Whitespace.init("\t");
    const more_tabs = Whitespace.init("\t\t");
    try std.testing.expect(tabs.isConsistent(more_tabs));
}

test "checkString no issues" {
    const code =
        \\def foo():
        \\    pass
        \\
        \\def bar():
        \\    return 1
    ;
    const result = checkString(code);
    try std.testing.expectEqual(@as(?NannyNag, null), result);
}

test "checkString mixed tabs and spaces" {
    const code = "def foo():\n\t pass";
    const result = checkString(code);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 2), result.?.line_number);
}

test "verbose mode" {
    try std.testing.expect(!isVerbose());
    setVerbose(true);
    try std.testing.expect(isVerbose());
    setVerbose(false);
    try std.testing.expect(!isVerbose());
}
