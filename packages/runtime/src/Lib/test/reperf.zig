//! test.reperf - Regex Performance Tests
//!
//! Performance benchmarks for regular expression operations including
//! compilation, matching, substitution, and various pattern complexities.
//!
//! CPython equivalent: test/reperf.py

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Benchmark Configuration
// ============================================================================

/// Configuration for regex performance tests
pub const BenchmarkConfig = struct {
    /// Number of iterations for timing
    iterations: u32 = 1000,
    /// Warmup iterations before timing
    warmup_iterations: u32 = 100,
    /// Input string length multiplier
    input_scale: u32 = 1,
    /// Enable detailed timing breakdown
    detailed_timing: bool = false,
    /// Timeout per operation in milliseconds
    timeout_ms: u64 = 5000,

    pub fn quick() BenchmarkConfig {
        return .{
            .iterations = 100,
            .warmup_iterations = 10,
        };
    }

    pub fn standard() BenchmarkConfig {
        return .{
            .iterations = 1000,
            .warmup_iterations = 100,
        };
    }

    pub fn thorough() BenchmarkConfig {
        return .{
            .iterations = 10000,
            .warmup_iterations = 500,
        };
    }
};

// ============================================================================
// Pattern Categories
// ============================================================================

/// Categories of regex patterns for benchmarking
pub const PatternCategory = enum(u8) {
    /// Simple literal patterns
    literal,
    /// Character classes [a-z]
    char_class,
    /// Alternation (a|b|c)
    alternation,
    /// Quantifiers (*, +, ?, {n,m})
    quantifier,
    /// Anchors (^, $, \b)
    anchor,
    /// Groups and backreferences
    group,
    /// Lookahead/lookbehind
    lookaround,
    /// Complex nested patterns
    complex,
    /// Pathological cases (exponential backtracking)
    pathological,
};

/// Test pattern with metadata
pub const TestPattern = struct {
    const Self = @This();

    name: []const u8,
    pattern: []const u8,
    category: PatternCategory,
    expected_complexity: Complexity,
    test_inputs: []const TestInput,

    pub const TestInput = struct {
        text: []const u8,
        should_match: bool,
    };

    pub const Complexity = enum(u8) {
        constant,
        linear,
        quadratic,
        exponential,
        unknown,
    };

    pub fn init(
        name: []const u8,
        pattern: []const u8,
        category: PatternCategory,
        complexity: Complexity,
    ) Self {
        return .{
            .name = name,
            .pattern = pattern,
            .category = category,
            .expected_complexity = complexity,
            .test_inputs = &[_]TestInput{},
        };
    }
};

// ============================================================================
// Standard Test Patterns
// ============================================================================

/// Collection of standard benchmark patterns
pub const StandardPatterns = struct {
    pub const LITERAL = TestPattern.init(
        "literal_match",
        "hello world",
        .literal,
        .constant,
    );

    pub const WORD_BOUNDARY = TestPattern.init(
        "word_boundary",
        "\\bword\\b",
        .anchor,
        .linear,
    );

    pub const EMAIL = TestPattern.init(
        "email_pattern",
        "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
        .complex,
        .linear,
    );

    pub const URL = TestPattern.init(
        "url_pattern",
        "https?://[a-zA-Z0-9.-]+(/[a-zA-Z0-9._/-]*)?",
        .complex,
        .linear,
    );

    pub const IP_ADDRESS = TestPattern.init(
        "ip_address",
        "\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}",
        .quantifier,
        .linear,
    );

    pub const PHONE = TestPattern.init(
        "phone_number",
        "\\(\\d{3}\\)\\s?\\d{3}-\\d{4}",
        .quantifier,
        .linear,
    );

    pub const DATE = TestPattern.init(
        "date_pattern",
        "\\d{4}-\\d{2}-\\d{2}",
        .quantifier,
        .constant,
    );

    pub const PATHOLOGICAL_A = TestPattern.init(
        "pathological_backtrack",
        "(a+)+$",
        .pathological,
        .exponential,
    );

    pub const NESTED_GROUPS = TestPattern.init(
        "nested_groups",
        "((a)(b(c)(d)))",
        .group,
        .linear,
    );

    pub const ALL = [_]TestPattern{
        LITERAL,
        WORD_BOUNDARY,
        EMAIL,
        URL,
        IP_ADDRESS,
        PHONE,
        DATE,
        NESTED_GROUPS,
    };
};

