//! CPython source: Lib/pyclbr.py
//!
//! Provides functions for extracting class and function definitions
//! from Python source code without importing it.
//!
//! Mirrors: CPython Lib/pyclbr.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Class - Represents a class definition
// ============================================================================

pub const Class = struct {
    allocator: std.mem.Allocator,

    /// Module where the class is defined
    module: []const u8,

    /// Name of the class
    name: []const u8,

    /// Super classes (base classes)
    super: std.ArrayList([]const u8),

    /// Methods defined in the class
    methods: hashmap_helper.StringHashMap(usize), // method name -> line number

    /// File where the class is defined
    file: []const u8,

    /// Line number where the class is defined
    lineno: usize,

    /// End line number
    end_lineno: ?usize = null,

    /// Parent class (for nested classes)
    parent: ?*Class = null,

    /// Nested classes
    children: hashmap_helper.StringHashMap(*Class),

    pub fn init(
        allocator: std.mem.Allocator,
        module: []const u8,
        name: []const u8,
        file: []const u8,
        lineno: usize,
    ) !*Class {
        const cls = try allocator.create(Class);
        cls.* = .{
            .allocator = allocator,
            .module = try allocator.dupe(u8, module),
            .name = try allocator.dupe(u8, name),
            .super = std.ArrayList([]const u8).init(allocator),
            .methods = hashmap_helper.StringHashMap(usize).init(allocator),
            .file = try allocator.dupe(u8, file),
            .lineno = lineno,
            .children = hashmap_helper.StringHashMap(*Class).init(allocator),
        };
        return cls;
    }

    pub fn deinit(self: *Class) void {
        self.allocator.free(self.module);
        self.allocator.free(self.name);
        self.allocator.free(self.file);

        for (self.super.items) |s| {
            self.allocator.free(s);
        }
        self.super.deinit();

        self.methods.deinit();

        var it = self.children.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.children.deinit();
    }

    /// Add a method to the class
    pub fn addMethod(self: *Class, name: []const u8, lineno: usize) !void {
        try self.methods.put(name, lineno);
    }

    /// Add a super class
    pub fn addSuper(self: *Class, name: []const u8) !void {
        try self.super.append(try self.allocator.dupe(u8, name));
    }
};

// ============================================================================
// Function - Represents a function definition
// ============================================================================

pub const Function = struct {
    allocator: std.mem.Allocator,

    /// Module where the function is defined
    module: []const u8,

    /// Name of the function
    name: []const u8,

    /// File where the function is defined
    file: []const u8,

    /// Line number where the function is defined
    lineno: usize,

    /// End line number
    end_lineno: ?usize = null,

    /// Whether it's async
    is_async: bool = false,

    /// Parent (for nested functions)
    parent: ?*anyopaque = null,

    pub fn init(
        allocator: std.mem.Allocator,
        module: []const u8,
        name: []const u8,
        file: []const u8,
        lineno: usize,
    ) !*Function {
        const func = try allocator.create(Function);
        func.* = .{
            .allocator = allocator,
            .module = try allocator.dupe(u8, module),
            .name = try allocator.dupe(u8, name),
            .file = try allocator.dupe(u8, file),
            .lineno = lineno,
        };
        return func;
    }

    pub fn deinit(self: *Function) void {
        self.allocator.free(self.module);
        self.allocator.free(self.name);
        self.allocator.free(self.file);
    }
};

// ============================================================================
// Module-level functions
// ============================================================================

/// Read a module and return a dictionary of classes and functions
pub fn readmodule(
    allocator: std.mem.Allocator,
    module: []const u8,
    path: ?[]const []const u8,
) !hashmap_helper.StringHashMap(*Class) {
    _ = path;
    const result = try readmodule_ex(allocator, module, null);
    // Filter to only return classes
    var classes = hashmap_helper.StringHashMap(*Class).init(allocator);
    var it = result.classes.iterator();
    while (it.next()) |entry| {
        try classes.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    return classes;
}

/// Read a module and return both classes and functions
pub const ReadModuleResult = struct {
    classes: hashmap_helper.StringHashMap(*Class),
    functions: hashmap_helper.StringHashMap(*Function),
};

pub fn readmodule_ex(
    allocator: std.mem.Allocator,
    module: []const u8,
    path: ?[]const []const u8,
) !ReadModuleResult {
    _ = path;

    // Find the source file for the module
    const filename = try moduleToFilename(allocator, module);
    defer allocator.free(filename);

    // Read and parse the file
    const file = std.fs.cwd().openFile(filename, .{}) catch {
        return ReadModuleResult{
            .classes = hashmap_helper.StringHashMap(*Class).init(allocator),
            .functions = hashmap_helper.StringHashMap(*Function).init(allocator),
        };
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    return parseSource(allocator, content, module, filename);
}

/// Parse Python source code and extract classes and functions
fn parseSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    module: []const u8,
    filename: []const u8,
) !ReadModuleResult {
    var classes = hashmap_helper.StringHashMap(*Class).init(allocator);
    var functions = hashmap_helper.StringHashMap(*Function).init(allocator);

    var line_num: usize = 0;
    var lines = std.mem.splitSequence(u8, source, "\n");

    while (lines.next()) |line| {
        line_num += 1;

        const trimmed = std.mem.trimLeft(u8, line, " \t");

        // Check for class definition
        if (std.mem.startsWith(u8, trimmed, "class ")) {
            if (parseClassDef(trimmed)) |name| {
                const cls = try Class.init(allocator, module, name, filename, line_num);
                try classes.put(name, cls);
            }
        }
        // Check for function definition
        else if (std.mem.startsWith(u8, trimmed, "def ")) {
            if (parseFuncDef(trimmed, false)) |name| {
                const func = try Function.init(allocator, module, name, filename, line_num);
                try functions.put(name, func);
            }
        }
        // Check for async function definition
        else if (std.mem.startsWith(u8, trimmed, "async def ")) {
            if (parseFuncDef(trimmed, true)) |name| {
                const func = try Function.init(allocator, module, name, filename, line_num);
                func.is_async = true;
                try functions.put(name, func);
            }
        }
    }

    return ReadModuleResult{
        .classes = classes,
        .functions = functions,
    };
}

/// Parse a class definition line and extract the class name
fn parseClassDef(line: []const u8) ?[]const u8 {
    const after_class = line[6..]; // Skip "class "
    var end: usize = 0;

    // Find end of class name (at : or ()
    for (after_class, 0..) |c, i| {
        if (c == ':' or c == '(') {
            end = i;
            break;
        }
    }

    if (end == 0) {
        // Check for simple case: class Name:
        for (after_class, 0..) |c, i| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') {
                end = i;
                break;
            }
        }
    }

    if (end > 0) {
        return after_class[0..end];
    }
    return null;
}

