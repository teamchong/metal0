/// Main regex API - ties everything together
const std = @import("std");
const parser = @import("parser.zig");
const nfa_mod = @import("nfa.zig");
const pikevm = @import("pikevm.zig");

pub const Match = pikevm.Match;
pub const Span = pikevm.Span;

/// Compiled regular expression
pub const Regex = struct {
    nfa: nfa_mod.NFA,
    allocator: std.mem.Allocator,

    /// Compile a regex pattern
    pub fn compile(allocator: std.mem.Allocator, pattern: []const u8) !Regex {
        // Parse pattern to AST
        var p = parser.Parser.init(allocator, pattern);
        var ast = try p.parse();
        defer ast.deinit();

        // Build NFA from AST
        var builder = nfa_mod.Builder.init(allocator);
        const nfa = try builder.build(ast.root);

        return .{
            .nfa = nfa,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Regex) void {
        self.nfa.deinit();
    }

    /// Find first match in text
    pub fn find(self: *Regex, text: []const u8) !?Match {
        var vm = pikevm.PikeVM.init(self.allocator, &self.nfa);
        return try vm.find(text);
    }

    /// Find all non-overlapping matches in text
    /// Returns list of matched strings (caller must free)
    pub fn findAll(self: *Regex, text: []const u8) !std.ArrayList([]const u8) {
        var results = std.ArrayList([]const u8){};
        var vm = pikevm.PikeVM.init(self.allocator, &self.nfa);

        var pos: usize = 0;
        while (pos < text.len) {
            // Search for match starting at or after pos
            const maybe_match = try vm.findFrom(text, pos);
            if (maybe_match) |m| {
                var match = m;
                defer match.deinit(self.allocator);

                // Extract matched text
                const matched_text = text[match.span.start..match.span.end];
                const duped = try self.allocator.dupe(u8, matched_text);
                try results.append(self.allocator, duped);

                // Move past this match (ensure progress)
                if (match.span.end > pos) {
                    pos = match.span.end;
                } else {
                    pos += 1;
                }
            } else {
                break;
            }
        }

        return results;
    }
};

// Tests
test "regex literal match" {
    const allocator = std.testing.allocator;

    var regex = try Regex.compile(allocator, "hello");
    defer regex.deinit();

    const result = try regex.find("hello world");
    try std.testing.expect(result != null);

    var match = result.?;
    defer match.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), match.span.start);
    try std.testing.expectEqual(@as(usize, 5), match.span.end);
}

test "regex alternation" {
    const allocator = std.testing.allocator;

    var regex = try Regex.compile(allocator, "cat|dog");
    defer regex.deinit();

    // Test cat
    {
        const result = try regex.find("I have a cat");
        try std.testing.expect(result != null);
        var match = result.?;
        defer match.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 9), match.span.start);
        try std.testing.expectEqual(@as(usize, 12), match.span.end);
    }

    // Test dog
    {
        const result = try regex.find("I have a dog");
        try std.testing.expect(result != null);
        var match = result.?;
        defer match.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 9), match.span.start);
        try std.testing.expectEqual(@as(usize, 12), match.span.end);
    }
}

test "regex star quantifier" {
    const allocator = std.testing.allocator;

    var regex = try Regex.compile(allocator, "a*");
    defer regex.deinit();

    const result = try regex.find("aaa");
    try std.testing.expect(result != null);

    var match = result.?;
    defer match.deinit(allocator);
    // Should match "aaa" (greedy)
    try std.testing.expectEqual(@as(usize, 0), match.span.start);
    try std.testing.expectEqual(@as(usize, 3), match.span.end);
}

test "regex no match" {
    const allocator = std.testing.allocator;

    var regex = try Regex.compile(allocator, "xyz");
    defer regex.deinit();

    const result = try regex.find("abc");
    try std.testing.expect(result == null);
}