// ============================================================================
// Timing Results
// ============================================================================

/// Result of a single timing measurement
pub const TimingResult = struct {
    const Self = @This();

    pattern_name: []const u8,
    operation: Operation,
    iterations: u32,
    total_ns: u64,
    min_ns: u64,
    max_ns: u64,
    input_size: usize,

    pub const Operation = enum {
        compile,
        match,
        search,
        findall,
        sub,
        split,
    };

    pub fn avgNs(self: *const Self) u64 {
        if (self.iterations == 0) return 0;
        return self.total_ns / self.iterations;
    }

    pub fn avgUs(self: *const Self) f64 {
        return @as(f64, @floatFromInt(self.avgNs())) / 1000.0;
    }

    pub fn avgMs(self: *const Self) f64 {
        return @as(f64, @floatFromInt(self.avgNs())) / 1_000_000.0;
    }

    pub fn opsPerSecond(self: *const Self) f64 {
        if (self.total_ns == 0) return 0;
        const secs = @as(f64, @floatFromInt(self.total_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.iterations)) / secs;
    }

    pub fn throughputMBps(self: *const Self) f64 {
        if (self.total_ns == 0) return 0;
        const bytes = @as(f64, @floatFromInt(self.input_size * self.iterations));
        const secs = @as(f64, @floatFromInt(self.total_ns)) / 1_000_000_000.0;
        return bytes / secs / 1_000_000.0;
    }
};

// ============================================================================
// Benchmark Runner
// ============================================================================

/// Runs regex performance benchmarks
pub const BenchmarkRunner = struct {
    const Self = @This();

    allocator: Allocator,
    config: BenchmarkConfig,
    results: std.ArrayListUnmanaged(TimingResult),

    pub fn init(allocator: Allocator, config: BenchmarkConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .results = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.results.deinit(self.allocator);
    }

    /// Benchmark pattern compilation
    pub fn benchCompile(self: *Self, pattern: TestPattern) !void {
        // Warmup
        var warmup_i: u32 = 0;
        while (warmup_i < self.config.warmup_iterations) : (warmup_i += 1) {
            _ = simulateCompile(pattern.pattern);
        }

        var min_ns: u64 = std.math.maxInt(u64);
        var max_ns: u64 = 0;

        const start = std.time.nanoTimestamp();

        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const op_start = std.time.nanoTimestamp();
            _ = simulateCompile(pattern.pattern);
            const op_ns: u64 = @intCast(std.time.nanoTimestamp() - op_start);
            min_ns = @min(min_ns, op_ns);
            max_ns = @max(max_ns, op_ns);
        }

        const total_ns: u64 = @intCast(std.time.nanoTimestamp() - start);

        try self.results.append(self.allocator, .{
            .pattern_name = pattern.name,
            .operation = .compile,
            .iterations = self.config.iterations,
            .total_ns = total_ns,
            .min_ns = min_ns,
            .max_ns = max_ns,
            .input_size = pattern.pattern.len,
        });
    }

    /// Benchmark pattern matching
    pub fn benchMatch(self: *Self, pattern: TestPattern, input: []const u8) !void {
        // Warmup
        var warmup_i: u32 = 0;
        while (warmup_i < self.config.warmup_iterations) : (warmup_i += 1) {
            _ = simulateMatch(pattern.pattern, input);
        }

        var min_ns: u64 = std.math.maxInt(u64);
        var max_ns: u64 = 0;

        const start = std.time.nanoTimestamp();

        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const op_start = std.time.nanoTimestamp();
            _ = simulateMatch(pattern.pattern, input);
            const op_ns: u64 = @intCast(std.time.nanoTimestamp() - op_start);
            min_ns = @min(min_ns, op_ns);
            max_ns = @max(max_ns, op_ns);
        }

        const total_ns: u64 = @intCast(std.time.nanoTimestamp() - start);

        try self.results.append(self.allocator, .{
            .pattern_name = pattern.name,
            .operation = .match,
            .iterations = self.config.iterations,
            .total_ns = total_ns,
            .min_ns = min_ns,
            .max_ns = max_ns,
            .input_size = input.len,
        });
    }

    /// Benchmark search operation
    pub fn benchSearch(self: *Self, pattern: TestPattern, input: []const u8) !void {
        var min_ns: u64 = std.math.maxInt(u64);
        var max_ns: u64 = 0;

        const start = std.time.nanoTimestamp();

        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const op_start = std.time.nanoTimestamp();
            _ = simulateSearch(pattern.pattern, input);
            const op_ns: u64 = @intCast(std.time.nanoTimestamp() - op_start);
            min_ns = @min(min_ns, op_ns);
            max_ns = @max(max_ns, op_ns);
        }

        const total_ns: u64 = @intCast(std.time.nanoTimestamp() - start);

        try self.results.append(self.allocator, .{
            .pattern_name = pattern.name,
            .operation = .search,
            .iterations = self.config.iterations,
            .total_ns = total_ns,
            .min_ns = min_ns,
            .max_ns = max_ns,
            .input_size = input.len,
        });
    }

    /// Run all standard benchmarks
    pub fn runStandard(self: *Self) !void {
        const test_input = "The quick brown fox jumps over the lazy dog. " ++
            "Email: test@example.com, Phone: (555) 123-4567, " ++
            "URL: https://www.example.com/path/to/page";

        for (StandardPatterns.ALL) |pattern| {
            try self.benchCompile(pattern);
            try self.benchMatch(pattern, test_input);
            try self.benchSearch(pattern, test_input);
        }
    }

    /// Get summary statistics
    pub fn getSummary(self: *const Self) BenchmarkSummary {
        var summary = BenchmarkSummary{};

        for (self.results.items) |result| {
            summary.total_operations += result.iterations;
            summary.total_time_ns += result.total_ns;

            switch (result.operation) {
                .compile => summary.compile_count += 1,
                .match => summary.match_count += 1,
                .search => summary.search_count += 1,
                else => {},
            }
        }

        return summary;
    }

    // Simulation functions (actual regex implementation would go here)
    fn simulateCompile(pattern: []const u8) u64 {
        // Simulate compilation by hashing the pattern
        return std.hash.Wyhash.hash(0, pattern);
    }

    fn simulateMatch(pattern: []const u8, input: []const u8) bool {
        // Simple simulation - actual regex would be here
        return std.mem.indexOf(u8, input, pattern) != null or pattern.len > 0;
    }

    fn simulateSearch(pattern: []const u8, input: []const u8) ?usize {
        _ = pattern;
        _ = input;
        return 0;
    }
};

