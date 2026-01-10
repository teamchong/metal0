//! test.test_doctest.test_part3 - DocTestFinder implementation
//! Find and extract doctests from modules, classes, and functions.
const std = @import("std");

/// Types of objects that can contain doctests
pub const ObjectKind = enum {
    module,
    class,
    function,
    method,
    property,
    staticmethod,
    classmethod,
};

/// Represents a doctest-containing object found during discovery
pub const FoundObject = struct {
    name: []const u8,
    kind: ObjectKind,
    docstring: ?[]const u8,
    lineno: usize,
    parent: ?[]const u8,

    pub fn qualifiedName(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        if (self.parent) |p| {
            return std.fmt.allocPrint(allocator, "{s}.{s}", .{ p, self.name });
        }
        return allocator.dupe(u8, self.name);
    }

    pub fn hasDocstring(self: @This()) bool {
        return self.docstring != null and self.docstring.?.len > 0;
    }
};

/// Filter function type for object discovery
pub const ObjectFilter = *const fn (obj: FoundObject) bool;

/// DocTestFinder - discovers doctests in Python modules
pub const DocTestFinder = struct {
    allocator: std.mem.Allocator,
    verbose: bool = false,
    recurse: bool = true,
    exclude_empty: bool = true,
    objects: std.ArrayList(FoundObject),
    visited: std.StringHashMap(void),
    filter: ?ObjectFilter = null,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .objects = std.ArrayList(FoundObject).init(allocator),
            .visited = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.objects.deinit();
        self.visited.deinit();
    }

    /// Find all doctest-containing objects in a module source
    pub fn find(self: *@This(), module_name: []const u8, source: []const u8) !void {
        // Mark module as visited
        try self.visited.put(module_name, {});

        // Find module-level docstring
        if (findModuleDocstring(source)) |docstring| {
            try self.addObject(.{
                .name = module_name,
                .kind = .module,
                .docstring = docstring,
                .lineno = 1,
                .parent = null,
            });
        }

        // Find classes and functions
        try self.findDefinitions(source, module_name);
    }

    /// Find class and function definitions in source
    fn findDefinitions(self: *@This(), source: []const u8, module_name: []const u8) !void {
        var lines = std.mem.splitScalar(u8, source, '\n');
        var lineno: usize = 0;
        var current_class: ?[]const u8 = null;

        while (lines.next()) |line| {
            lineno += 1;
            const trimmed = std.mem.trimLeft(u8, line, " \t");
            const indent = line.len - trimmed.len;

            // Reset class context when dedenting to top level
            if (indent == 0 and current_class != null) {
                current_class = null;
            }

            if (std.mem.startsWith(u8, trimmed, "class ")) {
                const name = extractDefinitionName(trimmed[6..]);
                if (name) |n| {
                    current_class = n;
                    // Look for class docstring on following lines
                    const docstring = findFollowingDocstring(lines.rest());
                    try self.addObject(.{
                        .name = n,
                        .kind = .class,
                        .docstring = docstring,
                        .lineno = lineno,
                        .parent = module_name,
                    });
                }
            } else if (std.mem.startsWith(u8, trimmed, "def ")) {
                const name = extractDefinitionName(trimmed[4..]);
                if (name) |n| {
                    const docstring = findFollowingDocstring(lines.rest());
                    const kind: ObjectKind = if (current_class != null) .method else .function;
                    const parent = current_class orelse module_name;

                    try self.addObject(.{
                        .name = n,
                        .kind = kind,
                        .docstring = docstring,
                        .lineno = lineno,
                        .parent = parent,
                    });
                }
            } else if (std.mem.startsWith(u8, trimmed, "@staticmethod")) {
                // Next def is a static method
                if (lines.next()) |next_line| {
                    lineno += 1;
                    const next_trimmed = std.mem.trimLeft(u8, next_line, " \t");
                    if (std.mem.startsWith(u8, next_trimmed, "def ")) {
                        if (extractDefinitionName(next_trimmed[4..])) |n| {
                            const docstring = findFollowingDocstring(lines.rest());
                            try self.addObject(.{
                                .name = n,
                                .kind = .staticmethod,
                                .docstring = docstring,
                                .lineno = lineno,
                                .parent = current_class,
                            });
                        }
                    }
                }
            } else if (std.mem.startsWith(u8, trimmed, "@classmethod")) {
                // Next def is a class method
                if (lines.next()) |next_line| {
                    lineno += 1;
                    const next_trimmed = std.mem.trimLeft(u8, next_line, " \t");
                    if (std.mem.startsWith(u8, next_trimmed, "def ")) {
                        if (extractDefinitionName(next_trimmed[4..])) |n| {
                            const docstring = findFollowingDocstring(lines.rest());
                            try self.addObject(.{
                                .name = n,
                                .kind = .classmethod,
                                .docstring = docstring,
                                .lineno = lineno,
                                .parent = current_class,
                            });
                        }
                    }
                }
            } else if (std.mem.startsWith(u8, trimmed, "@property")) {
                // Next def is a property
                if (lines.next()) |next_line| {
                    lineno += 1;
                    const next_trimmed = std.mem.trimLeft(u8, next_line, " \t");
                    if (std.mem.startsWith(u8, next_trimmed, "def ")) {
                        if (extractDefinitionName(next_trimmed[4..])) |n| {
                            const docstring = findFollowingDocstring(lines.rest());
                            try self.addObject(.{
                                .name = n,
                                .kind = .property,
                                .docstring = docstring,
                                .lineno = lineno,
                                .parent = current_class,
                            });
                        }
                    }
                }
            }
        }
    }

    /// Add an object if it passes filters
    fn addObject(self: *@This(), obj: FoundObject) !void {
        // Apply filter if set
        if (self.filter) |f| {
            if (!f(obj)) return;
        }

        // Skip empty docstrings if configured
        if (self.exclude_empty and !obj.hasDocstring()) {
            return;
        }

        try self.objects.append(obj);

        if (self.verbose) {
            std.debug.print("Found {s}: {s}\n", .{ @tagName(obj.kind), obj.name });
        }
    }

    /// Check if an object has been visited
    pub fn isVisited(self: @This(), name: []const u8) bool {
        return self.visited.contains(name);
    }

    /// Get count of found objects
    pub fn objectCount(self: @This()) usize {
        return self.objects.items.len;
    }

    /// Get objects of a specific kind
    pub fn objectsOfKind(self: @This(), kind: ObjectKind, allocator: std.mem.Allocator) ![]FoundObject {
        var result = std.ArrayList(FoundObject).init(allocator);
        for (self.objects.items) |obj| {
            if (obj.kind == kind) {
                try result.append(obj);
            }
        }
        return result.toOwnedSlice();
    }
};

