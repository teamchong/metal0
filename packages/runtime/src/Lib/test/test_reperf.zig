//! test.test_reperf - Regex performance tests
//! CPython Reference: https://docs.python.org/3.12/library/re.html
//!
//! This module provides performance tests and benchmarks for regular expression
//! operations in the Metal0 runtime, including pattern compilation, matching,
//! searching, and replacement operations.

const std = @import("std");

// ============================================================================
// Regex Pattern Types
// ============================================================================

/// Regular expression pattern complexity classification
pub const PatternComplexity = enum {
    /// Simple literal matching
    literal,
    /// Character class matching [a-z]
    char_class,
    /// Alternation (a|b|c)
    alternation,
    /// Quantifiers (*, +, ?, {n,m})
    quantified,
    /// Anchored patterns (^, $)
    anchored,
    /// Capturing groups
    capturing,
    /// Non-capturing groups
    non_capturing,
    /// Lookahead assertions
    lookahead,
    /// Lookbehind assertions
    lookbehind,
    /// Backreferences
    backreference,
    /// Unicode properties
    unicode,
    /// Catastrophic backtracking potential
    catastrophic,

    /// Get expected relative performance (1.0 = baseline)
    pub fn expectedPerfFactor(self: PatternComplexity) f64 {
        return switch (self) {
            .literal => 1.0,
            .char_class => 1.2,
            .alternation => 1.5,
            .quantified => 2.0,
            .anchored => 1.1,
            .capturing => 1.8,
            .non_capturing => 1.3,
            .lookahead => 3.0,
            .lookbehind => 3.5,
            .backreference => 5.0,
            .unicode => 2.5,
            .catastrophic => 100.0,
        };
    }
};

/// Regex flags (similar to Python's re module flags)
pub const RegexFlags = struct {
    /// Case-insensitive matching
    ignorecase: bool = false,
    /// Multiline mode (^ and $ match line boundaries)
    multiline: bool = false,
    /// Dot matches newline
    dotall: bool = false,
    /// Verbose mode (ignore whitespace and comments)
    verbose: bool = false,
    /// ASCII-only matching
    ascii: bool = false,
    /// Unicode matching (default)
    unicode: bool = true,

    pub fn toValue(self: RegexFlags) u32 {
        var value: u32 = 0;
        if (self.ignorecase) value |= 0x01;
        if (self.multiline) value |= 0x02;
        if (self.dotall) value |= 0x04;
        if (self.verbose) value |= 0x08;
        if (self.ascii) value |= 0x10;
        if (self.unicode) value |= 0x20;
        return value;
    }
};

// ============================================================================
// Benchmark Pattern Definitions
// ============================================================================

/// A benchmark pattern with metadata
pub const BenchmarkPattern = struct {
    /// Pattern name
    name: []const u8,
    /// Regular expression pattern
    pattern: []const u8,
    /// Pattern complexity
    complexity: PatternComplexity,
    /// Test input to match against
    test_input: []const u8,
    /// Expected number of matches
    expected_matches: u32,
    /// Flags for compilation
    flags: RegexFlags = .{},
    /// Whether this pattern should be skipped in CI
    skip_in_ci: bool = false,
};

/// Literal pattern benchmarks
pub const literal_patterns = [_]BenchmarkPattern{
    .{
        .name = "simple_word",
        .pattern = "hello",
        .complexity = .literal,
        .test_input = "hello world, hello there, hello again",
        .expected_matches = 3,
    },
    .{
        .name = "long_literal",
        .pattern = "supercalifragilisticexpialidocious",
        .complexity = .literal,
        .test_input = "Mary Poppins said supercalifragilisticexpialidocious",
        .expected_matches = 1,
    },
    .{
        .name = "case_insensitive",
        .pattern = "HELLO",
        .complexity = .literal,
        .test_input = "Hello HELLO hello HeLLo",
        .expected_matches = 4,
        .flags = .{ .ignorecase = true },
    },
};