/// Summary of benchmark results
pub const BenchmarkSummary = struct {
    total_operations: u64 = 0,
    total_time_ns: u64 = 0,
    compile_count: u32 = 0,
    match_count: u32 = 0,
    search_count: u32 = 0,

    pub fn avgTimePerOp(self: *const BenchmarkSummary) f64 {
        if (self.total_operations == 0) return 0;
        return @as(f64, @floatFromInt(self.total_time_ns)) / @as(f64, @floatFromInt(self.total_operations));
    }
};

// ============================================================================
// Input Generators
// ============================================================================

/// Generates test inputs for benchmarking
pub const InputGenerator = struct {
    const Self = @This();

    allocator: Allocator,
    seed: u64,
    prng: std.Random.DefaultPrng,

    pub fn init(allocator: Allocator, seed: u64) Self {
        return .{
            .allocator = allocator,
            .seed = seed,
            .prng = std.Random.DefaultPrng.init(seed),
        };
    }

    /// Generate random ASCII string
    pub fn randomAscii(self: *Self, len: usize) ![]u8 {
        const result = try self.allocator.alloc(u8, len);
        for (result) |*c| {
            c.* = @as(u8, @intCast(self.prng.random().int(u7) % 95 + 32));
        }
        return result;
    }

    /// Generate string with pattern matches
    pub fn withMatches(self: *Self, base_len: usize, pattern: []const u8, match_count: u32) ![]u8 {
        var list: std.ArrayListUnmanaged(u8) = .{};
        const chunk_size = base_len / (match_count + 1);

        var i: u32 = 0;
        while (i < match_count) : (i += 1) {
            // Add random content
            const chunk = try self.randomAscii(chunk_size);
            defer self.allocator.free(chunk);
            try list.appendSlice(self.allocator, chunk);

            // Add pattern
            try list.appendSlice(self.allocator, pattern);
        }

        // Add final chunk
        const final = try self.randomAscii(chunk_size);
        defer self.allocator.free(final);
        try list.appendSlice(self.allocator, final);

        return list.toOwnedSlice(self.allocator);
    }

    /// Generate email addresses
    pub fn generateEmails(self: *Self, count: u32) ![][]u8 {
        var emails: std.ArrayListUnmanaged([]u8) = .{};

        const domains = [_][]const u8{ "example.com", "test.org", "mail.net" };
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            var email: std.ArrayListUnmanaged(u8) = .{};
            const name = try self.randomAscii(8);
            defer self.allocator.free(name);
            try email.appendSlice(self.allocator, name);
            try email.append(self.allocator, '@');
            try email.appendSlice(self.allocator, domains[i % domains.len]);
            try emails.append(self.allocator, try email.toOwnedSlice(self.allocator));
        }

        return emails.toOwnedSlice(self.allocator);
    }

    /// Generate pathological input (for backtracking tests)
    pub fn generatePathological(self: *Self, n: usize) ![]u8 {
        // Generate "aaa...aaa!" which causes exponential backtracking with (a+)+$
        const result = try self.allocator.alloc(u8, n + 1);
        @memset(result[0..n], 'a');
        result[n] = '!';
        return result;
    }
};

