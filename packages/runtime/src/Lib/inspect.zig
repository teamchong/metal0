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
// Source code inspection with file access
// ============================================================================

/// Get the source file of an object using Zig's @src() builtin
/// For types defined in known modules, attempts to infer source location
pub fn getfile(comptime T: type) ?[]const u8 {
    // Check if type has a __file__ declaration (Python convention)
    if (@hasDecl(T, "__file__")) {
        return @field(T, "__file__");
    }
    // Check for source_location from @src()
    if (@hasDecl(T, "__source_location__")) {
        const loc = @field(T, "__source_location__");
        return loc.file;
    }
    // Use @typeName to extract module path info
    const name = @typeName(T);
    // Strip package prefix if present (e.g., "runtime.Lib.foo")
    if (std.mem.indexOf(u8, name, ".")) |_| {
        // Type is from a known module, but we can't get exact file without debug info
        return null;
    }
    return null;
}

/// Get the source file name
pub fn getsourcefile(comptime T: type) ?[]const u8 {
    return getfile(T);
}

/// Source cache for runtime file reading
const SourceCache = struct {
    const max_files = 16;
    const max_file_size = 1024 * 1024; // 1MB max per file

    var cached_files: [max_files]CachedFile = [_]CachedFile{.{}} ** max_files;
    var cache_index: usize = 0;

    const CachedFile = struct {
        path: [256]u8 = [_]u8{0} ** 256,
        path_len: usize = 0,
        content: ?[]const u8 = null,
        lines: ?[]const []const u8 = null,
    };

    fn get(path: []const u8) ?*CachedFile {
        for (&cached_files) |*cf| {
            if (cf.path_len == path.len and
                std.mem.eql(u8, cf.path[0..cf.path_len], path))
            {
                return cf;
            }
        }
        return null;
    }
};

/// Get the source code of an object from file
/// Takes a file path and returns the file contents
pub fn getsourceFromFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size > SourceCache.max_file_size) {
        return error.FileTooLarge;
    }

    return try file.readToEndAlloc(allocator, SourceCache.max_file_size);
}

/// Get the source code of an object
pub fn getsource(_: anytype) ?[]const u8 {
    // For runtime values, we'd need the associated source file
    // This requires debug info that's not available at runtime
    return null;
}

/// Get the source lines from a file
pub fn getsourcelines_from_file(allocator: std.mem.Allocator, path: []const u8) !struct {
    lines: std.ArrayList([]const u8),
    content: []u8,
} {
    const content = try getsourceFromFile(allocator, path);
    errdefer allocator.free(content);

    var lines = std.ArrayList([]const u8).init(allocator);
    errdefer lines.deinit();

    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        try lines.append(line);
    }

    return .{ .lines = lines, .content = content };
}

/// Get the source lines
pub fn getsourcelines(_: anytype) ?struct { lines: []const []const u8, lineno: usize } {
    // For runtime values without debug info, return null
    return null;
}

/// Get the docstring
pub fn getdoc(comptime T: type) ?[]const u8 {
    if (@hasDecl(T, "__doc__")) {
        return @field(T, "__doc__");
    }
    return null;
}

/// Get the comments
/// NOTE: In AOT compilation, source comments are not preserved at runtime.
/// This function always returns null. Use doc comments (__doc__) instead.
pub fn getcomments(_: anytype) ?[]const u8 {
    // AOT limitation: Source code and comments are not available at runtime.
    // The Python AST is parsed at compile time and source is not retained.
    return null;
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
// Stack frame inspection (AOT: uses Zig debug info)
// ============================================================================

/// Frame information structure
pub const FrameInfo = struct {
    filename: []const u8,
    lineno: usize,
    function: []const u8,
    code_context: ?[]const u8,
    index: ?usize,
};

/// Get the current frame's return address
/// In AOT compilation, returns the instruction pointer
pub fn currentframe() ?*anyopaque {
    return @returnAddress();
}

/// Get stack trace as formatted string
/// Uses Zig's builtin stack trace functionality
pub fn stack(allocator: std.mem.Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    const writer = buffer.writer();

    var stack_trace = std.builtin.StackTrace{
        .instruction_addresses = undefined,
        .index = 0,
    };

    // Capture current stack
    std.debug.captureStackTrace(@returnAddress(), &stack_trace);

    // Format stack trace
    if (stack_trace.index > 0) {
        try writer.writeAll("Stack (most recent call last):\n");
        var debug_info = std.debug.getSelfDebugInfo() catch {
            try writer.writeAll("  <debug info unavailable>\n");
            return buffer.toOwnedSlice();
        };

        for (stack_trace.instruction_addresses[0..stack_trace.index]) |addr| {
            const symbol = debug_info.getSymbolFromAddress(addr);
            if (symbol.symbol_name) |name| {
                try writer.print("  File \"{s}\", line {d}, in {s}\n", .{
                    symbol.compile_unit_name orelse "<unknown>",
                    symbol.line_info.line orelse 0,
                    name,
                });
            }
        }
    }

    return buffer.toOwnedSlice();
}

/// Get the outer frames (caller frames)
/// Returns frame info for each frame in the call stack
pub fn getouterframes(allocator: std.mem.Allocator, frame: ?*anyopaque, context: usize) ![]FrameInfo {
    _ = frame;
    var frames = std.ArrayList(FrameInfo).init(allocator);

    var stack_trace = std.builtin.StackTrace{
        .instruction_addresses = undefined,
        .index = 0,
    };
    std.debug.captureStackTrace(@returnAddress(), &stack_trace);

    const debug_info = std.debug.getSelfDebugInfo() catch return frames.toOwnedSlice();

    const max_frames = @min(stack_trace.index, context);
    for (stack_trace.instruction_addresses[0..max_frames]) |addr| {
        const symbol = debug_info.getSymbolFromAddress(addr);
        try frames.append(.{
            .filename = symbol.compile_unit_name orelse "<unknown>",
            .lineno = symbol.line_info.line orelse 0,
            .function = symbol.symbol_name orelse "<unknown>",
            .code_context = null,
            .index = null,
        });
    }

    return frames.toOwnedSlice();
}

/// Get the inner frames (frames called from this frame)
/// In AOT, this returns empty as we can only see the call stack up, not down
pub fn getinnerframes(allocator: std.mem.Allocator, _: ?*anyopaque, _: usize) ![]FrameInfo {
    // Inner frames would require tracking frames as they're created
    // In AOT compilation, we only have access to the return address chain
    return allocator.alloc(FrameInfo, 0);
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
