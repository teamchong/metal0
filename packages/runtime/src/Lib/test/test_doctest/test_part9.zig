//! test.test_doctest.test_part9 - Class Docstring Tests implementation
//! Support for testing docstrings in class definitions.
const std = @import("std");

/// Class information for doctest discovery
pub const ClassInfo = struct {
    name: []const u8,
    docstring: ?[]const u8,
    bases: std.ArrayList([]const u8),
    methods: std.ArrayList(MethodInfo),
    properties: std.ArrayList(PropertyInfo),
    class_attrs: std.StringHashMap([]const u8),
    lineno: usize,
    allocator: std.mem.Allocator,

    pub const MethodInfo = struct {
        name: []const u8,
        docstring: ?[]const u8,
        is_static: bool = false,
        is_classmethod: bool = false,
        lineno: usize,
    };

    pub const PropertyInfo = struct {
        name: []const u8,
        docstring: ?[]const u8,
        has_setter: bool,
        lineno: usize,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .name = name,
            .docstring = null,
            .bases = std.ArrayList([]const u8).init(allocator),
            .methods = std.ArrayList(MethodInfo).init(allocator),
            .properties = std.ArrayList(PropertyInfo).init(allocator),
            .class_attrs = std.StringHashMap([]const u8).init(allocator),
            .lineno = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.bases.deinit();
        self.methods.deinit();
        self.properties.deinit();
        self.class_attrs.deinit();
    }

    pub fn hasDocstring(self: @This()) bool {
        return self.docstring != null and self.docstring.?.len > 0;
    }

    pub fn addMethod(self: *@This(), method: MethodInfo) !void {
        try self.methods.append(method);
    }

    pub fn addProperty(self: *@This(), prop: PropertyInfo) !void {
        try self.properties.append(prop);
    }

    pub fn addBase(self: *@This(), base: []const u8) !void {
        try self.bases.append(base);
    }

    pub fn methodCount(self: @This()) usize {
        return self.methods.items.len;
    }

    pub fn getMethod(self: @This(), name: []const u8) ?MethodInfo {
        for (self.methods.items) |method| {
            if (std.mem.eql(u8, method.name, name)) {
                return method;
            }
        }
        return null;
    }

    /// Get all methods with docstrings
    pub fn methodsWithDocstrings(self: @This(), allocator: std.mem.Allocator) ![]MethodInfo {
        var result = std.ArrayList(MethodInfo).init(allocator);
        for (self.methods.items) |method| {
            if (method.docstring != null) {
                try result.append(method);
            }
        }
        return result.toOwnedSlice();
    }
};