/// Find module-level docstring (first string literal in module)
fn findModuleDocstring(source: []const u8) ?[]const u8 {
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

/// Find docstring following a definition
fn findFollowingDocstring(rest: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, rest, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        if (trimmed.len == 0) continue;

        // Check for docstring start
        if (std.mem.startsWith(u8, trimmed, "\"\"\"")) {
            return extractTripleQuoted(trimmed, "\"\"\"");
        } else if (std.mem.startsWith(u8, trimmed, "'''")) {
            return extractTripleQuoted(trimmed, "'''");
        } else if (std.mem.startsWith(u8, trimmed, "\"") or std.mem.startsWith(u8, trimmed, "'")) {
            // Single-line docstring
            const quote = trimmed[0..1];
            if (trimmed.len > 2) {
                const content = trimmed[1..];
                if (std.mem.indexOf(u8, content, quote)) |end| {
                    return content[0..end];
                }
            }
        }
        // Not a docstring - stop looking
        break;
    }

    return null;
}

/// Extract content from triple-quoted string
fn extractTripleQuoted(line: []const u8, quote: []const u8) ?[]const u8 {
    const start = quote.len;
    const rest = line[start..];

    // Single-line triple-quoted
    if (std.mem.indexOf(u8, rest, quote)) |end| {
        return rest[0..end];
    }

    // Multi-line would need full parsing
    return rest;
}

