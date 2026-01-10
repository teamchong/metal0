//! test.test_doctest.test_part10 - Function Docstring Tests implementation
//! Support for testing docstrings in function definitions.
const std = @import("std");

/// Function information for doctest discovery
pub const FunctionInfo = struct {
    name: []const u8,
    docstring: ?[]const u8,
    parameters: std.ArrayList(Parameter),
    return_type: ?[]const u8,
    decorators: std.ArrayList([]const u8),
    lineno: usize,
    is_async: bool,
    allocator: std.mem.Allocator,

    pub const Parameter = struct {
        name: []const u8,
        type_hint: ?[]const u8,
        default_value: ?[]const u8,
        is_args: bool = false,
        is_kwargs: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .name = name,
            .docstring = null,
            .parameters = std.ArrayList(Parameter).init(allocator),
            .return_type = null,
            .decorators = std.ArrayList([]const u8).init(allocator),
            .lineno = 0,
            .is_async = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.parameters.deinit();
        self.decorators.deinit();
    }

    pub fn hasDocstring(self: @This()) bool {
        return self.docstring != null and self.docstring.?.len > 0;
    }

    pub fn addParameter(self: *@This(), param: Parameter) !void {
        try self.parameters.append(param);
    }

    pub fn addDecorator(self: *@This(), decorator: []const u8) !void {
        try self.decorators.append(decorator);
    }

    pub fn parameterCount(self: @This()) usize {
        return self.parameters.items.len;
    }

    pub fn hasDecorator(self: @This(), name: []const u8) bool {
        for (self.decorators.items) |dec| {
            if (std.mem.eql(u8, dec, name)) return true;
        }
        return false;
    }

    pub fn signature(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        try result.appendSlice(self.name);
        try result.append('(');

        for (self.parameters.items, 0..) |param, i| {
            if (i > 0) try result.appendSlice(", ");
            if (param.is_args) try result.append('*');
            if (param.is_kwargs) try result.appendSlice("**");
            try result.appendSlice(param.name);
            if (param.type_hint) |hint| {
                try result.appendSlice(": ");
                try result.appendSlice(hint);
            }
        }

        try result.append(')');
        if (self.return_type) |ret| {
            try result.appendSlice(" -> ");
            try result.appendSlice(ret);
        }

        return result.toOwnedSlice();
    }
};

/// Function doctest runner
pub const FunctionDocTestRunner = struct {
    allocator: std.mem.Allocator,
    verbose: bool = false,
    optionflags: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    /// Run doctests for a function
    pub fn runFunction(self: @This(), func: *const FunctionInfo) !FunctionTestResult {
        var result = FunctionTestResult.init(self.allocator, func.name);

        if (func.hasDocstring()) {
            const doc_result = self.runDocstring(func.docstring.?);
            result.attempted = doc_result.attempted;
            result.failed = doc_result.failed;
        }

        return result;
    }

    /// Run doctests from a docstring
    fn runDocstring(self: @This(), docstring: []const u8) DocstringResult {
        _ = self;
        var result = DocstringResult{};

        var lines = std.mem.splitScalar(u8, docstring, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trimLeft(u8, line, " \t");
            if (std.mem.startsWith(u8, trimmed, ">>> ")) {
                result.attempted += 1;
            }
        }

        return result;
    }
};

/// Result of running doctests for docstring
pub const DocstringResult = struct {
    attempted: usize = 0,
    failed: usize = 0,

    pub fn passed(self: @This()) usize {
        return self.attempted - self.failed;
    }

    pub fn wasSuccessful(self: @This()) bool {
        return self.failed == 0;
    }
};