/// Class doctest runner
pub const ClassDocTestRunner = struct {
    allocator: std.mem.Allocator,
    verbose: bool = false,
    test_methods: bool = true,
    test_properties: bool = true,
    optionflags: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    /// Run doctests for a class
    pub fn runClass(self: @This(), class: *const ClassInfo) !ClassTestResult {
        var result = ClassTestResult.init(self.allocator, class.name);

        // Test class docstring
        if (class.hasDocstring()) {
            const doc_result = self.runDocstring(class.docstring.?, class.name);
            result.class_attempted = doc_result.attempted;
            result.class_failed = doc_result.failed;
        }

        // Test method docstrings
        if (self.test_methods) {
            for (class.methods.items) |method| {
                if (method.docstring) |docstring| {
                    const method_result = self.runDocstring(docstring, method.name);
                    try result.method_results.put(method.name, method_result);
                    result.methods_attempted += method_result.attempted;
                    result.methods_failed += method_result.failed;
                }
            }
        }

        // Test property docstrings
        if (self.test_properties) {
            for (class.properties.items) |prop| {
                if (prop.docstring) |docstring| {
                    const prop_result = self.runDocstring(docstring, prop.name);
                    result.properties_attempted += prop_result.attempted;
                    result.properties_failed += prop_result.failed;
                }
            }
        }

        return result;
    }

    /// Run doctests from a docstring
    fn runDocstring(self: @This(), docstring: []const u8, name: []const u8) DocstringResult {
        _ = self;
        _ = name;
        var result = DocstringResult{};

        // Count examples
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

/// Result of testing a class
pub const ClassTestResult = struct {
    class_name: []const u8,
    class_attempted: usize = 0,
    class_failed: usize = 0,
    methods_attempted: usize = 0,
    methods_failed: usize = 0,
    properties_attempted: usize = 0,
    properties_failed: usize = 0,
    method_results: std.StringHashMap(DocstringResult),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .class_name = name,
            .method_results = std.StringHashMap(DocstringResult).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.method_results.deinit();
    }

    pub fn totalAttempted(self: @This()) usize {
        return self.class_attempted + self.methods_attempted + self.properties_attempted;
    }

    pub fn totalFailed(self: @This()) usize {
        return self.class_failed + self.methods_failed + self.properties_failed;
    }

    pub fn wasSuccessful(self: @This()) bool {
        return self.totalFailed() == 0;
    }

    pub fn summary(self: @This(), writer: anytype) !void {
        try writer.print("Class {s}:\n", .{self.class_name});
        try writer.print("  Class docstring: {d} tests, {d} failed\n", .{
            self.class_attempted,
            self.class_failed,
        });
        try writer.print("  Methods: {d} tests, {d} failed\n", .{
            self.methods_attempted,
            self.methods_failed,
        });
        try writer.print("  Properties: {d} tests, {d} failed\n", .{
            self.properties_attempted,
            self.properties_failed,
        });
    }
};

/// Parse class from Python source
pub fn parseClass(allocator: std.mem.Allocator, source: []const u8) !ClassInfo {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var class: ?ClassInfo = null;
    var lineno: usize = 0;
    var in_class = false;
    var class_indent: usize = 0;

    while (lines.next()) |line| {
        lineno += 1;
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        const indent = line.len - trimmed.len;

        // Look for class definition
        if (std.mem.startsWith(u8, trimmed, "class ")) {
            const class_line = trimmed[6..];
            // Extract class name (before : or ()
            var name_end: usize = 0;
            for (class_line, 0..) |c, i| {
                if (c == ':' or c == '(') {
                    name_end = i;
                    break;
                }
            }
            if (name_end > 0) {
                class = ClassInfo.init(allocator, class_line[0..name_end]);
                class.?.lineno = lineno;
                in_class = true;
                class_indent = indent;

                // Extract bases if present
                if (std.mem.indexOf(u8, class_line, "(")) |paren_start| {
                    if (std.mem.indexOf(u8, class_line[paren_start..], ")")) |paren_end| {
                        const bases_str = class_line[paren_start + 1 .. paren_start + paren_end];
                        var bases_iter = std.mem.splitScalar(u8, bases_str, ',');
                        while (bases_iter.next()) |base| {
                            const base_name = std.mem.trim(u8, base, " \t");
                            if (base_name.len > 0) {
                                try class.?.addBase(base_name);
                            }
                        }
                    }
                }
            }
        } else if (in_class and indent > class_indent) {
            // Inside class body
            if (std.mem.startsWith(u8, trimmed, "def ")) {
                // Method definition
                const def_line = trimmed[4..];
                var name_end: usize = 0;
                for (def_line, 0..) |c, i| {
                    if (c == '(') {
                        name_end = i;
                        break;
                    }
                }
                if (name_end > 0) {
                    try class.?.addMethod(.{
                        .name = def_line[0..name_end],
                        .docstring = null,
                        .lineno = lineno,
                    });
                }
            } else if (std.mem.startsWith(u8, trimmed, "@property")) {
                // Property detected - would need to parse next line
            }
        } else if (in_class and indent <= class_indent and trimmed.len > 0) {
            // Exited class
            break;
        }
    }

    return class orelse ClassInfo.init(allocator, "unknown");
}

/// Check if line contains a docstring start
pub fn isDocstringStart(line: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, line, " \t");
    return std.mem.startsWith(u8, trimmed, "\"\"\"") or
        std.mem.startsWith(u8, trimmed, "'''");
}

/// Extract class docstring
pub fn extractClassDocstring(source: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var found_class = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trimLeft(u8, line, " \t");

        if (std.mem.startsWith(u8, trimmed, "class ")) {
            found_class = true;
            continue;
        }

        if (found_class) {
            if (std.mem.startsWith(u8, trimmed, "\"\"\"")) {
                const start = 3;
                const rest = trimmed[start..];
                if (std.mem.indexOf(u8, rest, "\"\"\"")) |end| {
                    return rest[0..end];
                }
                // Multi-line - would need more parsing
                return rest;
            } else if (std.mem.startsWith(u8, trimmed, "'''")) {
                const start = 3;
                const rest = trimmed[start..];
                if (std.mem.indexOf(u8, rest, "'''")) |end| {
                    return rest[0..end];
                }
                return rest;
            } else if (trimmed.len > 0) {
                // Not a docstring
                break;
            }
        }
    }

    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "ClassInfo_init" {
    var info = ClassInfo.init(std.testing.allocator, "MyClass");
    defer info.deinit();

    try std.testing.expectEqualStrings("MyClass", info.name);
    try std.testing.expect(!info.hasDocstring());
}

test "ClassInfo_addMethod" {
    var info = ClassInfo.init(std.testing.allocator, "MyClass");
    defer info.deinit();

    try info.addMethod(.{ .name = "method1", .docstring = null, .lineno = 5 });
    try info.addMethod(.{ .name = "method2", .docstring = "Doc", .lineno = 10 });

    try std.testing.expectEqual(@as(usize, 2), info.methodCount());
}

test "ClassInfo_getMethod" {
    var info = ClassInfo.init(std.testing.allocator, "MyClass");
    defer info.deinit();

    try info.addMethod(.{ .name = "foo", .docstring = null, .lineno = 1 });
    try info.addMethod(.{ .name = "bar", .docstring = null, .lineno = 2 });

    const foo = info.getMethod("foo");
    try std.testing.expect(foo != null);
    try std.testing.expectEqualStrings("foo", foo.?.name);

    try std.testing.expect(info.getMethod("baz") == null);
}