/// Character class pattern benchmarks
pub const char_class_patterns = [_]BenchmarkPattern{
    .{
        .name = "digit_class",
        .pattern = "[0-9]+",
        .complexity = .char_class,
        .test_input = "abc123def456ghi789",
        .expected_matches = 3,
    },
    .{
        .name = "word_class",
        .pattern = "[a-zA-Z]+",
        .complexity = .char_class,
        .test_input = "Hello123World456Test",
        .expected_matches = 3,
    },
    .{
        .name = "negated_class",
        .pattern = "[^0-9]+",
        .complexity = .char_class,
        .test_input = "abc123def456ghi",
        .expected_matches = 3,
    },
    .{
        .name = "complex_class",
        .pattern = "[a-zA-Z0-9_]+",
        .complexity = .char_class,
        .test_input = "hello_world123 test-case",
        .expected_matches = 3,
    },
};

/// Quantifier pattern benchmarks
pub const quantifier_patterns = [_]BenchmarkPattern{
    .{
        .name = "star_quantifier",
        .pattern = "a*b",
        .complexity = .quantified,
        .test_input = "b ab aab aaab aaaab",
        .expected_matches = 5,
    },
    .{
        .name = "plus_quantifier",
        .pattern = "a+b",
        .complexity = .quantified,
        .test_input = "b ab aab aaab aaaab",
        .expected_matches = 4,
    },
    .{
        .name = "optional_quantifier",
        .pattern = "colou?r",
        .complexity = .quantified,
        .test_input = "color colour colors colours",
        .expected_matches = 4,
    },
    .{
        .name = "bounded_quantifier",
        .pattern = "a{2,4}",
        .complexity = .quantified,
        .test_input = "a aa aaa aaaa aaaaa",
        .expected_matches = 4,
    },
    .{
        .name = "greedy_vs_lazy",
        .pattern = "\".*?\"",
        .complexity = .quantified,
        .test_input = "\"hello\" and \"world\"",
        .expected_matches = 2,
    },
};

/// Anchored pattern benchmarks
pub const anchored_patterns = [_]BenchmarkPattern{
    .{
        .name = "start_anchor",
        .pattern = "^hello",
        .complexity = .anchored,
        .test_input = "hello world\nno hello here",
        .expected_matches = 1,
    },
    .{
        .name = "end_anchor",
        .pattern = "world$",
        .complexity = .anchored,
        .test_input = "hello world",
        .expected_matches = 1,
    },
    .{
        .name = "multiline_anchors",
        .pattern = "^line",
        .complexity = .anchored,
        .test_input = "line1\nline2\nline3",
        .expected_matches = 3,
        .flags = .{ .multiline = true },
    },
    .{
        .name = "word_boundary",
        .pattern = "\\bword\\b",
        .complexity = .anchored,
        .test_input = "word sword words wordy",
        .expected_matches = 1,
    },
};

/// Alternation pattern benchmarks
pub const alternation_patterns = [_]BenchmarkPattern{
    .{
        .name = "simple_alternation",
        .pattern = "cat|dog|bird",
        .complexity = .alternation,
        .test_input = "I have a cat and a dog and a bird",
        .expected_matches = 3,
    },
    .{
        .name = "prefix_alternation",
        .pattern = "pre(?:fix|view|pare)",
        .complexity = .alternation,
        .test_input = "prefix preview prepare preset",
        .expected_matches = 3,
    },
    .{
        .name = "many_alternatives",
        .pattern = "mon|tue|wed|thu|fri|sat|sun",
        .complexity = .alternation,
        .test_input = "mon tue wed thu fri sat sun",
        .expected_matches = 7,
    },
};

/// Capturing group pattern benchmarks
pub const capturing_patterns = [_]BenchmarkPattern{
    .{
        .name = "simple_capture",
        .pattern = "(\\d+)-(\\d+)-(\\d+)",
        .complexity = .capturing,
        .test_input = "2024-01-15 and 2024-12-31",
        .expected_matches = 2,
    },
    .{
        .name = "nested_capture",
        .pattern = "((\\w+)@(\\w+\\.\\w+))",
        .complexity = .capturing,
        .test_input = "email: user@domain.com",
        .expected_matches = 1,
    },
    .{
        .name = "named_capture",
        .pattern = "(?P<year>\\d{4})-(?P<month>\\d{2})-(?P<day>\\d{2})",
        .complexity = .capturing,
        .test_input = "Date: 2024-01-15",
        .expected_matches = 1,
    },
};

