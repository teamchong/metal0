//! test.test_future_stmt.test_annotations - Tests for `from __future__ import annotations`
//!
//! PEP 563 introduced postponed evaluation of annotations.
//! In Python 3.10+, annotations are stored as strings rather than evaluated at definition time.
//! This allows forward references and reduces import-time overhead.
//!
//! CPython Reference: https://docs.python.org/3/library/__future__.html
//! PEP 563: https://peps.python.org/pep-0563/

const std = @import("std");
const testing = std.testing;

// ============================================================================
// Annotation Storage Types
// ============================================================================

/// Represents a stringified annotation (PEP 563 style)
/// When `from __future__ import annotations` is active, all annotations
/// are stored as string literals rather than evaluated expressions.
pub const StringifiedAnnotation = struct {
    /// The raw annotation string as it appears in source code
    raw: []const u8,
    /// Whether this annotation has been resolved to a type
    resolved: bool = false,
    /// Cached resolved type name (after get_type_hints() is called)
    resolved_type: ?[]const u8 = null,

    const Self = @This();

    /// Create a new stringified annotation
    pub fn init(raw: []const u8) Self {
        return .{ .raw = raw };
    }

    /// Check if annotation contains a forward reference
    pub fn isForwardRef(self: Self) bool {
        // Forward refs are typically quoted strings or unresolvable at definition time
        return !self.resolved;
    }

    /// Attempt to resolve the annotation string to a type name
    /// In real Python, this would call typing.get_type_hints()
    pub fn resolve(self: *Self, namespace: anytype) !void {
        _ = namespace;
        self.resolved = true;
        self.resolved_type = self.raw;
    }

    /// Get string representation
    pub fn toString(self: Self) []const u8 {
        return self.raw;
    }

    /// Check equality with another annotation
    pub fn eql(self: Self, other: Self) bool {
        return std.mem.eql(u8, self.raw, other.raw);
    }
};

/// Type hints container for a function or class
pub const TypeHints = struct {
    allocator: std.mem.Allocator,
    hints: std.StringHashMap(StringifiedAnnotation),
    return_hint: ?StringifiedAnnotation = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .hints = std.StringHashMap(StringifiedAnnotation).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.hints.deinit();
    }

    /// Add a parameter annotation
    pub fn addParam(self: *Self, name: []const u8, annotation: StringifiedAnnotation) !void {
        try self.hints.put(name, annotation);
    }

    /// Set return type annotation
    pub fn setReturn(self: *Self, annotation: StringifiedAnnotation) void {
        self.return_hint = annotation;
    }

    /// Get annotation for a parameter
    pub fn getParam(self: Self, name: []const u8) ?StringifiedAnnotation {
        return self.hints.get(name);
    }

    /// Get all parameter names
    pub fn paramNames(self: Self) []const []const u8 {
        var names: [32][]const u8 = undefined;
        var idx: usize = 0;
        var it = self.hints.keyIterator();
        while (it.next()) |key| {
            if (idx < 32) {
                names[idx] = key.*;
                idx += 1;
            }
        }
        return names[0..idx];
    }

    /// Get total number of annotations
    pub fn count(self: Self) usize {
        var total = self.hints.count();
        if (self.return_hint != null) total += 1;
        return total;
    }
};

// ============================================================================
// Annotation Context Manager
// ============================================================================

/// Context manager for temporarily enabling/disabling annotation stringification
/// Simulates the effect of `from __future__ import annotations`
pub const AnnotationsContext = struct {
    enabled: bool,
    previous_state: bool = false,

    const Self = @This();

    /// Global state tracking whether stringified annotations are enabled
    var global_enabled: bool = false;

    pub fn init(enabled: bool) Self {
        return .{ .enabled = enabled };
    }

    pub fn __enter__(self: *Self) *Self {
        self.previous_state = global_enabled;
        global_enabled = self.enabled;
        return self;
    }

    pub fn __exit__(self: *Self) void {
        global_enabled = self.previous_state;
    }

    /// Check if stringified annotations are currently enabled
    pub fn isEnabled() bool {
        return global_enabled;
    }
};

// ============================================================================
// Forward Reference Handling
// ============================================================================

/// Represents a forward reference that can be resolved later
pub const ForwardRef = struct {
    /// The string representation of the type
    arg: []const u8,
    /// Whether the reference has been evaluated
    is_evaluated: bool = false,
    /// The module where this forward ref was defined
    module: ?[]const u8 = null,

    const Self = @This();

    pub fn init(arg: []const u8) Self {
        return .{ .arg = arg };
    }

    /// Create a forward ref with module context
    pub fn initWithModule(arg: []const u8, module: []const u8) Self {
        return .{ .arg = arg, .module = module };
    }

    /// Evaluate the forward reference in a given namespace
    pub fn evaluate(self: *Self, globalns: anytype, localns: anytype) !void {
        _ = globalns;
        _ = localns;
        self.is_evaluated = true;
    }

    /// Get the string representation
    pub fn repr(self: Self) []const u8 {
        return self.arg;
    }

    /// Check if this is a class reference
    pub fn isClass(self: Self) bool {
        // Simple heuristic: starts with uppercase
        if (self.arg.len == 0) return false;
        return std.ascii.isUpper(self.arg[0]);
    }
};

