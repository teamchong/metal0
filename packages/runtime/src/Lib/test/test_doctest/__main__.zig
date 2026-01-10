//! test.test_doctest - Doctest functionality tests
const std = @import("std");

pub const DocTestResult = struct {
    attempted: usize = 0,
    failed: usize = 0,
    
    pub fn wasSuccessful(self: @This()) bool {
        return self.failed == 0;
    }
};

pub const Example = struct {
    source: []const u8,
    want: []const u8,
    lineno: usize = 0,
    indent: usize = 0,
    options: Options = .{},
    
    pub const Options = struct {
        normalize_whitespace: bool = false,
        ellipsis: bool = false,
        skip: bool = false,
    };
};

pub const DocTest = struct {
    name: []const u8,
    examples: std.ArrayList(Example),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .allocator = allocator,
            .name = name,
            .examples = std.ArrayList(Example).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.examples.deinit();
    }
};

pub const DocTestRunner = struct {
    verbose: bool = false,
    optionflags: u32 = 0,
    
    pub fn run(self: @This(), test_: *DocTest) DocTestResult {
        _ = self;
        return .{
            .attempted = test_.examples.items.len,
            .failed = 0,
        };
    }
};

pub const DocTestFinder = struct {
    verbose: bool = false,
    recurse: bool = true,
    
    pub fn find(self: @This(), allocator: std.mem.Allocator, module: []const u8) std.ArrayList(DocTest) {
        _ = self; _ = module;
        return std.ArrayList(DocTest).init(allocator);
    }
};

pub fn testmod(allocator: std.mem.Allocator, module: []const u8) DocTestResult {
    _ = allocator; _ = module;
    return .{};
}

pub fn run_docstring_examples(source: []const u8, allocator: std.mem.Allocator) DocTestResult {
    _ = source; _ = allocator;
    return .{};
}

test "doctest_result" {
    const r = DocTestResult{ .attempted = 5, .failed = 0 };
    try std.testing.expect(r.wasSuccessful());
}

test "doctest_result_failed" {
    const r = DocTestResult{ .attempted = 5, .failed = 2 };
    try std.testing.expect(!r.wasSuccessful());
}

test "example_init" {
    const ex = Example{ .source = "1 + 1", .want = "2" };
    try std.testing.expectEqualStrings("1 + 1", ex.source);
}

test "doctest_init" {
    var dt = DocTest.init(std.testing.allocator, "my_doctest");
    defer dt.deinit();
    try std.testing.expectEqualStrings("my_doctest", dt.name);
}