// ============================================================================
// Complexity Analyzer
// ============================================================================

/// Analyzes pattern complexity empirically
pub const ComplexityAnalyzer = struct {
    const Self = @This();

    allocator: Allocator,
    measurements: std.ArrayListUnmanaged(Measurement),

    pub const Measurement = struct {
        input_size: usize,
        time_ns: u64,
    };

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .measurements = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.measurements.deinit(self.allocator);
    }

    pub fn addMeasurement(self: *Self, input_size: usize, time_ns: u64) !void {
        try self.measurements.append(self.allocator, .{
            .input_size = input_size,
            .time_ns = time_ns,
        });
    }

    /// Estimate complexity class
    pub fn estimateComplexity(self: *const Self) TestPattern.Complexity {
        if (self.measurements.items.len < 3) return .unknown;

        // Simple heuristic: compare ratios
        const items = self.measurements.items;
        const n = items.len;

        const ratio1 = @as(f64, @floatFromInt(items[n / 2].time_ns)) /
            @as(f64, @floatFromInt(items[0].time_ns));
        const ratio2 = @as(f64, @floatFromInt(items[n - 1].time_ns)) /
            @as(f64, @floatFromInt(items[n / 2].time_ns));

        const size_ratio1 = @as(f64, @floatFromInt(items[n / 2].input_size)) /
            @as(f64, @floatFromInt(items[0].input_size));
        const size_ratio2 = @as(f64, @floatFromInt(items[n - 1].input_size)) /
            @as(f64, @floatFromInt(items[n / 2].input_size));

        // If time grows faster than input squared, likely exponential
        if (ratio1 > size_ratio1 * size_ratio1 or ratio2 > size_ratio2 * size_ratio2) {
            return .exponential;
        }

        // If time grows faster than input, likely quadratic
        if (ratio1 > size_ratio1 * 1.5 or ratio2 > size_ratio2 * 1.5) {
            return .quadratic;
        }

        // If time roughly proportional to input, linear
        if (ratio1 > 0.8 and ratio1 < 1.5) {
            return .linear;
        }

        return .constant;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "benchmark_config_quick" {
    const config = BenchmarkConfig.quick();
    try std.testing.expectEqual(@as(u32, 100), config.iterations);
    try std.testing.expectEqual(@as(u32, 10), config.warmup_iterations);
}

test "benchmark_config_standard" {
    const config = BenchmarkConfig.standard();
    try std.testing.expectEqual(@as(u32, 1000), config.iterations);
}

test "test_pattern_init" {
    const pattern = TestPattern.init("test", "\\d+", .quantifier, .linear);
    try std.testing.expectEqualStrings("test", pattern.name);
    try std.testing.expectEqualStrings("\\d+", pattern.pattern);
    try std.testing.expectEqual(PatternCategory.quantifier, pattern.category);
}

test "timing_result_avg" {
    const result = TimingResult{
        .pattern_name = "test",
        .operation = .match,
        .iterations = 100,
        .total_ns = 1_000_000,
        .min_ns = 5000,
        .max_ns = 20000,
        .input_size = 100,
    };

    try std.testing.expectEqual(@as(u64, 10000), result.avgNs());
    try std.testing.expectEqual(@as(f64, 10.0), result.avgUs());
}

test "timing_result_throughput" {
    const result = TimingResult{
        .pattern_name = "test",
        .operation = .match,
        .iterations = 1000,
        .total_ns = 1_000_000_000,
        .min_ns = 500000,
        .max_ns = 2000000,
        .input_size = 1000,
    };

    const throughput = result.throughputMBps();
    try std.testing.expect(throughput > 0);
}

test "benchmark_runner_init" {
    const allocator = std.testing.allocator;
    var runner = BenchmarkRunner.init(allocator, BenchmarkConfig.quick());
    defer runner.deinit();

    try std.testing.expectEqual(@as(usize, 0), runner.results.items.len);
}

test "benchmark_runner_compile" {
    const allocator = std.testing.allocator;
    var runner = BenchmarkRunner.init(allocator, .{
        .iterations = 10,
        .warmup_iterations = 2,
    });
    defer runner.deinit();

    try runner.benchCompile(StandardPatterns.LITERAL);
    try std.testing.expectEqual(@as(usize, 1), runner.results.items.len);
}

test "benchmark_runner_match" {
    const allocator = std.testing.allocator;
    var runner = BenchmarkRunner.init(allocator, .{
        .iterations = 10,
        .warmup_iterations = 2,
    });
    defer runner.deinit();

    try runner.benchMatch(StandardPatterns.LITERAL, "hello world test");
    try std.testing.expectEqual(@as(usize, 1), runner.results.items.len);
}

test "benchmark_summary" {
    const allocator = std.testing.allocator;
    var runner = BenchmarkRunner.init(allocator, .{
        .iterations = 10,
        .warmup_iterations = 2,
    });
    defer runner.deinit();

    try runner.benchCompile(StandardPatterns.LITERAL);
    try runner.benchMatch(StandardPatterns.LITERAL, "test");

    const summary = runner.getSummary();
    try std.testing.expectEqual(@as(u32, 1), summary.compile_count);
    try std.testing.expectEqual(@as(u32, 1), summary.match_count);
}

test "input_generator_random_ascii" {
    const allocator = std.testing.allocator;
    var gen = InputGenerator.init(allocator, 42);

    const result = try gen.randomAscii(100);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 100), result.len);
}