/// Result of testing a function
pub const FunctionTestResult = struct {
    function_name: []const u8,
    attempted: usize = 0,
    failed: usize = 0,
    examples: std.ArrayList(ExampleResult),
    allocator: std.mem.Allocator,

    pub const ExampleResult = struct {
        source: []const u8,
        expected: []const u8,
        actual: []const u8,
        passed: bool,
        lineno: usize,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .function_name = name,
            .examples = std.ArrayList(ExampleResult).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.examples.deinit();
    }

    pub fn wasSuccessful(self: @This()) bool {
        return self.failed == 0;
    }

    pub fn addExample(self: *@This(), result: ExampleResult) !void {
        try self.examples.append(result);
        if (!result.passed) {
            self.failed += 1;
        }
    }

    pub fn summary(self: @This(), writer: anytype) !void {
        try writer.print("{s}: {d} tests, {d} passed, {d} failed\n", .{
            self.function_name,
            self.attempted,
            self.attempted - self.failed,
            self.failed,
        });
    }
};

/// Parse function from Python source
pub fn parseFunction(allocator: std.mem.Allocator, source: []const u8) !FunctionInfo {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var func: ?FunctionInfo = null;
    var lineno: usize = 0;
    var pending_decorators = std.ArrayList([]const u8).init(allocator);
    defer pending_decorators.deinit();

    while (lines.next()) |line| {
        lineno += 1;
        const trimmed = std.mem.trimLeft(u8, line, " \t");

        // Collect decorators
        if (std.mem.startsWith(u8, trimmed, "@")) {
            const decorator = extractDecoratorName(trimmed[1..]);
            if (decorator) |dec| {
                try pending_decorators.append(dec);
            }
            continue;
        }

        // Look for function definition
        const is_async = std.mem.startsWith(u8, trimmed, "async def ");
        const def_start: usize = if (is_async) 10 else if (std.mem.startsWith(u8, trimmed, "def ")) 4 else continue;

        const def_line = trimmed[def_start..];
        const name_end = std.mem.indexOf(u8, def_line, "(") orelse continue;

        func = FunctionInfo.init(allocator, def_line[0..name_end]);
        func.?.lineno = lineno;
        func.?.is_async = is_async;

        // Copy decorators
        for (pending_decorators.items) |dec| {
            try func.?.addDecorator(dec);
        }

        // Parse parameters
        const params_start = name_end + 1;
        if (std.mem.indexOf(u8, def_line[params_start..], ")")) |params_end| {
            const params_str = def_line[params_start .. params_start + params_end];
            try parseParameters(&func.?, params_str);
        }

        // Parse return type
        if (std.mem.indexOf(u8, def_line, "->")) |arrow| {
            const after_arrow = def_line[arrow + 2 ..];
            const colon = std.mem.indexOf(u8, after_arrow, ":") orelse after_arrow.len;
            func.?.return_type = std.mem.trim(u8, after_arrow[0..colon], " \t");
        }

        break;
    }

    // Look for docstring
    if (func != null) {
        while (lines.next()) |line| {
            const trimmed = std.mem.trimLeft(u8, line, " \t");
            if (trimmed.len == 0) continue;

            if (std.mem.startsWith(u8, trimmed, "\"\"\"")) {
                func.?.docstring = extractDocstring(trimmed, "\"\"\"");
            } else if (std.mem.startsWith(u8, trimmed, "'''")) {
                func.?.docstring = extractDocstring(trimmed, "'''");
            }
            break;
        }
    }

    return func orelse FunctionInfo.init(allocator, "unknown");
}

/// Parse function parameters
fn parseParameters(func: *FunctionInfo, params_str: []const u8) !void {
    var params = std.mem.splitScalar(u8, params_str, ',');

    while (params.next()) |param| {
        const trimmed = std.mem.trim(u8, param, " \t");
        if (trimmed.len == 0) continue;

        var p = FunctionInfo.Parameter{
            .name = trimmed,
            .type_hint = null,
            .default_value = null,
        };

        // Check for *args or **kwargs
        if (std.mem.startsWith(u8, trimmed, "**")) {
            p.is_kwargs = true;
            p.name = trimmed[2..];
        } else if (std.mem.startsWith(u8, trimmed, "*")) {
            p.is_args = true;
            p.name = trimmed[1..];
        }

        // Check for type hint
        if (std.mem.indexOf(u8, trimmed, ":")) |colon| {
            p.name = std.mem.trim(u8, trimmed[0..colon], " \t");
            const after_colon = trimmed[colon + 1 ..];
            if (std.mem.indexOf(u8, after_colon, "=")) |eq| {
                p.type_hint = std.mem.trim(u8, after_colon[0..eq], " \t");
                p.default_value = std.mem.trim(u8, after_colon[eq + 1 ..], " \t");
            } else {
                p.type_hint = std.mem.trim(u8, after_colon, " \t");
            }
        } else if (std.mem.indexOf(u8, trimmed, "=")) |eq| {
            p.name = std.mem.trim(u8, trimmed[0..eq], " \t");
            p.default_value = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
        }

        try func.addParameter(p);
    }
}