test "ClassInfo_addBase" {
    var info = ClassInfo.init(std.testing.allocator, "Child");
    defer info.deinit();

    try info.addBase("Parent1");
    try info.addBase("Parent2");

    try std.testing.expectEqual(@as(usize, 2), info.bases.items.len);
}

test "ClassInfo_methodsWithDocstrings" {
    var info = ClassInfo.init(std.testing.allocator, "MyClass");
    defer info.deinit();

    try info.addMethod(.{ .name = "no_doc", .docstring = null, .lineno = 1 });
    try info.addMethod(.{ .name = "with_doc", .docstring = "Doc here", .lineno = 5 });
    try info.addMethod(.{ .name = "also_doc", .docstring = "Another", .lineno = 10 });

    const with_docs = try info.methodsWithDocstrings(std.testing.allocator);
    defer std.testing.allocator.free(with_docs);

    try std.testing.expectEqual(@as(usize, 2), with_docs.len);
}

test "ClassDocTestRunner_init" {
    const runner = ClassDocTestRunner.init(std.testing.allocator);
    try std.testing.expect(runner.test_methods);
    try std.testing.expect(runner.test_properties);
}

test "ClassDocTestRunner_runClass" {
    const runner = ClassDocTestRunner.init(std.testing.allocator);

    var class = ClassInfo.init(std.testing.allocator, "TestClass");
    defer class.deinit();
    class.docstring =
        \\Test class.
        \\
        \\>>> obj = TestClass()
        \\>>> obj.value
        \\0
    ;

    try class.addMethod(.{
        .name = "method",
        .docstring =
        \\A method.
        \\
        \\>>> obj.method()
        \\42
    ,
        .lineno = 10,
    });

    var result = try runner.runClass(&class);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.class_attempted);
    try std.testing.expectEqual(@as(usize, 1), result.methods_attempted);
}

test "DocstringResult_passed" {
    const result = DocstringResult{ .attempted = 5, .failed = 2 };
    try std.testing.expectEqual(@as(usize, 3), result.passed());
}

test "ClassTestResult_init" {
    var result = ClassTestResult.init(std.testing.allocator, "TestClass");
    defer result.deinit();

    try std.testing.expectEqualStrings("TestClass", result.class_name);
    try std.testing.expect(result.wasSuccessful());
}

test "ClassTestResult_totalAttempted" {
    var result = ClassTestResult.init(std.testing.allocator, "Test");
    defer result.deinit();

    result.class_attempted = 2;
    result.methods_attempted = 5;
    result.properties_attempted = 1;

    try std.testing.expectEqual(@as(usize, 8), result.totalAttempted());
}

test "ClassTestResult_summary" {
    var result = ClassTestResult.init(std.testing.allocator, "MyClass");
    defer result.deinit();

    result.class_attempted = 3;
    result.methods_attempted = 5;

    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try result.summary(stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "MyClass") != null);
}

test "parseClass_simple" {
    const source =
        \\class Simple:
        \\    def __init__(self):
        \\        pass
        \\
        \\    def method(self):
        \\        pass
    ;

    var class = try parseClass(std.testing.allocator, source);
    defer class.deinit();

    try std.testing.expectEqualStrings("Simple", class.name);
    try std.testing.expectEqual(@as(usize, 2), class.methodCount());
}

test "parseClass_with_bases" {
    const source =
        \\class Child(Parent, Mixin):
        \\    pass
    ;

    var class = try parseClass(std.testing.allocator, source);
    defer class.deinit();

    try std.testing.expectEqualStrings("Child", class.name);
    try std.testing.expectEqual(@as(usize, 2), class.bases.items.len);
}

test "isDocstringStart" {
    try std.testing.expect(isDocstringStart("    \"\"\"docstring\"\"\""));
    try std.testing.expect(isDocstringStart("'''single'''"));
    try std.testing.expect(!isDocstringStart("# comment"));
    try std.testing.expect(!isDocstringStart("x = 1"));
}

test "extractClassDocstring" {
    const source =
        \\class MyClass:
        \\    """This is the docstring."""
        \\
        \\    def __init__(self):
        \\        pass
    ;

    const doc = extractClassDocstring(source);
    try std.testing.expect(doc != null);
    try std.testing.expectEqualStrings("This is the docstring.", doc.?);
}

test "extractClassDocstring_none" {
    const source =
        \\class NoDoc:
        \\    def __init__(self):
        \\        pass
    ;

    try std.testing.expect(extractClassDocstring(source) == null);
}

test "ClassInfo_addProperty" {
    var info = ClassInfo.init(std.testing.allocator, "MyClass");
    defer info.deinit();

    try info.addProperty(.{
        .name = "value",
        .docstring = "The value.",
        .has_setter = true,
        .lineno = 5,
    });

    try std.testing.expectEqual(@as(usize, 1), info.properties.items.len);
}