// ============================================================================
// Annotation Evaluation Utilities
// ============================================================================

/// Get type hints from an annotated object
/// This simulates typing.get_type_hints() behavior
pub fn getTypeHints(allocator: std.mem.Allocator, annotations: anytype) !TypeHints {
    var hints = TypeHints.init(allocator);

    // If annotations is a map-like structure, iterate over it
    if (@hasDecl(@TypeOf(annotations), "iterator")) {
        var it = annotations.iterator();
        while (it.next()) |entry| {
            const annotation = StringifiedAnnotation.init(entry.value_ptr.*);
            try hints.addParam(entry.key_ptr.*, annotation);
        }
    }

    return hints;
}

/// Stringify a type annotation for storage
pub fn stringifyAnnotation(comptime T: type) []const u8 {
    return @typeName(T);
}

/// Parse an annotation string to check validity
pub fn parseAnnotation(annotation: []const u8) !void {
    // Basic validation - check for balanced brackets
    var depth: i32 = 0;
    for (annotation) |c| {
        switch (c) {
            '[', '(' => depth += 1,
            ']', ')' => depth -= 1,
            else => {},
        }
        if (depth < 0) return error.UnbalancedBrackets;
    }
    if (depth != 0) return error.UnbalancedBrackets;
}

// ============================================================================
// Annotation Visitor Pattern
// ============================================================================

/// Visitor for traversing annotation AST nodes
pub const AnnotationVisitor = struct {
    visited_names: std.ArrayListUnmanaged([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .visited_names = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.visited_names.deinit(self.allocator);
    }

    /// Visit a name node in the annotation
    pub fn visitName(self: *Self, name: []const u8) !void {
        try self.visited_names.append(self.allocator, name);
    }

    /// Visit a subscript (e.g., List[int])
    pub fn visitSubscript(self: *Self, base: []const u8, args: []const []const u8) !void {
        try self.visitName(base);
        for (args) |arg| {
            try self.visitName(arg);
        }
    }

    /// Get all visited names
    pub fn getVisitedNames(self: Self) []const []const u8 {
        return self.visited_names.items;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "stringified_annotation_creation" {
    const ann = StringifiedAnnotation.init("int");
    try testing.expectEqualStrings("int", ann.raw);
    try testing.expect(!ann.resolved);
    try testing.expect(ann.isForwardRef());
}

test "stringified_annotation_equality" {
    const ann1 = StringifiedAnnotation.init("List[str]");
    const ann2 = StringifiedAnnotation.init("List[str]");
    const ann3 = StringifiedAnnotation.init("List[int]");

    try testing.expect(ann1.eql(ann2));
    try testing.expect(!ann1.eql(ann3));
}

test "type_hints_container" {
    var hints = TypeHints.init(testing.allocator);
    defer hints.deinit();

    try hints.addParam("x", StringifiedAnnotation.init("int"));
    try hints.addParam("y", StringifiedAnnotation.init("str"));
    hints.setReturn(StringifiedAnnotation.init("bool"));

    try testing.expectEqual(@as(usize, 3), hints.count());
    try testing.expect(hints.getParam("x") != null);
    try testing.expectEqualStrings("int", hints.getParam("x").?.raw);
}

test "forward_ref_creation" {
    const ref = ForwardRef.init("MyClass");
    try testing.expectEqualStrings("MyClass", ref.arg);
    try testing.expect(!ref.is_evaluated);
    try testing.expect(ref.isClass());
}

test "forward_ref_lowercase_not_class" {
    const ref = ForwardRef.init("some_type");
    try testing.expect(!ref.isClass());
}

test "annotation_context_manager" {
    try testing.expect(!AnnotationsContext.isEnabled());

    var ctx = AnnotationsContext.init(true);
    _ = ctx.__enter__();
    try testing.expect(AnnotationsContext.isEnabled());
    ctx.__exit__();

    try testing.expect(!AnnotationsContext.isEnabled());
}

test "parse_annotation_balanced" {
    try parseAnnotation("List[int]");
    try parseAnnotation("Dict[str, List[int]]");
    try parseAnnotation("Callable[[int, str], bool]");
}

test "parse_annotation_unbalanced" {
    try testing.expectError(error.UnbalancedBrackets, parseAnnotation("List[int"));
    try testing.expectError(error.UnbalancedBrackets, parseAnnotation("Dict[str, int]]"));
}

test "annotation_visitor" {
    var visitor = AnnotationVisitor.init(testing.allocator);
    defer visitor.deinit();

    try visitor.visitSubscript("List", &.{"int"});
    const names = visitor.getVisitedNames();

    try testing.expectEqual(@as(usize, 2), names.len);
    try testing.expectEqualStrings("List", names[0]);
    try testing.expectEqualStrings("int", names[1]);
}

test "stringify_annotation" {
    const result = stringifyAnnotation(i64);
    try testing.expect(result.len > 0);
}

test "forward_ref_with_module" {
    const ref = ForwardRef.initWithModule("SomeClass", "mymodule");
    try testing.expectEqualStrings("SomeClass", ref.arg);
    try testing.expectEqualStrings("mymodule", ref.module.?);
}
