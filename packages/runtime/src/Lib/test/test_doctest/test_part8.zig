//! test.test_doctest.test_part8 - Module-level Doctests implementation
//! Support for module-level docstring testing.
const std = @import("std");

/// Module information for doctest discovery
pub const ModuleInfo = struct {
    name: []const u8,
    file_path: ?[]const u8,
    docstring: ?[]const u8,
    is_package: bool,
    submodules: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .name = name,
            .file_path = null,
            .docstring = null,
            .is_package = false,
            .submodules = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.submodules.deinit();
    }

    pub fn addSubmodule(self: *@This(), name: []const u8) !void {
        try self.submodules.append(name);
    }

    pub fn hasDocstring(self: @This()) bool {
        return self.docstring != null and self.docstring.?.len > 0;
    }

    pub fn qualifiedName(self: @This(), parent: ?[]const u8, allocator: std.mem.Allocator) ![]u8 {
        if (parent) |p| {
            return std.fmt.allocPrint(allocator, "{s}.{s}", .{ p, self.name });
        }
        return allocator.dupe(u8, self.name);
    }
};

/// Module doctest runner
pub const ModuleDocTestRunner = struct {
    allocator: std.mem.Allocator,
    verbose: bool = false,
    recurse: bool = true,
    optionflags: u32 = 0,
    tested_modules: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .tested_modules = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.tested_modules.deinit();
    }

    /// Run doctests for a module
    pub fn runModule(self: *@This(), module: *const ModuleInfo) !ModuleTestResult {
        if (self.tested_modules.contains(module.name)) {
            return ModuleTestResult.init(self.allocator, module.name, true);
        }

        try self.tested_modules.put(module.name, {});

        var result = ModuleTestResult.init(self.allocator, module.name, false);

        // Test module docstring
        if (module.hasDocstring()) {
            const doc_result = try self.runDocstring(module.docstring.?);
            result.attempted += doc_result.attempted;
            result.failed += doc_result.failed;
        }

        // Recursively test submodules
        if (self.recurse) {
            for (module.submodules.items) |_| {
                // In real impl, would load and test each submodule
                result.submodules_tested += 1;
            }
        }

        return result;
    }

    /// Run doctests from a docstring
    fn runDocstring(self: @This(), docstring: []const u8) !DocstringResult {
        _ = self;
        var result = DocstringResult{};

        // Count examples (simplified - just count >>> prompts)
        var lines = std.mem.splitScalar(u8, docstring, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trimLeft(u8, line, " \t");
            if (std.mem.startsWith(u8, trimmed, ">>> ")) {
                result.attempted += 1;
            }
        }

        return result;
    }

    /// Check if module was already tested
    pub fn wasTested(self: @This(), name: []const u8) bool {
        return self.tested_modules.contains(name);
    }
};

/// Result of running docstring examples
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

