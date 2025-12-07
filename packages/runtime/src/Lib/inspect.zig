//! CPython source: Lib/inspect.py
//!
//! Provides functions to get information about live objects such as modules,
//! classes, methods, functions, tracebacks, frame objects, and code objects.
//!
//! Mirrors: CPython Lib/inspect.py

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Type checking predicates
// ============================================================================

/// Check if the object is a module
pub fn ismodule(comptime T: type) bool {
    // In Zig, modules are namespaces at comptime
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "__module__");
}

/// Check if the object is a class (struct in Zig)
pub fn isclass(comptime T: type) bool {
    return @typeInfo(T) == .@"struct";
}

/// Check if the object is a method
pub fn ismethod(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info == .@"fn") {
        // Methods have a self parameter
        return info.@"fn".params.len > 0;
    }
    return false;
}

/// Check if the object is a function
pub fn isfunction(comptime T: type) bool {
    return @typeInfo(T) == .@"fn";
}

/// Check if the object is a generator function
pub fn isgeneratorfunction(comptime T: type) bool {
    // Zig doesn't have native generators, but we can check for iterator patterns
    _ = T;
    return false;
}

/// Check if the object is a generator
pub fn isgenerator(comptime T: type) bool {
    // Check if it implements the iterator pattern
    return @hasDecl(T, "next");
}

/// Check if the object is a coroutine function
pub fn iscoroutinefunction(comptime T: type) bool {
    // Check if it's an async function
    const info = @typeInfo(T);
    if (info == .@"fn") {
        return info.@"fn".is_async;
    }
    return false;
}

/// Check if the object is a coroutine
pub fn iscoroutine(_: anytype) bool {
    return false; // Zig handles async differently
}

/// Check if the object is awaitable
pub fn isawaitable(comptime T: type) bool {
    return @hasDecl(T, "await") or iscoroutinefunction(T);
}

/// Check if the object is async generator function
pub fn isasyncgenfunction(comptime T: type) bool {
    return iscoroutinefunction(T) and isgenerator(T);
}

/// Check if the object is async generator
pub fn isasyncgen(comptime T: type) bool {
    return isasyncgenfunction(T);
}

/// Check if the object is a traceback
pub fn istraceback(_: anytype) bool {
    return false; // Zig doesn't have tracebacks in the same way
}

/// Check if the object is a frame
pub fn isframe(_: anytype) bool {
    return false; // Zig doesn't have frames in the same way
}

/// Check if the object is a code object
pub fn iscode(_: anytype) bool {
    return false; // Zig doesn't have code objects
}

/// Check if the object is a built-in function
pub fn isbuiltin(comptime T: type) bool {
    return @typeInfo(T) == .@"fn";
}

/// Check if the object is a routine (function, method, or builtin)
pub fn isroutine(comptime T: type) bool {
    return isfunction(T) or ismethod(T) or isbuiltin(T);
}

/// Check if the object appears to be abstract
pub fn isabstract(comptime T: type) bool {
    // Check if it has abstractmethod declarations
    return @hasDecl(T, "__abstractmethods__");
}

/// Check if the object is a data descriptor
pub fn isdatadescriptor(comptime T: type) bool {
    return @hasDecl(T, "__get__") and @hasDecl(T, "__set__");
}

/// Check if the object is a member descriptor
pub fn ismemberdescriptor(comptime T: type) bool {
    return @hasDecl(T, "__get__") and !@hasDecl(T, "__set__");
}

/// Check if the object is a method descriptor
pub fn ismethoddescriptor(comptime T: type) bool {
    return @hasDecl(T, "__get__") and !@hasDecl(T, "__set__") and !isdatadescriptor(T);
}

// ============================================================================
// Signature inspection
// ============================================================================

/// Parameter kind enum
pub const ParameterKind = enum {
    POSITIONAL_ONLY,
    POSITIONAL_OR_KEYWORD,
    VAR_POSITIONAL,
    KEYWORD_ONLY,
    VAR_KEYWORD,
};

/// Parameter representation
pub const Parameter = struct {
    name: []const u8,
    kind: ParameterKind = .POSITIONAL_OR_KEYWORD,
    default: ?[]const u8 = null,
    annotation: ?[]const u8 = null,

    pub const empty = Parameter{ .name = "" };
};