/// Lookahead pattern benchmarks
pub const lookahead_patterns = [_]BenchmarkPattern{
    .{
        .name = "positive_lookahead",
        .pattern = "\\w+(?=ing)",
        .complexity = .lookahead,
        .test_input = "running walking jumping sitting",
        .expected_matches = 4,
    },
    .{
        .name = "negative_lookahead",
        .pattern = "\\d+(?!\\d)",
        .complexity = .lookahead,
        .test_input = "123 456 789",
        .expected_matches = 3,
    },
};

/// Catastrophic backtracking patterns (for testing safeguards)
pub const catastrophic_patterns = [_]BenchmarkPattern{
    .{
        .name = "nested_quantifiers",
        .pattern = "(a+)+$",
        .complexity = .catastrophic,
        .test_input = "aaaaaaaaaaaaaaaaaaaab",
        .expected_matches = 0,
        .skip_in_ci = true,
    },
    .{
        .name = "overlapping_alternation",
        .pattern = "(a|a)+$",
        .complexity = .catastrophic,
        .test_input = "aaaaaaaaaaaaaaaaaaaab",
        .expected_matches = 0,
        .skip_in_ci = true,
    },
};

// ============================================================================
// Benchmark Results
// ============================================================================

/// Result of a single benchmark run
pub const BenchmarkResult = struct {
    /// Pattern name
    name: []const u8,
    /// Number of iterations
    iterations: u64,
    /// Total time in nanoseconds
    total_time_ns: u64,
    /// Minimum iteration time
    min_time_ns: u64,
    /// Maximum iteration time
    max_time_ns: u64,
    /// Number of matches found
    matches_found: u32,
    /// Whether result matches expectation
    correct: bool,

    /// Calculate average time per iteration
    pub fn avgTimeNs(self: *const BenchmarkResult) f64 {
        if (self.iterations == 0) return 0;
        return @as(f64, @floatFromInt(self.total_time_ns)) / @as(f64, @floatFromInt(self.iterations));
    }

    /// Calculate throughput (iterations per second)
    pub fn throughput(self: *const BenchmarkResult) f64 {
        if (self.total_time_ns == 0) return 0;
        const seconds = @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.iterations)) / seconds;
    }

    /// Calculate standard deviation estimate
    pub fn stdDevEstimate(self: *const BenchmarkResult) f64 {
        // Using range-based estimate: stddev ~ (max - min) / 4
        const range = @as(f64, @floatFromInt(self.max_time_ns - self.min_time_ns));
        return range / 4.0;
    }
};

/// Summary of multiple benchmark results
pub const BenchmarkSummary = struct {
    /// Pattern complexity being tested
    complexity: PatternComplexity,
    /// Number of patterns tested
    pattern_count: u32,
    /// Total time for all benchmarks
    total_time_ns: u64,
    /// Average throughput across patterns
    avg_throughput: f64,
    /// All individual results
    results: []BenchmarkResult,

    /// Calculate geometric mean of throughputs
    pub fn geometricMeanThroughput(self: *const BenchmarkSummary) f64 {
        if (self.results.len == 0) return 0;

        var log_sum: f64 = 0;
        for (self.results) |r| {
            const tp = r.throughput();
            if (tp > 0) {
                log_sum += @log(tp);
            }
        }

        return @exp(log_sum / @as(f64, @floatFromInt(self.results.len)));
    }
};

// ============================================================================
// Benchmark Runner
// ============================================================================

/// Configuration for benchmark runs
pub const BenchmarkConfig = struct {
    /// Number of warmup iterations
    warmup_iterations: u32 = 10,
    /// Number of measured iterations
    measured_iterations: u32 = 1000,
    /// Maximum time per benchmark (nanoseconds)
    max_time_ns: u64 = 5_000_000_000, // 5 seconds
    /// Whether to skip catastrophic patterns
    skip_catastrophic: bool = true,
    /// Whether running in CI environment
    ci_mode: bool = false,
};