/// Extract definition name from "def name(" or "class Name:"
fn extractDefinitionName(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trimLeft(u8, text, " \t");

    // Find end of name (at ( or :)
    for (trimmed, 0..) |c, i| {
        if (c == '(' or c == ':') {
            return trimmed[0..i];
        }
        if (!std.ascii.isAlphanumeric(c) and c != '_') {
            return null;
        }
    }
    return null;
}

/// Summary of discovery results
pub const DiscoverySummary = struct {
    modules: usize = 0,
    classes: usize = 0,
    functions: usize = 0,
    methods: usize = 0,
    total_examples: usize = 0,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Found {d} modules, {d} classes, {d} functions, {d} methods", .{
            self.modules,
            self.classes,
            self.functions,
            self.methods,
        });
    }
};

/// Create summary from finder results
pub fn summarize(finder: *const DocTestFinder) DiscoverySummary {
    var summary = DiscoverySummary{};

    for (finder.objects.items) |obj| {
        switch (obj.kind) {
            .module => summary.modules += 1,
            .class => summary.classes += 1,
            .function => summary.functions += 1,
            .method, .staticmethod, .classmethod => summary.methods += 1,
            .property => {},
        }
    }

    return summary;
}

// ============================================================================
// Tests
// ============================================================================

test "FoundObject_qualifiedName_no_parent" {
    const obj = FoundObject{
        .name = "my_func",
        .kind = .function,
        .docstring = null,
        .lineno = 1,
        .parent = null,
    };

    const name = try obj.qualifiedName(std.testing.allocator);
    defer std.testing.allocator.free(name);

    try std.testing.expectEqualStrings("my_func", name);
}

test "FoundObject_qualifiedName_with_parent" {
    const obj = FoundObject{
        .name = "method",
        .kind = .method,
        .docstring = null,
        .lineno = 5,
        .parent = "MyClass",
    };

    const name = try obj.qualifiedName(std.testing.allocator);
    defer std.testing.allocator.free(name);

    try std.testing.expectEqualStrings("MyClass.method", name);
}

test "FoundObject_hasDocstring" {
    const with_doc = FoundObject{
        .name = "test",
        .kind = .function,
        .docstring = "A docstring",
        .lineno = 1,
        .parent = null,
    };
    try std.testing.expect(with_doc.hasDocstring());

    const without_doc = FoundObject{
        .name = "test",
        .kind = .function,
        .docstring = null,
        .lineno = 1,
        .parent = null,
    };
    try std.testing.expect(!without_doc.hasDocstring());
}

test "DocTestFinder_init" {
    var finder = DocTestFinder.init(std.testing.allocator);
    defer finder.deinit();

    try std.testing.expectEqual(@as(usize, 0), finder.objectCount());
    try std.testing.expect(finder.recurse);
}

test "DocTestFinder_find_module_docstring" {
    const source =
        \\"""
        \\This is a module docstring.
        \\
        \\>>> 1 + 1
        \\2
        \\"""
        \\
        \\def foo():
        \\    pass
    ;

    var finder = DocTestFinder.init(std.testing.allocator);
    defer finder.deinit();
    finder.exclude_empty = false;

    try finder.find("test_module", source);

    try std.testing.expect(finder.objectCount() >= 1);
}

test "DocTestFinder_find_function" {
    const source =
        \\def add(a, b):
        \\    """Add two numbers.
        \\
        \\    >>> add(1, 2)
        \\    3
        \\    """
        \\    return a + b
    ;

    var finder = DocTestFinder.init(std.testing.allocator);
    defer finder.deinit();

    try finder.find("math_utils", source);

    const funcs = try finder.objectsOfKind(.function, std.testing.allocator);
    defer std.testing.allocator.free(funcs);

    try std.testing.expectEqual(@as(usize, 1), funcs.len);
    try std.testing.expectEqualStrings("add", funcs[0].name);
}

