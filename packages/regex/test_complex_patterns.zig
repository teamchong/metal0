const std = @import("std");
const Regex = @import("src/pyregex/regex.zig").Regex;

pub fn testPattern(allocator: std.mem.Allocator, pattern: []const u8, text: []const u8, should_match: bool) !void {
    std.debug.print("Testing '{s}' against '{s}' (expect: {s})... ", .{pattern, text, if (should_match) "MATCH" else "NO MATCH"});
    
    var regex = Regex.compile(allocator, pattern) catch |err| {
        std.debug.print("COMPILE ERROR: {}\n", .{err});
        return err;
    };
    defer regex.deinit();

    const result = try regex.find(text);
    
    if (result) |match| {
        var mut_match = match;
        defer mut_match.deinit(allocator);
        
        if (should_match) {
            std.debug.print("✓ MATCH at ({d}, {d})\n", .{match.span.start, match.span.end});
        } else {
            std.debug.print("✗ UNEXPECTED MATCH at ({d}, {d})\n", .{match.span.start, match.span.end});
        }
    } else {
        if (!should_match) {
            std.debug.print("✓ NO MATCH\n", .{});
        } else {
            std.debug.print("✗ EXPECTED MATCH\n", .{});
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Basic Patterns ===\n", .{});
    try testPattern(allocator, "hello", "hello world", true);
    try testPattern(allocator, "world", "hello world", true);
    try testPattern(allocator, "xyz", "hello world", false);

    std.debug.print("\n=== Concatenation ===\n", .{});
    try testPattern(allocator, "abc", "abc", true);
    try testPattern(allocator, "abc", "xabcx", true);

    std.debug.print("\n=== Alternation ===\n", .{});
    try testPattern(allocator, "cat|dog", "I have a cat", true);
    try testPattern(allocator, "cat|dog", "I have a dog", true);
    try testPattern(allocator, "cat|dog", "I have a bird", false);

    std.debug.print("\n=== Star Quantifier ===\n", .{});
    try testPattern(allocator, "a*", "", true);  // Empty match
    try testPattern(allocator, "a*", "aaa", true);  // Multiple a's
    try testPattern(allocator, "a*", "b", true);  // Zero a's (empty match at start)
    try testPattern(allocator, "ab*c", "ac", true);  // Zero b's
    try testPattern(allocator, "ab*c", "abc", true);  // One b
    try testPattern(allocator, "ab*c", "abbc", true);  // Multiple b's

    std.debug.print("\n=== Plus Quantifier ===\n", .{});
    try testPattern(allocator, "a+", "aaa", true);
    try testPattern(allocator, "a+", "b", false);  // Requires at least one a
    try testPattern(allocator, "ab+c", "ac", false);  // Requires at least one b
    try testPattern(allocator, "ab+c", "abc", true);

    std.debug.print("\n=== Question Quantifier ===\n", .{});
    try testPattern(allocator, "ab?c", "ac", true);  // Zero b's
    try testPattern(allocator, "ab?c", "abc", true);  // One b
    try testPattern(allocator, "ab?c", "abbc", false);  // Too many b's

    std.debug.print("\n=== Dot (Any Character) ===\n", .{});
    try testPattern(allocator, "a.c", "abc", true);
    try testPattern(allocator, "a.c", "axc", true);
    try testPattern(allocator, "a.c", "ac", false);  // Dot must match one char

    std.debug.print("\n=== Complex Combinations ===\n", .{});
    try testPattern(allocator, "a+b*", "aaa", true);  // a+ matches, b* matches empty
    try testPattern(allocator, "a+b*", "aaabbb", true);  // Both match
}
