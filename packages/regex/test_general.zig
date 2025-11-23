/// Test auto-optimizer on completely new patterns
const std = @import("std");
const parser = @import("src/pyregex/parser.zig");
const nfa_mod = @import("src/pyregex/nfa.zig");
const lazydfa = @import("src/pyregex/lazydfa.zig");
const optimizer = @import("src/pyregex/optimizer.zig");
const allocator_helper = @import("src/pyregex/allocator_helper.zig");

fn testPattern(allocator: std.mem.Allocator, name: []const u8, pattern: []const u8, text: []const u8) !void {
    var p = parser.Parser.init(allocator, pattern);
    var ast = p.parse() catch {
        std.debug.print("{s:<30} PARSE FAILED\n", .{name});
        return;
    };
    defer ast.deinit();

    // Analyze with optimizer
    var opt_info = try optimizer.analyze(allocator, &ast);
    defer opt_info.deinit();

    std.debug.print("{s:<30} Strategy: {s:<15}", .{ name, @tagName(opt_info.strategy) });
    if (opt_info.prefix_literal) |lit| {
        std.debug.print(" Prefix: \"{s}\" [{d},{d}]", .{ lit, opt_info.window_before, opt_info.window_after });
    }

    // Build NFA
    var builder = nfa_mod.Builder.init(allocator);
    const nfa = builder.build(ast.root) catch {
        std.debug.print(" - BUILD FAILED\n", .{});
        return;
    };
    defer {
        var mut_nfa = nfa;
        mut_nfa.deinit();
    }

    // Apply optimization
    var dfa = lazydfa.LazyDFA.init(allocator, &nfa);
    defer dfa.deinit();

    switch (opt_info.strategy) {
        .simd_digits => dfa.enableDigitsFastPath(),
        .word_boundary => dfa.enableWordBoundaryFastPath(),
        .prefix_scan => {
            if (opt_info.prefix_literal) |lit| {
                if (std.mem.indexOf(u8, lit, "://") != null) {
                    dfa.enableUrlFastPath();
                } else {
                    dfa.setPrefixWithWindow(lit, opt_info.window_before, opt_info.window_after);
                }
            }
        },
        else => {},
    }

    // Find matches
    const matches = try dfa.findAll(text, allocator);
    defer allocator.free(matches);

    std.debug.print(" → {d} matches\n", .{matches.len});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    std.debug.print("\n=== Testing Auto-Optimizer on NEW Patterns ===\n\n", .{});

    // Test data
    const test_text = "Contact: alice@test.com or bob#example.org. Phone: 555-1234 and 555-9876. Visit ftp://files.example.com or http://web.example.com. Prices: $19.99, $5.50, $100.00. Years: 2024-01-15 and 1999-12-31.";

    // Test 1: Simple digits (should detect SIMD)
    try testPattern(allocator, "Simple Digits: [0-9]+", "[0-9]+", test_text);

    // Test 2: Phone pattern with - (should detect prefix)
    try testPattern(allocator, "Phone: [0-9]+-[0-9]+", "[0-9]+-[0-9]+", test_text);

    // Test 3: Price pattern with $ (should detect prefix)
    try testPattern(allocator, "Price: $[0-9]+", "\\$[0-9]+", test_text);

    // Test 4: FTP URL (should detect ://)
    try testPattern(allocator, "FTP: ftp://...", "ftp://[a-z.]+", test_text);

    // Test 5: Alternative separator (should detect #)
    try testPattern(allocator, "Alt email: ...#...", "[a-z]+#[a-z.]+", test_text);

    // Test 6: Year-Month (should detect -)
    try testPattern(allocator, "Date: YYYY-MM", "[0-9]{4}-[0-9]{2}", test_text);

    // Test 7: Just lowercase (should use lazy DFA)
    try testPattern(allocator, "Lowercase: [a-z]+", "[a-z]+", test_text);

    std.debug.print("\n--- Edge Cases ---\n\n", .{});

    // Test 8: Digit with word boundary (should prefer SIMD over word boundary)
    try testPattern(allocator, "Digits with boundary: \\b[0-9]+\\b", "\\b[0-9]+\\b", test_text);

    // Test 9: Multiple prefixes (first one wins)
    try testPattern(allocator, "Multi: @...-...", "[a-z]+@[a-z]+-[0-9]+", test_text);

    // Test 10: Digit class vs literal
    try testPattern(allocator, "Digit class: \\d+", "\\d+", test_text);

    // Test 11: Complex pattern (should fallback to DFA)
    try testPattern(allocator, "Complex: (a|b)+c", "(a|b)+c", test_text);

    std.debug.print("\n=== All Tests Complete! ===\n", .{});
}