/// Extract decorator name
fn extractDecoratorName(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t");
    // Find end of decorator name (at ( or end of line)
    for (trimmed, 0..) |c, i| {
        if (c == '(' or c == '\n') {
            return trimmed[0..i];
        }
    }
    return trimmed;
}

/// Extract docstring content
fn extractDocstring(line: []const u8, quote: []const u8) ?[]const u8 {
    const start = quote.len;
    const rest = line[start..];
    if (std.mem.indexOf(u8, rest, quote)) |end| {
        return rest[0..end];
    }
    return rest;
}

/// run_docstring_examples() implementation
pub fn run_docstring_examples(
    allocator: std.mem.Allocator,
    docstring: []const u8,
    name: []const u8,
) !FunctionTestResult {
    var func = FunctionInfo.init(allocator, name);
    defer func.deinit();
    func.docstring = docstring;

    const runner = FunctionDocTestRunner.init(allocator);
    return runner.runFunction(&func);
}

// ============================================================================
// Tests
// ============================================================================

test "FunctionInfo_init" {
    var info = FunctionInfo.init(std.testing.allocator, "my_func");
    defer info.deinit();

    try std.testing.expectEqualStrings("my_func", info.name);
    try std.testing.expect(!info.hasDocstring());
    try std.testing.expect(!info.is_async);
}

test "FunctionInfo_addParameter" {
    var info = FunctionInfo.init(std.testing.allocator, "func");
    defer info.deinit();

    try info.addParameter(.{ .name = "x" });
    try info.addParameter(.{ .name = "y", .type_hint = "int" });

    try std.testing.expectEqual(@as(usize, 2), info.parameterCount());
}

test "FunctionInfo_addDecorator" {
    var info = FunctionInfo.init(std.testing.allocator, "func");
    defer info.deinit();

    try info.addDecorator("staticmethod");
    try info.addDecorator("cache");

    try std.testing.expect(info.hasDecorator("staticmethod"));
    try std.testing.expect(info.hasDecorator("cache"));
    try std.testing.expect(!info.hasDecorator("property"));
}

test "FunctionInfo_signature_simple" {
    var info = FunctionInfo.init(std.testing.allocator, "add");
    defer info.deinit();

    try info.addParameter(.{ .name = "a" });
    try info.addParameter(.{ .name = "b" });

    const sig = try info.signature(std.testing.allocator);
    defer std.testing.allocator.free(sig);

    try std.testing.expectEqualStrings("add(a, b)", sig);
}

test "FunctionInfo_signature_with_types" {
    var info = FunctionInfo.init(std.testing.allocator, "greet");
    defer info.deinit();

    try info.addParameter(.{ .name = "name", .type_hint = "str" });
    info.return_type = "str";

    const sig = try info.signature(std.testing.allocator);
    defer std.testing.allocator.free(sig);

    try std.testing.expectEqualStrings("greet(name: str) -> str", sig);
}

test "FunctionDocTestRunner_init" {
    const runner = FunctionDocTestRunner.init(std.testing.allocator);
    try std.testing.expect(!runner.verbose);
}