test "DocTestFinder_find_class" {
    const source =
        \\class MyClass:
        \\    """A test class.
        \\
        \\    >>> obj = MyClass()
        \\    >>> obj.value
        \\    0
        \\    """
        \\
        \\    def __init__(self):
        \\        """Initialize."""
        \\        self.value = 0
    ;

    var finder = DocTestFinder.init(std.testing.allocator);
    defer finder.deinit();

    try finder.find("test_classes", source);

    const classes = try finder.objectsOfKind(.class, std.testing.allocator);
    defer std.testing.allocator.free(classes);

    try std.testing.expectEqual(@as(usize, 1), classes.len);
    try std.testing.expectEqualStrings("MyClass", classes[0].name);
}

test "DocTestFinder_isVisited" {
    var finder = DocTestFinder.init(std.testing.allocator);
    defer finder.deinit();

    const source = "# empty module";
    try finder.find("visited_module", source);

    try std.testing.expect(finder.isVisited("visited_module"));
    try std.testing.expect(!finder.isVisited("other_module"));
}

test "findModuleDocstring_double_quotes" {
    const source =
        \\"""Module docstring."""
        \\
        \\import sys
    ;

    const docstring = findModuleDocstring(source);
    try std.testing.expect(docstring != null);
    try std.testing.expectEqualStrings("Module docstring.", docstring.?);
}

test "findModuleDocstring_single_quotes" {
    const source =
        \\'''Single quote docstring.'''
        \\
        \\def foo():
        \\    pass
    ;

    const docstring = findModuleDocstring(source);
    try std.testing.expect(docstring != null);
    try std.testing.expectEqualStrings("Single quote docstring.", docstring.?);
}

test "findModuleDocstring_none" {
    const source =
        \\# No docstring
        \\import os
    ;

    const docstring = findModuleDocstring(source);
    try std.testing.expect(docstring == null);
}

test "extractDefinitionName_function" {
    try std.testing.expectEqualStrings("foo", extractDefinitionName("foo():").?);
    try std.testing.expectEqualStrings("bar", extractDefinitionName("bar(x, y):").?);
    try std.testing.expectEqualStrings("_private", extractDefinitionName("_private():").?);
}

test "extractDefinitionName_class" {
    try std.testing.expectEqualStrings("MyClass", extractDefinitionName("MyClass:").?);
    try std.testing.expectEqualStrings("Base", extractDefinitionName("Base(object):").?);
}

test "summarize_finder" {
    var finder = DocTestFinder.init(std.testing.allocator);
    defer finder.deinit();
    finder.exclude_empty = false;

    const source =
        \\"""Module doc."""
        \\
        \\class Foo:
        \\    """Class doc."""
        \\
        \\    def method(self):
        \\        """Method doc."""
        \\        pass
        \\
        \\def standalone():
        \\    """Function doc."""
        \\    pass
    ;

    try finder.find("test", source);

    const summary = summarize(&finder);
    try std.testing.expect(summary.modules >= 1);
}

test "DiscoverySummary_format" {
    const summary = DiscoverySummary{
        .modules = 1,
        .classes = 2,
        .functions = 3,
        .methods = 4,
    };

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try stream.writer().print("{}", .{summary});

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "1 modules") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "2 classes") != null);
}

test "DocTestFinder_exclude_empty_true" {
    var finder = DocTestFinder.init(std.testing.allocator);
    defer finder.deinit();
    finder.exclude_empty = true;

    const source =
        \\def no_docstring():
        \\    pass
        \\
        \\def has_docstring():
        \\    """I have a docstring."""
        \\    pass
    ;

    try finder.find("test", source);

    // Only function with docstring should be found
    try std.testing.expectEqual(@as(usize, 1), finder.objectCount());
}

test "DocTestFinder_exclude_empty_false" {
    var finder = DocTestFinder.init(std.testing.allocator);
    defer finder.deinit();
    finder.exclude_empty = false;

    const source =
        \\def no_docstring():
        \\    pass
        \\
        \\def has_docstring():
        \\    """I have a docstring."""
        \\    pass
    ;

    try finder.find("test", source);

    // Both functions should be found
    try std.testing.expectEqual(@as(usize, 2), finder.objectCount());
}