/// Function signature
pub const Signature = struct {
    parameters: []const Parameter,
    return_annotation: ?[]const u8 = null,

    pub fn init(params: []const Parameter) Signature {
        return .{ .parameters = params };
    }

    pub fn withReturn(self: Signature, ret: []const u8) Signature {
        return .{ .parameters = self.parameters, .return_annotation = ret };
    }
};

/// Get the signature of a function type
pub fn getSignature(comptime T: type) Signature {
    const info = @typeInfo(T);

    if (info != .@"fn") {
        return Signature.init(&[_]Parameter{});
    }

    const fn_info = info.@"fn";
    var params: [fn_info.params.len]Parameter = undefined;

    inline for (fn_info.params, 0..) |param, i| {
        params[i] = .{
            .name = if (param.name) |n| n else "",
            .kind = .POSITIONAL_OR_KEYWORD,
            .annotation = if (param.type) |t| @typeName(t) else "any",
        };
    }

    return Signature.init(&params);
}

// ============================================================================
// Member inspection
// ============================================================================

/// Member information
pub const MemberInfo = struct {
    name: []const u8,
    value_type: []const u8,
};

/// Get methods of a type as a slice
pub fn getmethods(comptime T: type) []const []const u8 {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") return &[_][]const u8{};

    const decls = type_info.@"struct".decls;
    comptime var count: usize = 0;

    // Count methods
    inline for (decls) |decl| {
        const field_type = @TypeOf(@field(T, decl.name));
        if (@typeInfo(field_type) == .@"fn") {
            count += 1;
        }
    }

    comptime var result: [count][]const u8 = undefined;
    comptime var idx: usize = 0;

    inline for (decls) |decl| {
        const field_type = @TypeOf(@field(T, decl.name));
        if (@typeInfo(field_type) == .@"fn") {
            result[idx] = decl.name;
            idx += 1;
        }
    }

    return &result;
}

// ============================================================================
// Source code inspection (stubs - would need file access)
// ============================================================================

/// Get the source file of an object
pub fn getfile(comptime _: type) ?[]const u8 {
    return null; // Would need debug info
}

/// Get the source file name
pub fn getsourcefile(comptime T: type) ?[]const u8 {
    return getfile(T);
}

/// Get the source code of an object
pub fn getsource(_: anytype) ?[]const u8 {
    return null; // Would need debug info
}

/// Get the source lines
pub fn getsourcelines(_: anytype) ?struct { lines: []const []const u8, lineno: usize } {
    return null; // Would need debug info
}

/// Get the docstring
pub fn getdoc(comptime T: type) ?[]const u8 {
    if (@hasDecl(T, "__doc__")) {
        return @field(T, "__doc__");
    }
    return null;
}

/// Get the comments
pub fn getcomments(_: anytype) ?[]const u8 {
    return null; // Would need source access
}

// ============================================================================
// Class hierarchy
// ============================================================================

/// Get the method resolution order
pub fn getmro(comptime T: type) []const type {
    // Zig doesn't have class inheritance, so MRO is just the type itself
    return &[_]type{T};
}