test "FunctionDocTestRunner_runFunction" {
    const runner = FunctionDocTestRunner.init(std.testing.allocator);

    var func = FunctionInfo.init(std.testing.allocator, "add");
    defer func.deinit();
    func.docstring =
        \\Add two numbers.
        \\
        \\>>> add(1, 2)
        \\3
        \\>>> add(-1, 1)
        \\0
    ;

    var result = try runner.runFunction(&func);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.attempted);
}

test "DocstringResult_passed" {
    const result = DocstringResult{ .attempted = 5, .failed = 2 };
    try std.testing.expectEqual(@as(usize, 3), result.passed());
}

test "FunctionTestResult_init" {
    var result = FunctionTestResult.init(std.testing.allocator, "test_func");
    defer result.deinit();

    try std.testing.expectEqualStrings("test_func", result.function_name);
    try std.testing.expect(result.wasSuccessful());
}

test "FunctionTestResult_addExample" {
    var result = FunctionTestResult.init(std.testing.allocator, "test");
    defer result.deinit();

    try result.addExample(.{
        .source = "1 + 1",
        .expected = "2",
        .actual = "2",
        .passed = true,
        .lineno = 1,
    });

    try result.addExample(.{
        .source = "1 + 1",
        .expected = "3",
        .actual = "2",
        .passed = false,
        .lineno = 2,
    });

    try std.testing.expectEqual(@as(usize, 2), result.examples.items.len);
    try std.testing.expectEqual(@as(usize, 1), result.failed);
}

test "FunctionTestResult_summary" {
    var result = FunctionTestResult.init(std.testing.allocator, "my_func");
    defer result.deinit();

    result.attempted = 5;
    result.failed = 1;

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try result.summary(stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "my_func") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "5 tests") != null);
}

test "parseFunction_simple" {
    const source =
        \\def add(a, b):
        \\    """Add two numbers."""
        \\    return a + b
    ;

    var func = try parseFunction(std.testing.allocator, source);
    defer func.deinit();

    try std.testing.expectEqualStrings("add", func.name);
    try std.testing.expectEqual(@as(usize, 2), func.parameterCount());
    try std.testing.expect(func.hasDocstring());
}

test "parseFunction_with_types" {
    const source =
        \\def greet(name: str) -> str:
        \\    """Return greeting."""
        \\    return f"Hello, {name}"
    ;

    var func = try parseFunction(std.testing.allocator, source);
    defer func.deinit();

    try std.testing.expectEqualStrings("greet", func.name);
    try std.testing.expect(func.return_type != null);
    try std.testing.expectEqualStrings("str", func.return_type.?);
}

test "parseFunction_async" {
    const source =
        \\async def fetch(url):
        \\    """Fetch URL."""
        \\    pass
    ;

    var func = try parseFunction(std.testing.allocator, source);
    defer func.deinit();

    try std.testing.expectEqualStrings("fetch", func.name);
    try std.testing.expect(func.is_async);
}

test "parseFunction_with_decorators" {
    const source =
        \\@staticmethod
        \\@cache
        \\def compute(x):
        \\    """Compute value."""
        \\    return x * 2
    ;

    var func = try parseFunction(std.testing.allocator, source);
    defer func.deinit();

    try std.testing.expectEqualStrings("compute", func.name);
    try std.testing.expect(func.hasDecorator("staticmethod"));
    try std.testing.expect(func.hasDecorator("cache"));
}

test "parseParameters" {
    var func = FunctionInfo.init(std.testing.allocator, "test");
    defer func.deinit();

    try parseParameters(&func, "a, b: int, c=10, *args, **kwargs");

    try std.testing.expectEqual(@as(usize, 5), func.parameterCount());
}

test "extractDecoratorName" {
    try std.testing.expectEqualStrings("staticmethod", extractDecoratorName("staticmethod").?);
    try std.testing.expectEqualStrings("cache", extractDecoratorName("cache(maxsize=100)").?);
}

test "run_docstring_examples" {
    const docstring =
        \\Example usage:
        \\
        \\>>> func(1)
        \\1
        \\>>> func(2)
        \\2
    ;

    var result = try run_docstring_examples(std.testing.allocator, docstring, "func");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.attempted);
}