/// Parse a function definition line and extract the function name
fn parseFuncDef(line: []const u8, is_async: bool) ?[]const u8 {
    const offset: usize = if (is_async) 10 else 4; // "async def " or "def "
    if (line.len <= offset) return null;

    const after_def = line[offset..];
    var end: usize = 0;

    // Find end of function name (at ()
    for (after_def, 0..) |c, i| {
        if (c == '(') {
            end = i;
            break;
        }
    }

    if (end > 0) {
        return after_def[0..end];
    }
    return null;
}

/// Convert module name to filename
fn moduleToFilename(allocator: std.mem.Allocator, module: []const u8) ![]u8 {
    // Replace dots with path separator
    var filename = std.ArrayList(u8).init(allocator);
    for (module) |c| {
        if (c == '.') {
            try filename.append(std.fs.path.sep);
        } else {
            try filename.append(c);
        }
    }
    try filename.appendSlice(".py");
    return filename.toOwnedSlice();
}

// ============================================================================
// Tests
// ============================================================================

test "Class init" {
    const allocator = std.testing.allocator;
    const cls = try Class.init(allocator, "mymodule", "MyClass", "test.py", 10);
    defer {
        cls.deinit();
        allocator.destroy(cls);
    }

    try std.testing.expectEqualStrings("mymodule", cls.module);
    try std.testing.expectEqualStrings("MyClass", cls.name);
    try std.testing.expectEqual(@as(usize, 10), cls.lineno);
}

test "Class addMethod" {
    const allocator = std.testing.allocator;
    const cls = try Class.init(allocator, "test", "Test", "test.py", 1);
    defer {
        cls.deinit();
        allocator.destroy(cls);
    }

    try cls.addMethod("__init__", 2);
    try cls.addMethod("foo", 5);

    try std.testing.expectEqual(@as(usize, 2), cls.methods.get("__init__").?);
    try std.testing.expectEqual(@as(usize, 5), cls.methods.get("foo").?);
}

test "Function init" {
    const allocator = std.testing.allocator;
    const func = try Function.init(allocator, "mymodule", "my_func", "test.py", 20);
    defer {
        func.deinit();
        allocator.destroy(func);
    }

    try std.testing.expectEqualStrings("mymodule", func.module);
    try std.testing.expectEqualStrings("my_func", func.name);
    try std.testing.expectEqual(@as(usize, 20), func.lineno);
}

test "parseClassDef" {
    try std.testing.expectEqualStrings("Foo", parseClassDef("class Foo:").?);
    try std.testing.expectEqualStrings("Bar", parseClassDef("class Bar(Base):").?);
    try std.testing.expectEqualStrings("Baz", parseClassDef("class Baz(A, B):").?);
}

test "parseFuncDef" {
    try std.testing.expectEqualStrings("foo", parseFuncDef("def foo():", false).?);
    try std.testing.expectEqualStrings("bar", parseFuncDef("def bar(x, y):", false).?);
    try std.testing.expectEqualStrings("async_func", parseFuncDef("async def async_func():", true).?);
}

test "moduleToFilename" {
    const allocator = std.testing.allocator;

    const f1 = try moduleToFilename(allocator, "mymodule");
    defer allocator.free(f1);
    try std.testing.expectEqualStrings("mymodule.py", f1);

    const f2 = try moduleToFilename(allocator, "package.module");
    defer allocator.free(f2);
    try std.testing.expect(std.mem.endsWith(u8, f2, "module.py"));
}