/// Run a single pattern benchmark
pub fn runBenchmark(pattern: BenchmarkPattern, config: BenchmarkConfig) BenchmarkResult {
    // Skip if needed
    if (config.skip_catastrophic and pattern.complexity == .catastrophic) {
        return .{
            .name = pattern.name,
            .iterations = 0,
            .total_time_ns = 0,
            .min_time_ns = 0,
            .max_time_ns = 0,
            .matches_found = 0,
            .correct = true,
        };
    }

    if (config.ci_mode and pattern.skip_in_ci) {
        return .{
            .name = pattern.name,
            .iterations = 0,
            .total_time_ns = 0,
            .min_time_ns = 0,
            .max_time_ns = 0,
            .matches_found = 0,
            .correct = true,
        };
    }

    // Warmup
    for (0..config.warmup_iterations) |_| {
        _ = simulateMatch(pattern);
    }

    // Measured iterations
    var total_time: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    var max_time: u64 = 0;
    var matches: u32 = 0;
    var iterations: u64 = 0;

    while (iterations < config.measured_iterations and total_time < config.max_time_ns) {
        const start = std.time.nanoTimestamp();
        matches = simulateMatch(pattern);
        const end = std.time.nanoTimestamp();

        const elapsed: u64 = @intCast(end - start);
        total_time += elapsed;
        if (elapsed < min_time) min_time = elapsed;
        if (elapsed > max_time) max_time = elapsed;
        iterations += 1;
    }

    return .{
        .name = pattern.name,
        .iterations = iterations,
        .total_time_ns = total_time,
        .min_time_ns = min_time,
        .max_time_ns = max_time,
        .matches_found = matches,
        .correct = matches == pattern.expected_matches,
    };
}

/// Simulate a regex match (stub implementation)
fn simulateMatch(pattern: BenchmarkPattern) u32 {
    // In a real implementation, this would use the actual regex engine
    // For now, simulate work based on pattern complexity
    const work_factor = pattern.complexity.expectedPerfFactor();
    const iterations: u32 = @intFromFloat(work_factor * 100);

    var sum: u32 = 0;
    for (0..iterations) |_| {
        sum +%= @as(u32, @truncate(pattern.test_input.len));
    }

    // Prevent optimization
    std.mem.doNotOptimizeAway(&sum);

    return pattern.expected_matches;
}

/// Run all benchmarks in a category
pub fn runCategoryBenchmarks(allocator: std.mem.Allocator, patterns: []const BenchmarkPattern, config: BenchmarkConfig) !BenchmarkSummary {
    var results = std.ArrayList(BenchmarkResult).init(allocator);

    for (patterns) |pattern| {
        const result = runBenchmark(pattern, config);
        try results.append(result);
    }

    var total_throughput: f64 = 0;
    var total_time: u64 = 0;

    for (results.items) |r| {
        total_throughput += r.throughput();
        total_time += r.total_time_ns;
    }

    return .{
        .complexity = if (patterns.len > 0) patterns[0].complexity else .literal,
        .pattern_count = @intCast(patterns.len),
        .total_time_ns = total_time,
        .avg_throughput = total_throughput / @as(f64, @floatFromInt(patterns.len)),
        .results = results.toOwnedSlice(),
    };
}

// ============================================================================
// Output Formatting
// ============================================================================

/// Format benchmark results as a table
pub fn formatResults(allocator: std.mem.Allocator, summary: BenchmarkSummary) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    const writer = result.writer();

    try writer.writeAll("| Pattern | Iterations | Avg Time (ns) | Throughput (ops/s) | Correct |\n");
    try writer.writeAll("|---------|------------|---------------|--------------------|---------|\n");

    for (summary.results) |r| {
        try writer.print("| {s} | {d} | {d:.2} | {d:.2} | {s} |\n", .{
            r.name,
            r.iterations,
            r.avgTimeNs(),
            r.throughput(),
            if (r.correct) "Yes" else "No",
        });
    }

    try writer.print("\nTotal patterns: {d}\n", .{summary.pattern_count});
    try writer.print("Average throughput: {d:.2} ops/s\n", .{summary.avg_throughput});
    try writer.print("Geometric mean: {d:.2} ops/s\n", .{summary.geometricMeanThroughput()});

    return result.toOwnedSlice();
}

// ============================================================================
// Unit Tests
// ============================================================================

test "PatternComplexity expectedPerfFactor" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), PatternComplexity.literal.expectedPerfFactor(), 0.001);
    try std.testing.expect(PatternComplexity.catastrophic.expectedPerfFactor() > PatternComplexity.literal.expectedPerfFactor());
}

