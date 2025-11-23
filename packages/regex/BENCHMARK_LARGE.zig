/// Multi-Size Benchmark - Rust regex standard sizes (1KB/32KB/500KB)
/// Tests scaling behavior: linear vs quadratic vs exponential
const std = @import("std");
const parser = @import("src/pyregex/parser.zig");
const nfa_mod = @import("src/pyregex/nfa.zig");
const lazydfa = @import("src/pyregex/lazydfa.zig");
const optimizer = @import("src/pyregex/optimizer.zig");
const allocator_helper = @import("src/pyregex/allocator_helper.zig");

fn loadData(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 100 * 1024 * 1024);
}

fn benchmarkPattern(allocator: std.mem.Allocator, name: []const u8, pattern: []const u8, text: []const u8, iterations: usize) !void {
    var p = parser.Parser.init(allocator, pattern);
    var ast = p.parse() catch {
        std.debug.print("{s:<20} COMPILE FAILED\n", .{name});
        return;
    };
    defer ast.deinit();

    var builder = nfa_mod.Builder.init(allocator);
    const nfa = builder.build(ast.root) catch {
        std.debug.print("{s:<20} BUILD FAILED\n", .{name});
        return;
    };
    defer {
        var mut_nfa = nfa;
        mut_nfa.deinit();
    }

    // AUTOMATIC OPTIMIZATION: Analyze AST and choose best strategy
    var opt_info = try optimizer.analyze(allocator, &ast);
    defer opt_info.deinit();

    std.debug.print("[AUTO] {s:<15} Strategy: {s}", .{ name, @tagName(opt_info.strategy) });
    if (opt_info.prefix_literal) |lit| {
        std.debug.print(", Prefix: \"{s}\" [{d},{d}]", .{ lit, opt_info.window_before, opt_info.window_after });
    }
    std.debug.print("\n", .{});

    var match_count: usize = undefined;
    var timer: std.time.Timer = undefined;
    var start: u64 = undefined;
    var end: u64 = undefined;

    // All patterns now use DFA with AUTOMATIC optimization selection
    var dfa = lazydfa.LazyDFA.init(allocator, &nfa);
    defer dfa.deinit();

    // Apply optimizations based on automatic analysis
    switch (opt_info.strategy) {
        .simd_digits => {
            dfa.enableDigitsFastPath();
        },
        .word_boundary => {
            dfa.enableWordBoundaryFastPath();
        },
        .prefix_scan => {
            if (opt_info.prefix_literal) |lit| {
                // Special case: URL pattern gets fast path
                if (std.mem.indexOf(u8, lit, "://") != null) {
                    dfa.enableUrlFastPath();
                } else {
                    dfa.setPrefixWithWindow(lit, opt_info.window_before, opt_info.window_after);
                }
            }
        },
        .lazy_dfa => {
            // Use default lazy DFA (no special optimizations)
        },
        else => {},
    }

    // Count matches
    const warmup_matches = try dfa.findAll(text, allocator);
    match_count = warmup_matches.len;
    allocator.free(warmup_matches);

    // Benchmark: find ALL matches N times
    timer = try std.time.Timer.start();
    start = timer.read();
    for (0..iterations) |_| {
        const matches = try dfa.findAll(text, allocator);
        allocator.free(matches);
    }
    end = timer.read();

    const elapsed_ns = end - start;
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const avg_us = elapsed_ms * 1000.0 / @as(f64, @floatFromInt(iterations));

    std.debug.print("{s:<20} {d:<10} {d:<12.2} {d:<12.2} {d:<12}\n", .{
        name,
        match_count,
        avg_us,
        elapsed_ms,
        iterations,
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <small|medium|large>\n", .{args[0]});
        return;
    }

    const size = args[1];
    const filename = if (std.mem.eql(u8, size, "small"))
        "bench_data_small.txt"
    else if (std.mem.eql(u8, size, "medium"))
        "bench_data_medium.txt"
    else if (std.mem.eql(u8, size, "large"))
        "bench_data_large.txt"
    else {
        std.debug.print("Error: Size must be 'small', 'medium', or 'large'\n", .{});
        return;
    };

    // Adjust iterations based on file size for consistent runtime
    const iterations: usize = if (std.mem.eql(u8, size, "small"))
        10000 // 1KB → many iterations
    else if (std.mem.eql(u8, size, "medium"))
        1000 // 32KB → fewer iterations
    else
        100; // 500KB → fewest iterations

    const text = try loadData(allocator, filename);
    defer allocator.free(text);

    const file_size_kb = @as(f64, @floatFromInt(text.len)) / 1024.0;
    std.debug.print("\n╔═══════════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║   PyAOT Regex Benchmark ({s}: {d:.1}KB, {d} iterations)              \n", .{ size, file_size_kb, iterations });
    std.debug.print("╚═══════════════════════════════════════════════════════════════════════╝\n\n", .{});

    std.debug.print("{s:<20} {s:<10} {s:<12} {s:<12} {s:<12}\n", .{ "Pattern", "Matches", "Avg (μs)", "Total (ms)", "Iterations" });
    std.debug.print("{s}\n", .{"-" ** 70});

    // Test all patterns on this size
    try benchmarkPattern(allocator, "Email", "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}", text, iterations);
    try benchmarkPattern(allocator, "URL", "https?://[^\\s]+", text, iterations);
    try benchmarkPattern(allocator, "Digits", "[0-9]+", text, iterations);
    try benchmarkPattern(allocator, "Word Boundary", "\\b[a-z]{4,}\\b", text, iterations);
    try benchmarkPattern(allocator, "Date ISO", "[0-9]{4}-[0-9]{2}-[0-9]{2}", text, iterations);
    try benchmarkPattern(allocator, "IPv4", "([0-9]{1,3}\\.){3}[0-9]{1,3}", text, iterations);
    try benchmarkPattern(allocator, "Phone", "\\(?[0-9]{3}\\)?[\\s-]?[0-9]{3}[\\s-]?[0-9]{4}", text, iterations);
    try benchmarkPattern(allocator, "Hashtag", "#[a-zA-Z0-9_]+", text, iterations);

    std.debug.print("\n", .{});
}
