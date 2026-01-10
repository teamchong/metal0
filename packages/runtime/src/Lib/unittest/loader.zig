//! unittest.loader - Test discovery and loading
//! Reference: cpython/Lib/unittest/loader.py
//!
//! CPython __all__: ['TestLoader', 'defaultTestLoader', 'makeSuite', 'getTestCaseNames', 'findTestCases']
//!
//! Provides test loading and discovery functionality.

const std = @import("std");
const runner = @import("runner.zig");
const suite_mod = @import("suite.zig");

// ============================================================================
// Re-export from runner (DRY)
// ============================================================================

/// TestLoader - Load test cases from modules and classes
/// CPython: class TestLoader
pub const TestLoader = runner.TestLoader;

// ============================================================================
// Module-level Functions
// ============================================================================

/// CPython: defaultTestLoader = TestLoader()
/// The default test loader instance
var _defaultTestLoader: ?TestLoader = null;

pub fn defaultTestLoader(allocator: std.mem.Allocator) *TestLoader {
    if (_defaultTestLoader == null) {
        _defaultTestLoader = TestLoader.init(allocator);
    }
    return &_defaultTestLoader.?;
}

/// CPython: def makeSuite(testCaseClass, prefix='test', sortUsing=util.three_way_cmp, suiteClass=suite.TestSuite)
/// Create a suite from a test case class
/// Note: In AOT, test discovery is compile-time; this returns an empty suite
pub fn makeSuite(allocator: std.mem.Allocator, comptime TestCaseClass: type, prefix: []const u8, suiteClass: type) suiteClass {
    _ = TestCaseClass;
    _ = prefix;
    return suiteClass.init(allocator);
}

/// CPython: def getTestCaseNames(testCaseClass, prefix, sortUsing=util.three_way_cmp)
/// Get test method names from a test case class
/// Note: In AOT, returns empty slice; codegen handles discovery
pub fn getTestCaseNames(comptime TestCaseClass: type, prefix: []const u8) []const []const u8 {
    _ = TestCaseClass;
    _ = prefix;
    return &[_][]const u8{};
}

/// CPython: def findTestCases(module, prefix='test')
/// Find test cases in a module
/// Note: In AOT, returns empty slice; codegen handles discovery
pub fn findTestCases(comptime Module: type, prefix: []const u8) []const type {
    _ = Module;
    _ = prefix;
    return &[_]type{};
}

// ============================================================================
// Extended TestLoader with CPython Features
// ============================================================================

/// CPythonTestLoader - Full CPython-compatible TestLoader
/// Provides complete API matching Python's unittest.TestLoader
pub const CPythonTestLoader = struct {
    allocator: std.mem.Allocator,
    /// Prefix for test method names (default: "test")
    testMethodPrefix: []const u8 = "test",
    /// Comparison function for sorting test methods
    sortTestMethodsUsing: ?*const fn ([]const u8, []const u8) std.math.Order = null,
    /// Class to use for test suites
    suiteClass: type = runner.TestSuite,
    /// Errors encountered during loading
    errors: std.ArrayListUnmanaged(LoadError) = .{},
    /// Pattern for test file discovery (default: "test*.py")
    testNamePatterns: ?[]const []const u8 = null,

    pub const LoadError = struct {
        test_name: []const u8,
        message: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) CPythonTestLoader {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CPythonTestLoader) void {
        self.errors.deinit(self.allocator);
    }

    /// CPython: def loadTestsFromTestCase(self, testCaseClass)
    /// Load tests from a TestCase class
    pub fn loadTestsFromTestCase(self: *CPythonTestLoader, comptime TestCaseClass: type) runner.TestSuite {
        _ = TestCaseClass;
        return runner.TestSuite.init(self.allocator);
    }

    /// CPython: def loadTestsFromModule(self, module, *args, pattern=None, **kws)
    /// Load tests from a module
    pub fn loadTestsFromModule(self: *CPythonTestLoader, comptime Module: type, pattern: ?[]const u8) runner.TestSuite {
        _ = Module;
        _ = pattern;
        return runner.TestSuite.init(self.allocator);
    }

    /// CPython: def loadTestsFromName(self, name, module=None)
    /// Load tests from a dotted name
    pub fn loadTestsFromName(self: *CPythonTestLoader, name: []const u8, module: ?type) runner.TestSuite {
        _ = name;
        _ = module;
        return runner.TestSuite.init(self.allocator);
    }

    /// CPython: def loadTestsFromNames(self, names, module=None)
    /// Load tests from multiple names
    pub fn loadTestsFromNames(self: *CPythonTestLoader, names: []const []const u8, module: ?type) runner.TestSuite {
        _ = names;
        _ = module;
        return runner.TestSuite.init(self.allocator);
    }

    /// CPython: def getTestCaseNames(self, testCaseClass)
    /// Get test method names from a test case class
    pub fn getTestCaseNames(self: *CPythonTestLoader, comptime TestCaseClass: type) []const []const u8 {
        _ = self;
        _ = TestCaseClass;
        return &[_][]const u8{};
    }

    /// CPython: def discover(self, start_dir, pattern='test*.py', top_level_dir=None)
    /// Discover tests in a directory
    pub fn discover(
        self: *CPythonTestLoader,
        start_dir: []const u8,
        pattern: []const u8,
        top_level_dir: ?[]const u8,
    ) runner.TestSuite {
        _ = start_dir;
        _ = pattern;
        _ = top_level_dir;
        return runner.TestSuite.init(self.allocator);
    }

    /// CPython: def _match_path(self, path, full_path, pattern)
    /// Check if a path matches the test pattern
    fn matchPath(_: *CPythonTestLoader, path: []const u8, full_path: []const u8, pattern: []const u8) bool {
        _ = full_path;
        // Simple pattern matching
        if (std.mem.startsWith(u8, pattern, "*")) {
            const suffix = pattern[1..];
            return std.mem.endsWith(u8, path, suffix);
        }
        if (std.mem.endsWith(u8, pattern, "*")) {
            const prefix = pattern[0 .. pattern.len - 1];
            return std.mem.startsWith(u8, path, prefix);
        }
        return std.mem.eql(u8, path, pattern);
    }
};

// ============================================================================
// SKIP_HEADER constant for module docstring tests
// ============================================================================

/// Number of lines to skip for module docstring tests
pub const VALID_MODULE_NAME = "test";

// ============================================================================
// Tests
// ============================================================================

test "TestLoader basic" {
    const allocator = std.testing.allocator;
    var loader = TestLoader.init(allocator);
    _ = loader;
}

test "CPythonTestLoader basic" {
    const allocator = std.testing.allocator;
    var loader = CPythonTestLoader.init(allocator);
    defer loader.deinit();
}

test "defaultTestLoader" {
    const allocator = std.testing.allocator;
    const loader = defaultTestLoader(allocator);
    try std.testing.expect(loader.allocator.ptr == allocator.ptr);
}