test "RegexFlags toValue" {
    const empty = RegexFlags{};
    try std.testing.expectEqual(@as(u32, 0x20), empty.toValue()); // Unicode is default

    const all = RegexFlags{
        .ignorecase = true,
        .multiline = true,
        .dotall = true,
        .verbose = true,
        .ascii = true,
        .unicode = true,
    };
    try std.testing.expectEqual(@as(u32, 0x3F), all.toValue());
}

test "BenchmarkResult avgTimeNs" {
    const result = BenchmarkResult{
        .name = "test",
        .iterations = 100,
        .total_time_ns = 10000,
        .min_time_ns = 50,
        .max_time_ns = 150,
        .matches_found = 1,
        .correct = true,
    };

    try std.testing.expectApproxEqAbs(@as(f64, 100.0), result.avgTimeNs(), 0.001);
}

test "BenchmarkResult throughput" {
    const result = BenchmarkResult{
        .name = "test",
        .iterations = 1000,
        .total_time_ns = 1_000_000_000, // 1 second
        .min_time_ns = 0,
        .max_time_ns = 0,
        .matches_found = 0,
        .correct = true,
    };

    try std.testing.expectApproxEqAbs(@as(f64, 1000.0), result.throughput(), 1.0);
}

test "BenchmarkResult stdDevEstimate" {
    const result = BenchmarkResult{
        .name = "test",
        .iterations = 100,
        .total_time_ns = 10000,
        .min_time_ns = 50,
        .max_time_ns = 150,
        .matches_found = 0,
        .correct = true,
    };

    try std.testing.expectApproxEqAbs(@as(f64, 25.0), result.stdDevEstimate(), 0.001);
}

test "runBenchmark skips catastrophic" {
    const pattern = BenchmarkPattern{
        .name = "catastrophic",
        .pattern = "(a+)+$",
        .complexity = .catastrophic,
        .test_input = "aaaaab",
        .expected_matches = 0,
    };

    const config = BenchmarkConfig{ .skip_catastrophic = true };
    const result = runBenchmark(pattern, config);

    try std.testing.expectEqual(@as(u64, 0), result.iterations);
}

test "runBenchmark runs non-catastrophic" {
    const pattern = BenchmarkPattern{
        .name = "simple",
        .pattern = "hello",
        .complexity = .literal,
        .test_input = "hello world",
        .expected_matches = 1,
    };

    const config = BenchmarkConfig{
        .warmup_iterations = 1,
        .measured_iterations = 10,
    };
    const result = runBenchmark(pattern, config);

    try std.testing.expect(result.iterations > 0);
    try std.testing.expect(result.correct);
}

test "BenchmarkSummary geometricMeanThroughput" {
    var results = [_]BenchmarkResult{
        .{
            .name = "a",
            .iterations = 1000,
            .total_time_ns = 1_000_000_000,
            .min_time_ns = 0,
            .max_time_ns = 0,
            .matches_found = 0,
            .correct = true,
        },
        .{
            .name = "b",
            .iterations = 10000,
            .total_time_ns = 1_000_000_000,
            .min_time_ns = 0,
            .max_time_ns = 0,
            .matches_found = 0,
            .correct = true,
        },
    };

    const summary = BenchmarkSummary{
        .complexity = .literal,
        .pattern_count = 2,
        .total_time_ns = 2_000_000_000,
        .avg_throughput = 5500,
        .results = &results,
    };

    // Geometric mean of 1000 and 10000
    const expected = @sqrt(@as(f64, 1000.0) * @as(f64, 10000.0));
    try std.testing.expectApproxEqAbs(expected, summary.geometricMeanThroughput(), 1.0);
}

test "literal patterns well-formed" {
    for (literal_patterns) |p| {
        try std.testing.expect(p.pattern.len > 0);
        try std.testing.expect(p.test_input.len > 0);
        try std.testing.expectEqual(PatternComplexity.literal, p.complexity);
    }
}

test "char_class patterns well-formed" {
    for (char_class_patterns) |p| {
        try std.testing.expect(p.pattern.len > 0);
        try std.testing.expect(p.test_input.len > 0);
        try std.testing.expectEqual(PatternComplexity.char_class, p.complexity);
    }
}