/// Check if a class is a subclass of another
pub fn issubclass(comptime Sub: type, comptime Super: type) bool {
    // In Zig, we check structural compatibility
    if (Sub == Super) return true;

    // Check if Sub has all fields of Super
    const sub_info = @typeInfo(Sub);
    const super_info = @typeInfo(Super);

    if (sub_info != .@"struct" or super_info != .@"struct") return false;

    for (super_info.@"struct".fields) |super_field| {
        var found = false;
        for (sub_info.@"struct".fields) |sub_field| {
            if (std.mem.eql(u8, super_field.name, sub_field.name)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }

    return true;
}

// ============================================================================
// Stack frame inspection (stubs)
// ============================================================================

/// Get the current frame
pub fn currentframe() ?*anyopaque {
    return null;
}

/// Get the stack
pub fn stack() []const u8 {
    return "";
}

/// Get the outer frames
pub fn getouterframes(_: anytype) []const u8 {
    return "";
}

/// Get the inner frames
pub fn getinnerframes(_: anytype) []const u8 {
    return "";
}

// ============================================================================
// Attributes
// ============================================================================

/// Check if an object has an attribute
pub fn hasattr(comptime T: type, comptime name: []const u8) bool {
    return @hasField(T, name) or @hasDecl(T, name);
}

// ============================================================================
// Callable inspection
// ============================================================================

/// Check if the object is callable
pub fn callable(comptime T: type) bool {
    const info = @typeInfo(T);
    return info == .@"fn" or (info == .@"struct" and @hasDecl(T, "call"));
}

// ============================================================================
// Formatting
// ============================================================================

/// Format a signature as a string
pub fn formatargspec(sig: Signature, allocator: std.mem.Allocator) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.append('(');

    for (sig.parameters, 0..) |param, i| {
        if (i > 0) {
            try result.appendSlice(", ");
        }
        try result.appendSlice(param.name);

        if (param.annotation) |ann| {
            try result.appendSlice(": ");
            try result.appendSlice(ann);
        }

        if (param.default) |def| {
            try result.appendSlice(" = ");
            try result.appendSlice(def);
        }
    }

    try result.append(')');

    if (sig.return_annotation) |ret| {
        try result.appendSlice(" -> ");
        try result.appendSlice(ret);
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Cleandoc
// ============================================================================

/// Clean up indentation from docstrings
pub fn cleandoc(allocator: std.mem.Allocator, doc: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var lines = std.mem.splitScalar(u8, doc, '\n');
    var first = true;
    var min_indent: usize = std.math.maxInt(usize);

    // Find minimum indentation
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        var indent: usize = 0;
        for (line) |c| {
            if (c == ' ' or c == '\t') {
                indent += 1;
            } else {
                break;
            }
        }
        if (indent < line.len) {
            min_indent = @min(min_indent, indent);
        }
    }

    if (min_indent == std.math.maxInt(usize)) {
        min_indent = 0;
    }

    // Reset and strip
    lines = std.mem.splitScalar(u8, doc, '\n');
    while (lines.next()) |line| {
        if (!first) {
            try result.append('\n');
        }
        first = false;

        if (line.len >= min_indent) {
            try result.appendSlice(line[min_indent..]);
        }
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Tests
// ============================================================================

test "isclass" {
    const MyStruct = struct {
        x: i32,
        y: i32,
    };

    try std.testing.expect(isclass(MyStruct));
    try std.testing.expect(!isclass(i32));
}

test "isfunction" {
    const myFunc = struct {
        fn call(x: i32) i32 {
            return x + 1;
        }
    }.call;

    try std.testing.expect(isfunction(@TypeOf(myFunc)));
}

test "callable" {
    const Callable = struct {
        pub fn call(self: @This()) void {
            _ = self;
        }
    };

    try std.testing.expect(callable(Callable));
}

test "hasattr" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    try std.testing.expect(hasattr(Point, "x"));
    try std.testing.expect(hasattr(Point, "y"));
    try std.testing.expect(!hasattr(Point, "z"));
}

test "getmethods" {
    const Calculator = struct {
        pub fn add(a: i32, b: i32) i32 {
            return a + b;
        }
        pub fn sub(a: i32, b: i32) i32 {
            return a - b;
        }
    };

    const methods = getmethods(Calculator);
    try std.testing.expectEqual(@as(usize, 2), methods.len);
}

test "formatargspec" {
    const allocator = std.testing.allocator;

    const params = [_]Parameter{
        .{ .name = "x", .annotation = "i32" },
        .{ .name = "y", .annotation = "i32", .default = "0" },
    };

    const sig = Signature.init(&params).withReturn("i32");
    const formatted = try formatargspec(sig, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "x: i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "y: i32 = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "-> i32") != null);
}

test "cleandoc" {
    const allocator = std.testing.allocator;

    const doc =
        \\    This is a docstring.
        \\    It has multiple lines.
        \\    With consistent indentation.
    ;

    const cleaned = try cleandoc(allocator, doc);
    defer allocator.free(cleaned);

    try std.testing.expect(std.mem.startsWith(u8, cleaned, "This is a docstring."));
}