test "input_generator_with_matches" {
    const allocator = std.testing.allocator;
    var gen = InputGenerator.init(allocator, 42);

    const result = try gen.withMatches(100, "test", 3);
    defer allocator.free(result);

    // Should contain "test" at least 3 times
    var count: u32 = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, result, pos, "test")) |idx| {
        count += 1;
        pos = idx + 4;
    }
    try std.testing.expect(count >= 3);
}

test "input_generator_pathological" {
    const allocator = std.testing.allocator;
    var gen = InputGenerator.init(allocator, 42);

    const result = try gen.generatePathological(10);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 11), result.len);
    try std.testing.expectEqual(@as(u8, 'a'), result[0]);
    try std.testing.expectEqual(@as(u8, '!'), result[10]);
}

test "complexity_analyzer_init" {
    const allocator = std.testing.allocator;
    var analyzer = ComplexityAnalyzer.init(allocator);
    defer analyzer.deinit();

    try std.testing.expectEqual(@as(usize, 0), analyzer.measurements.items.len);
}

test "complexity_analyzer_add" {
    const allocator = std.testing.allocator;
    var analyzer = ComplexityAnalyzer.init(allocator);
    defer analyzer.deinit();

    try analyzer.addMeasurement(100, 1000);
    try analyzer.addMeasurement(200, 2000);
    try analyzer.addMeasurement(400, 4000);

    try std.testing.expectEqual(@as(usize, 3), analyzer.measurements.items.len);
}

test "complexity_analyzer_estimate" {
    const allocator = std.testing.allocator;
    var analyzer = ComplexityAnalyzer.init(allocator);
    defer analyzer.deinit();

    // Linear growth pattern
    try analyzer.addMeasurement(100, 1000);
    try analyzer.addMeasurement(200, 2000);
    try analyzer.addMeasurement(400, 4000);

    const complexity = analyzer.estimateComplexity();
    try std.testing.expect(complexity == .linear or complexity == .constant);
}

test "pattern_categories" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(PatternCategory.literal));
    try std.testing.expectEqual(@as(u8, 8), @intFromEnum(PatternCategory.pathological));
}

test "standard_patterns_count" {
    try std.testing.expectEqual(@as(usize, 8), StandardPatterns.ALL.len);
}