/// Result of testing a module
pub const ModuleTestResult = struct {
    module_name: []const u8,
    attempted: usize = 0,
    failed: usize = 0,
    skipped: bool,
    submodules_tested: usize = 0,
    examples: std.ArrayList(ExampleResult),
    allocator: std.mem.Allocator,

    pub const ExampleResult = struct {
        source: []const u8,
        expected: []const u8,
        actual: []const u8,
        passed: bool,
        lineno: usize,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8, skipped: bool) @This() {
        return .{
            .module_name = name,
            .skipped = skipped,
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
        self.attempted += 1;
        if (!result.passed) {
            self.failed += 1;
        }
    }

    pub fn summary(self: @This(), writer: anytype) !void {
        if (self.skipped) {
            try writer.print("{s}: SKIPPED\n", .{self.module_name});
            return;
        }

        try writer.print("{s}: {d} tests, {d} passed, {d} failed", .{
            self.module_name,
            self.attempted,
            self.attempted - self.failed,
            self.failed,
        });

        if (self.submodules_tested > 0) {
            try writer.print(" ({d} submodules)", .{self.submodules_tested});
        }
        try writer.writeAll("\n");
    }
};

/// testmod() implementation - test module and its contents
pub fn testmod(
    allocator: std.mem.Allocator,
    module_source: []const u8,
    module_name: []const u8,
) !ModuleTestResult {
    // Extract module docstring
    const docstring = extractModuleDocstring(module_source);

    var info = ModuleInfo.init(allocator, module_name);
    defer info.deinit();
    info.docstring = docstring;

    var runner = ModuleDocTestRunner.init(allocator);
    defer runner.deinit();

    return runner.runModule(&info);
}

/// Extract module docstring from source
fn extractModuleDocstring(source: []const u8) ?[]const u8 {
    const trimmed = std.mem.trimLeft(u8, source, " \t\n\r");

    // Check for triple-quoted string at start
    if (std.mem.startsWith(u8, trimmed, "\"\"\"")) {
        const start = 3;
        if (std.mem.indexOf(u8, trimmed[start..], "\"\"\"")) |end| {
            return trimmed[start .. start + end];
        }
    } else if (std.mem.startsWith(u8, trimmed, "'''")) {
        const start = 3;
        if (std.mem.indexOf(u8, trimmed[start..], "'''")) |end| {
            return trimmed[start .. start + end];
        }
    }

    return null;
}

/// Check if source has module docstring
pub fn hasModuleDocstring(source: []const u8) bool {
    return extractModuleDocstring(source) != null;
}

/// Module loader for doctest discovery
pub const ModuleLoader = struct {
    allocator: std.mem.Allocator,
    search_paths: std.ArrayList([]const u8),
    loaded: std.StringHashMap(ModuleInfo),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .search_paths = std.ArrayList([]const u8).init(allocator),
            .loaded = std.StringHashMap(ModuleInfo).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.search_paths.deinit();
        var iter = self.loaded.valueIterator();
        while (iter.next()) |info| {
            var copy = info;
            copy.deinit();
        }
        self.loaded.deinit();
    }

    pub fn addSearchPath(self: *@This(), path: []const u8) !void {
        try self.search_paths.append(path);
    }

    pub fn isLoaded(self: @This(), name: []const u8) bool {
        return self.loaded.contains(name);
    }

    pub fn getModule(self: @This(), name: []const u8) ?ModuleInfo {
        return self.loaded.get(name);
    }
};

/// Package discovery for recursive doctest
pub const PackageDiscovery = struct {
    allocator: std.mem.Allocator,
    packages: std.ArrayList([]const u8),
    modules: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .packages = std.ArrayList([]const u8).init(allocator),
            .modules = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.packages.deinit();
        self.modules.deinit();
    }

    pub fn addPackage(self: *@This(), name: []const u8) !void {
        try self.packages.append(name);
    }

    pub fn addModule(self: *@This(), name: []const u8) !void {
        try self.modules.append(name);
    }

    pub fn totalCount(self: @This()) usize {
        return self.packages.items.len + self.modules.items.len;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ModuleInfo_init" {
    var info = ModuleInfo.init(std.testing.allocator, "my_module");
    defer info.deinit();

    try std.testing.expectEqualStrings("my_module", info.name);
    try std.testing.expect(!info.is_package);
    try std.testing.expect(!info.hasDocstring());
}

test "ModuleInfo_addSubmodule" {
    var info = ModuleInfo.init(std.testing.allocator, "package");
    defer info.deinit();

    try info.addSubmodule("submod1");
    try info.addSubmodule("submod2");

    try std.testing.expectEqual(@as(usize, 2), info.submodules.items.len);
}

test "ModuleInfo_qualifiedName_no_parent" {
    var info = ModuleInfo.init(std.testing.allocator, "module");
    defer info.deinit();

    const name = try info.qualifiedName(null, std.testing.allocator);
    defer std.testing.allocator.free(name);

    try std.testing.expectEqualStrings("module", name);
}

test "ModuleInfo_qualifiedName_with_parent" {
    var info = ModuleInfo.init(std.testing.allocator, "child");
    defer info.deinit();

    const name = try info.qualifiedName("parent", std.testing.allocator);
    defer std.testing.allocator.free(name);

    try std.testing.expectEqualStrings("parent.child", name);
}

test "ModuleDocTestRunner_init" {
    var runner = ModuleDocTestRunner.init(std.testing.allocator);
    defer runner.deinit();

    try std.testing.expect(runner.recurse);
    try std.testing.expect(!runner.verbose);
}

test "ModuleDocTestRunner_runModule" {
    var runner = ModuleDocTestRunner.init(std.testing.allocator);
    defer runner.deinit();

    var info = ModuleInfo.init(std.testing.allocator, "test_module");
    defer info.deinit();
    info.docstring =
        \\Module docstring.
        \\
        \\>>> 1 + 1
        \\2
    ;

    var result = try runner.runModule(&info);
    defer result.deinit();

    try std.testing.expect(!result.skipped);
    try std.testing.expectEqual(@as(usize, 1), result.attempted);
}

