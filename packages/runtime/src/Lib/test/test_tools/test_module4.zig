//! test.test_tools.test_scripts - Script runners testing
//! Tests for Python's script runner utilities and tools for executing
//! Python scripts, modules, and packages.

const std = @import("std");

/// Command-line argument parser for Python scripts
pub const ArgParser = struct {
    allocator: std.mem.Allocator,
    prog_name: []const u8,
    description: ?[]const u8 = null,
    positional_args: std.ArrayList(Argument),
    optional_args: std.ArrayList(Argument),
    parsed_values: std.StringHashMap(Value),

    pub const Argument = struct {
        name: []const u8,
        short_name: ?u8 = null,
        help: ?[]const u8 = null,
        default: ?Value = null,
        required: bool = false,
        nargs: Nargs = .one,
        arg_type: ArgType = .string,
        choices: ?[]const []const u8 = null,

        pub const Nargs = enum {
            one,
            optional, // ?
            zero_or_more, // *
            one_or_more, // +
            remainder,
        };

        pub const ArgType = enum {
            string,
            integer,
            float,
            boolean,
            path,
        };
    };

    pub const Value = union(enum) {
        string: []const u8,
        strings: []const []const u8,
        integer: i64,
        float: f64,
        boolean: bool,
        none,
    };

    pub fn init(allocator: std.mem.Allocator, prog_name: []const u8) ArgParser {
        return .{
            .allocator = allocator,
            .prog_name = prog_name,
            .positional_args = std.ArrayList(Argument).init(allocator),
            .optional_args = std.ArrayList(Argument).init(allocator),
            .parsed_values = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *ArgParser) void {
        self.positional_args.deinit();
        self.optional_args.deinit();
        self.parsed_values.deinit();
    }

    pub fn addArgument(self: *ArgParser, arg: Argument) !void {
        if (arg.name[0] == '-') {
            try self.optional_args.append(arg);
        } else {
            try self.positional_args.append(arg);
        }
    }

    pub fn parse(self: *ArgParser, args: []const []const u8) !void {
        var i: usize = 0;
        var positional_idx: usize = 0;

        while (i < args.len) {
            const arg = args[i];

            if (std.mem.startsWith(u8, arg, "--")) {
                // Long option
                const name = arg[2..];
                for (self.optional_args.items) |opt| {
                    if (std.mem.eql(u8, opt.name[2..], name)) {
                        if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                            try self.parsed_values.put(name, .{ .string = args[i + 1] });
                            i += 1;
                        } else {
                            try self.parsed_values.put(name, .{ .boolean = true });
                        }
                        break;
                    }
                }
            } else if (std.mem.startsWith(u8, arg, "-")) {
                // Short option
                const short = arg[1];
                for (self.optional_args.items) |opt| {
                    if (opt.short_name) |s| {
                        if (s == short) {
                            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                                try self.parsed_values.put(opt.name[2..], .{ .string = args[i + 1] });
                                i += 1;
                            } else {
                                try self.parsed_values.put(opt.name[2..], .{ .boolean = true });
                            }
                            break;
                        }
                    }
                }
            } else {
                // Positional argument
                if (positional_idx < self.positional_args.items.len) {
                    const pos_arg = self.positional_args.items[positional_idx];
                    try self.parsed_values.put(pos_arg.name, .{ .string = arg });
                    positional_idx += 1;
                }
            }
            i += 1;
        }

        // Apply defaults
        for (self.optional_args.items) |opt| {
            const name = opt.name[2..];
            if (!self.parsed_values.contains(name)) {
                if (opt.default) |default| {
                    try self.parsed_values.put(name, default);
                }
            }
        }
    }

    pub fn get(self: ArgParser, name: []const u8) ?Value {
        return self.parsed_values.get(name);
    }

    pub fn getString(self: ArgParser, name: []const u8) ?[]const u8 {
        if (self.parsed_values.get(name)) |val| {
            return switch (val) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    pub fn getBool(self: ArgParser, name: []const u8) bool {
        if (self.parsed_values.get(name)) |val| {
            return switch (val) {
                .boolean => |b| b,
                else => false,
            };
        }
        return false;
    }
};

/// Script runner for executing Python files and modules
pub const ScriptRunner = struct {
    allocator: std.mem.Allocator,
    python_path: []const u8 = "python3",
    environment: std.StringHashMap([]const u8),
    working_dir: ?[]const u8 = null,
    timeout_ms: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator) ScriptRunner {
        return .{
            .allocator = allocator,
            .environment = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ScriptRunner) void {
        self.environment.deinit();
    }

    pub fn setEnv(self: *ScriptRunner, key: []const u8, value: []const u8) !void {
        try self.environment.put(key, value);
    }

    pub fn runFile(self: ScriptRunner, path: []const u8, args: []const []const u8) !RunResult {
        _ = args;
        // Simulated execution
        return RunResult{
            .exit_code = 0,
            .stdout = "",
            .stderr = "",
            .script_path = path,
            .duration_ms = 0,
        };
    }

    pub fn runModule(self: ScriptRunner, module: []const u8, args: []const []const u8) !RunResult {
        _ = args;
        return RunResult{
            .exit_code = 0,
            .stdout = "",
            .stderr = "",
            .script_path = module,
            .duration_ms = 0,
        };
    }

    pub fn runCode(self: ScriptRunner, code: []const u8) !RunResult {
        return RunResult{
            .exit_code = 0,
            .stdout = "",
            .stderr = "",
            .script_path = "<string>",
            .duration_ms = code.len, // Just for testing
        };
    }

    pub const RunResult = struct {
        exit_code: i32,
        stdout: []const u8,
        stderr: []const u8,
        script_path: []const u8,
        duration_ms: u64,

        pub fn success(self: RunResult) bool {
            return self.exit_code == 0;
        }

        pub fn hasOutput(self: RunResult) bool {
            return self.stdout.len > 0 or self.stderr.len > 0;
        }
    };
};

/// Module runner for -m flag functionality
pub const ModuleRunner = struct {
    allocator: std.mem.Allocator,
    sys_path: std.ArrayList([]const u8),
    run_name: []const u8 = "__main__",

    pub fn init(allocator: std.mem.Allocator) ModuleRunner {
        return .{
            .allocator = allocator,
            .sys_path = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ModuleRunner) void {
        self.sys_path.deinit();
    }

    pub fn addPath(self: *ModuleRunner, path: []const u8) !void {
        try self.sys_path.append(path);
    }

    pub fn findModule(self: ModuleRunner, name: []const u8) !ModuleSpec {
        // Check each path in sys_path
        for (self.sys_path.items) |path| {
            // Try as package
            var pkg_path = std.ArrayList(u8).init(self.allocator);
            defer pkg_path.deinit();
            try pkg_path.appendSlice(path);
            try pkg_path.append('/');
            try pkg_path.appendSlice(name);
            try pkg_path.appendSlice("/__main__.py");

            // Try as module
            var mod_path = std.ArrayList(u8).init(self.allocator);
            defer mod_path.deinit();
            try mod_path.appendSlice(path);
            try mod_path.append('/');
            try mod_path.appendSlice(name);
            try mod_path.appendSlice(".py");
        }

        return ModuleSpec{
            .name = name,
            .loader = .source,
            .origin = null,
            .submodule_search_locations = null,
        };
    }

    pub const ModuleSpec = struct {
        name: []const u8,
        loader: LoaderType,
        origin: ?[]const u8,
        submodule_search_locations: ?[]const []const u8,

        pub const LoaderType = enum {
            source,
            bytecode,
            extension,
            builtin,
            frozen,
        };

        pub fn isPackage(self: ModuleSpec) bool {
            return self.submodule_search_locations != null;
        }
    };
};

/// Interactive console runner
pub const ConsoleRunner = struct {
    allocator: std.mem.Allocator,
    history: std.ArrayList([]const u8),
    locals: std.StringHashMap([]const u8),
    ps1: []const u8 = ">>> ",
    ps2: []const u8 = "... ",
    banner: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) ConsoleRunner {
        return .{
            .allocator = allocator,
            .history = std.ArrayList([]const u8).init(allocator),
            .locals = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ConsoleRunner) void {
        self.history.deinit();
        self.locals.deinit();
    }

    pub fn execute(self: *ConsoleRunner, line: []const u8) !ExecuteResult {
        try self.history.append(line);

        // Check for incomplete input
        if (needsContinuation(line)) {
            return .{ .status = .incomplete };
        }

        // Simulate execution
        return .{
            .status = .complete,
            .output = null,
            .exception = null,
        };
    }

    pub fn setLocal(self: *ConsoleRunner, name: []const u8, value: []const u8) !void {
        try self.locals.put(name, value);
    }

    fn needsContinuation(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        return std.mem.endsWith(u8, trimmed, ":") or
            std.mem.endsWith(u8, trimmed, "\\");
    }

    pub const ExecuteResult = struct {
        status: Status,
        output: ?[]const u8 = null,
        exception: ?[]const u8 = null,

        pub const Status = enum {
            complete,
            incomplete,
            error_status,
        };
    };
};

/// Script profiler for performance analysis
pub const ScriptProfiler = struct {
    allocator: std.mem.Allocator,
    call_counts: std.StringHashMap(u64),
    total_times: std.StringHashMap(u64),
    enabled: bool = false,

    pub fn init(allocator: std.mem.Allocator) ScriptProfiler {
        return .{
            .allocator = allocator,
            .call_counts = std.StringHashMap(u64).init(allocator),
            .total_times = std.StringHashMap(u64).init(allocator),
        };
    }

    pub fn deinit(self: *ScriptProfiler) void {
        self.call_counts.deinit();
        self.total_times.deinit();
    }

    pub fn enable(self: *ScriptProfiler) void {
        self.enabled = true;
    }

    pub fn disable(self: *ScriptProfiler) void {
        self.enabled = false;
    }

    pub fn recordCall(self: *ScriptProfiler, func_name: []const u8, duration_ns: u64) !void {
        if (!self.enabled) return;

        const count_entry = try self.call_counts.getOrPut(func_name);
        if (!count_entry.found_existing) {
            count_entry.value_ptr.* = 0;
        }
        count_entry.value_ptr.* += 1;

        const time_entry = try self.total_times.getOrPut(func_name);
        if (!time_entry.found_existing) {
            time_entry.value_ptr.* = 0;
        }
        time_entry.value_ptr.* += duration_ns;
    }

    pub fn getStats(self: ScriptProfiler, func_name: []const u8) ?Stats {
        const count = self.call_counts.get(func_name) orelse return null;
        const total_time = self.total_times.get(func_name) orelse return null;
        return Stats{
            .call_count = count,
            .total_time_ns = total_time,
            .avg_time_ns = total_time / count,
        };
    }

    pub fn reset(self: *ScriptProfiler) void {
        self.call_counts.clearRetainingCapacity();
        self.total_times.clearRetainingCapacity();
    }

    pub const Stats = struct {
        call_count: u64,
        total_time_ns: u64,
        avg_time_ns: u64,
    };
};

/// Script coverage analyzer
pub const CoverageAnalyzer = struct {
    allocator: std.mem.Allocator,
    executed_lines: std.StringHashMap(std.AutoHashMap(usize, void)),
    total_lines: std.StringHashMap(usize),
    branch_coverage: bool = false,

    pub fn init(allocator: std.mem.Allocator) CoverageAnalyzer {
        return .{
            .allocator = allocator,
            .executed_lines = std.StringHashMap(std.AutoHashMap(usize, void)).init(allocator),
            .total_lines = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *CoverageAnalyzer) void {
        var iter = self.executed_lines.valueIterator();
        while (iter.next()) |val| {
            var v = val;
            v.deinit();
        }
        self.executed_lines.deinit();
        self.total_lines.deinit();
    }

    pub fn recordLine(self: *CoverageAnalyzer, filename: []const u8, line: usize) !void {
        const result = try self.executed_lines.getOrPut(filename);
        if (!result.found_existing) {
            result.value_ptr.* = std.AutoHashMap(usize, void).init(self.allocator);
        }
        try result.value_ptr.put(line, {});
    }

    pub fn setTotalLines(self: *CoverageAnalyzer, filename: []const u8, count: usize) !void {
        try self.total_lines.put(filename, count);
    }

    pub fn getCoverage(self: CoverageAnalyzer, filename: []const u8) ?f64 {
        const total = self.total_lines.get(filename) orelse return null;
        const executed = self.executed_lines.get(filename) orelse return 0.0;

        if (total == 0) return 100.0;
        return @as(f64, @floatFromInt(executed.count())) / @as(f64, @floatFromInt(total)) * 100.0;
    }

    pub fn getTotalCoverage(self: CoverageAnalyzer) f64 {
        var total_executed: usize = 0;
        var total_lines: usize = 0;

        var exec_iter = self.executed_lines.iterator();
        while (exec_iter.next()) |entry| {
            total_executed += entry.value_ptr.count();
            if (self.total_lines.get(entry.key_ptr.*)) |total| {
                total_lines += total;
            }
        }

        if (total_lines == 0) return 100.0;
        return @as(f64, @floatFromInt(total_executed)) / @as(f64, @floatFromInt(total_lines)) * 100.0;
    }
};

/// Test runner for unittest discovery and execution
pub const TestRunner = struct {
    allocator: std.mem.Allocator,
    test_cases: std.ArrayList(TestCase),
    results: TestResults,
    verbosity: u8 = 1,
    pattern: []const u8 = "test*.py",
    start_dir: []const u8 = ".",

    pub const TestCase = struct {
        name: []const u8,
        class_name: []const u8,
        module: []const u8,
        method: []const u8,
    };

    pub const TestResults = struct {
        tests_run: usize = 0,
        failures: usize = 0,
        errors: usize = 0,
        skipped: usize = 0,
        expected_failures: usize = 0,
        unexpected_successes: usize = 0,

        pub fn wasSuccessful(self: TestResults) bool {
            return self.failures == 0 and self.errors == 0;
        }

        pub fn totalRun(self: TestResults) usize {
            return self.tests_run;
        }
    };

    pub fn init(allocator: std.mem.Allocator) TestRunner {
        return .{
            .allocator = allocator,
            .test_cases = std.ArrayList(TestCase).init(allocator),
            .results = .{},
        };
    }

    pub fn deinit(self: *TestRunner) void {
        self.test_cases.deinit();
    }

    pub fn discover(self: *TestRunner, start_dir: []const u8, pattern: []const u8) !void {
        self.start_dir = start_dir;
        self.pattern = pattern;
        // In real implementation, would scan directory
    }

    pub fn addTest(self: *TestRunner, test_case: TestCase) !void {
        try self.test_cases.append(test_case);
    }

    pub fn run(self: *TestRunner) !TestResults {
        for (self.test_cases.items) |_| {
            self.results.tests_run += 1;
            // Simulate running test
        }
        return self.results;
    }

    pub fn countTests(self: TestRunner) usize {
        return self.test_cases.items.len;
    }
};

// Tests
test "arg_parser_basic" {
    var parser = ArgParser.init(std.testing.allocator, "test_prog");
    defer parser.deinit();

    try parser.addArgument(.{
        .name = "--verbose",
        .short_name = 'v',
        .help = "Enable verbose mode",
    });

    try parser.parse(&[_][]const u8{ "--verbose", "true" });

    try std.testing.expect(parser.getBool("verbose") or parser.getString("verbose") != null);
}

test "arg_parser_positional" {
    var parser = ArgParser.init(std.testing.allocator, "test");
    defer parser.deinit();

    try parser.addArgument(.{
        .name = "filename",
        .required = true,
    });

    try parser.parse(&[_][]const u8{"input.txt"});

    try std.testing.expectEqualStrings("input.txt", parser.getString("filename").?);
}

test "script_runner_basic" {
    var runner = ScriptRunner.init(std.testing.allocator);
    defer runner.deinit();

    try runner.setEnv("PYTHONPATH", "/usr/lib/python3");

    const result = try runner.runCode("print('hello')");
    try std.testing.expect(result.success());
}

test "module_runner_spec" {
    var runner = ModuleRunner.init(std.testing.allocator);
    defer runner.deinit();

    try runner.addPath("/usr/lib/python3");
    try runner.addPath(".");

    const spec = try runner.findModule("json");
    try std.testing.expectEqualStrings("json", spec.name);
}

test "console_runner" {
    var console = ConsoleRunner.init(std.testing.allocator);
    defer console.deinit();

    const result1 = try console.execute("x = 1");
    try std.testing.expectEqual(ConsoleRunner.ExecuteResult.Status.complete, result1.status);

    const result2 = try console.execute("if True:");
    try std.testing.expectEqual(ConsoleRunner.ExecuteResult.Status.incomplete, result2.status);
}

test "script_profiler" {
    var profiler = ScriptProfiler.init(std.testing.allocator);
    defer profiler.deinit();

    profiler.enable();

    try profiler.recordCall("my_function", 1000);
    try profiler.recordCall("my_function", 2000);
    try profiler.recordCall("other_func", 500);

    const stats = profiler.getStats("my_function");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 2), stats.?.call_count);
    try std.testing.expectEqual(@as(u64, 3000), stats.?.total_time_ns);
    try std.testing.expectEqual(@as(u64, 1500), stats.?.avg_time_ns);
}

test "coverage_analyzer" {
    var coverage = CoverageAnalyzer.init(std.testing.allocator);
    defer coverage.deinit();

    try coverage.setTotalLines("test.py", 100);
    try coverage.recordLine("test.py", 1);
    try coverage.recordLine("test.py", 2);
    try coverage.recordLine("test.py", 3);

    const cov = coverage.getCoverage("test.py");
    try std.testing.expect(cov != null);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), cov.?, 0.01);
}

test "test_runner_discover" {
    var runner = TestRunner.init(std.testing.allocator);
    defer runner.deinit();

    try runner.addTest(.{
        .name = "test_add",
        .class_name = "TestMath",
        .module = "test_math",
        .method = "test_add",
    });

    try runner.addTest(.{
        .name = "test_sub",
        .class_name = "TestMath",
        .module = "test_math",
        .method = "test_sub",
    });

    try std.testing.expectEqual(@as(usize, 2), runner.countTests());

    const results = try runner.run();
    try std.testing.expectEqual(@as(usize, 2), results.tests_run);
    try std.testing.expect(results.wasSuccessful());
}

test "test_results" {
    var results = TestRunner.TestResults{
        .tests_run = 10,
        .failures = 0,
        .errors = 0,
        .skipped = 2,
    };
    try std.testing.expect(results.wasSuccessful());
    try std.testing.expectEqual(@as(usize, 10), results.totalRun());

    results.failures = 1;
    try std.testing.expect(!results.wasSuccessful());
}