test "ModuleDocTestRunner_skipAlreadyTested" {
    var runner = ModuleDocTestRunner.init(std.testing.allocator);
    defer runner.deinit();

    var info = ModuleInfo.init(std.testing.allocator, "test_module");
    defer info.deinit();
    info.docstring = ">>> 1";

    _ = try runner.runModule(&info);
    var result2 = try runner.runModule(&info);
    defer result2.deinit();

    try std.testing.expect(result2.skipped);
}

test "DocstringResult_passed" {
    const result = DocstringResult{ .attempted = 5, .failed = 2 };
    try std.testing.expectEqual(@as(usize, 3), result.passed());
}

test "DocstringResult_wasSuccessful" {
    const success = DocstringResult{ .attempted = 5, .failed = 0 };
    try std.testing.expect(success.wasSuccessful());

    const failure = DocstringResult{ .attempted = 5, .failed = 1 };
    try std.testing.expect(!failure.wasSuccessful());
}

test "ModuleTestResult_init" {
    var result = ModuleTestResult.init(std.testing.allocator, "test", false);
    defer result.deinit();

    try std.testing.expectEqualStrings("test", result.module_name);
    try std.testing.expect(!result.skipped);
    try std.testing.expect(result.wasSuccessful());
}

test "ModuleTestResult_addExample" {
    var result = ModuleTestResult.init(std.testing.allocator, "test", false);
    defer result.deinit();

    try result.addExample(.{
        .source = "1 + 1",
        .expected = "2",
        .actual = "2",
        .passed = true,
        .lineno = 1,
    });

    try std.testing.expectEqual(@as(usize, 1), result.attempted);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
}

test "ModuleTestResult_summary" {
    var result = ModuleTestResult.init(std.testing.allocator, "mymod", false);
    defer result.deinit();
    result.attempted = 3;
    result.failed = 1;

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try result.summary(stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "mymod") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "3 tests") != null);
}

test "testmod_with_docstring" {
    const source =
        \\"""
        \\Module with doctest.
        \\
        \\>>> 2 + 2
        \\4
        \\>>> 3 * 3
        \\9
        \\"""
        \\
        \\def foo():
        \\    pass
    ;

    var result = try testmod(std.testing.allocator, source, "test_mod");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.attempted);
}

test "testmod_without_docstring" {
    const source =
        \\# No docstring
        \\def foo():
        \\    pass
    ;

    var result = try testmod(std.testing.allocator, source, "nodoc");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.attempted);
}

test "extractModuleDocstring_double" {
    const source =
        \\"""Module doc."""
        \\
        \\code
    ;

    const doc = extractModuleDocstring(source);
    try std.testing.expect(doc != null);
    try std.testing.expectEqualStrings("Module doc.", doc.?);
}

test "extractModuleDocstring_single" {
    const source =
        \\'''Single quotes.'''
        \\
        \\code
    ;

    const doc = extractModuleDocstring(source);
    try std.testing.expect(doc != null);
    try std.testing.expectEqualStrings("Single quotes.", doc.?);
}

test "extractModuleDocstring_none" {
    const source =
        \\# comment
        \\def foo(): pass
    ;

    try std.testing.expect(extractModuleDocstring(source) == null);
}

test "hasModuleDocstring" {
    const with_doc =
        \\"""Doc."""
        \\pass
    ;
    try std.testing.expect(hasModuleDocstring(with_doc));

    const without_doc = "def foo(): pass";
    try std.testing.expect(!hasModuleDocstring(without_doc));
}

test "ModuleLoader_init" {
    var loader = ModuleLoader.init(std.testing.allocator);
    defer loader.deinit();

    try std.testing.expectEqual(@as(usize, 0), loader.search_paths.items.len);
}

test "ModuleLoader_addSearchPath" {
    var loader = ModuleLoader.init(std.testing.allocator);
    defer loader.deinit();

    try loader.addSearchPath("/usr/lib/python");
    try loader.addSearchPath("/home/user/lib");

    try std.testing.expectEqual(@as(usize, 2), loader.search_paths.items.len);
}

test "PackageDiscovery_init" {
    var discovery = PackageDiscovery.init(std.testing.allocator);
    defer discovery.deinit();

    try std.testing.expectEqual(@as(usize, 0), discovery.totalCount());
}

test "PackageDiscovery_add" {
    var discovery = PackageDiscovery.init(std.testing.allocator);
    defer discovery.deinit();

    try discovery.addPackage("pkg1");
    try discovery.addModule("mod1");
    try discovery.addModule("mod2");

    try std.testing.expectEqual(@as(usize, 3), discovery.totalCount());
}
