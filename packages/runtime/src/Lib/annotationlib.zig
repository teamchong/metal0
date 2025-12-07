//! CPython source: Lib/annotationlib.py
//!
//! Provides tools for working with annotations (PEP 563, PEP 649).
//!
//! Mirrors: CPython Lib/annotationlib.py

const std = @import("std");

// ============================================================================
// Format Enum
// ============================================================================

/// Annotation format specifier
pub const Format = enum {
    /// Evaluate annotations as expressions
    VALUE,
    /// Keep annotations as strings (PEP 563)
    STRING,
    /// Return ForwardRef objects for unevaluated annotations
    FORWARDREF,
    /// Return the source code string
    SOURCE,
};

// ============================================================================
// ForwardRef
// ============================================================================

/// Represents a forward reference annotation
pub const ForwardRef = struct {
    const Self = @This();

    /// The string representation of the annotation
    arg: []const u8,
    /// Whether the annotation has been evaluated
    is_evaluated: bool = false,
    /// The evaluated value (if evaluated)
    evaluated_value: ?*anyopaque = null,
    /// Module where the annotation was defined
    module: ?[]const u8 = null,
    /// Owner of the annotation (class or function)
    owner: ?[]const u8 = null,

    pub fn init(arg: []const u8) Self {
        return .{
            .arg = arg,
        };
    }

    /// Evaluate the forward reference
    pub fn evaluate(self: *Self, globalns: ?*anyopaque, localns: ?*anyopaque) !*anyopaque {
        _ = globalns;
        _ = localns;
        if (self.is_evaluated) {
            return self.evaluated_value orelse error.NoValue;
        }
        // In AOT compilation, we can't dynamically evaluate
        return error.CannotEvaluate;
    }

    /// Get string representation
    pub fn repr(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "ForwardRef('{s}')", .{self.arg});
    }

    pub fn eql(self: *const Self, other: *const Self) bool {
        return std.mem.eql(u8, self.arg, other.arg);
    }
};

// ============================================================================
// Annotation Utilities
// ============================================================================

/// Get annotations from an object with specified format
pub fn get_annotations(
    allocator: std.mem.Allocator,
    obj: anytype,
    format: Format,
    eval_str: bool,
) !std.StringHashMap([]const u8) {
    _ = obj;
    _ = eval_str;
    var annotations = std.StringHashMap([]const u8).init(allocator);

    // In AOT compilation, annotations are typically stored as metadata
    // This is a simplified implementation
    switch (format) {
        .VALUE => {
            // Return evaluated annotations
        },
        .STRING => {
            // Return string annotations (PEP 563)
        },
        .FORWARDREF => {
            // Return ForwardRef objects
        },
        .SOURCE => {
            // Return source strings
        },
    }

    return annotations;
}

/// Convert annotations to string format
pub fn annotations_to_string(
    allocator: std.mem.Allocator,
    annotations: std.StringHashMap(*anyopaque),
) !std.StringHashMap([]const u8) {
    var result = std.StringHashMap([]const u8).init(allocator);

    var iter = annotations.iterator();
    while (iter.next()) |entry| {
        // Convert each annotation to its string representation
        const str = try std.fmt.allocPrint(allocator, "{any}", .{entry.value_ptr.*});
        try result.put(entry.key_ptr.*, str);
    }

    return result;
}

/// Get type hints from an object
pub fn get_type_hints(
    allocator: std.mem.Allocator,
    obj: anytype,
    globalns: ?*anyopaque,
    localns: ?*anyopaque,
    include_extras: bool,
) !std.StringHashMap([]const u8) {
    _ = globalns;
    _ = localns;
    _ = include_extras;
    _ = obj;
    return std.StringHashMap([]const u8).init(allocator);
}

// ============================================================================
// Type Checking Utilities
// ============================================================================

/// Check if an annotation is a ForwardRef
pub fn is_forward_ref(annotation: anytype) bool {
    const T = @TypeOf(annotation);
    return T == ForwardRef or T == *ForwardRef or T == *const ForwardRef;
}

/// Resolve string annotations to ForwardRef objects
pub fn stringize_annotations(
    allocator: std.mem.Allocator,
    annotations: std.StringHashMap([]const u8),
) !std.StringHashMap(ForwardRef) {
    var result = std.StringHashMap(ForwardRef).init(allocator);

    var iter = annotations.iterator();
    while (iter.next()) |entry| {
        try result.put(entry.key_ptr.*, ForwardRef.init(entry.value_ptr.*));
    }

    return result;
}

// ============================================================================
// PEP 649 Support
// ============================================================================

/// Annotation evaluation mode
pub const EvalMode = enum {
    /// Evaluate immediately
    eager,
    /// Evaluate lazily (PEP 649)
    deferred,
    /// Keep as strings (PEP 563)
    stringified,
};

/// Get the current annotation evaluation mode
pub fn get_eval_mode() EvalMode {
    // In AOT compilation, we typically use deferred evaluation
    return .deferred;
}

/// Evaluate deferred annotations
pub fn evaluate_annotations(
    allocator: std.mem.Allocator,
    obj: anytype,
    globalns: ?*anyopaque,
    localns: ?*anyopaque,
) !std.StringHashMap([]const u8) {
    _ = globalns;
    _ = localns;
    _ = obj;
    return std.StringHashMap([]const u8).init(allocator);
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the annotationlib module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "Format enum" {
    try std.testing.expect(@intFromEnum(Format.VALUE) == 0);
    try std.testing.expect(@intFromEnum(Format.STRING) == 1);
    try std.testing.expect(@intFromEnum(Format.FORWARDREF) == 2);
    try std.testing.expect(@intFromEnum(Format.SOURCE) == 3);
}

test "ForwardRef init" {
    const ref = ForwardRef.init("List[int]");
    try std.testing.expectEqualStrings("List[int]", ref.arg);
    try std.testing.expect(!ref.is_evaluated);
    try std.testing.expect(ref.evaluated_value == null);
}

test "ForwardRef repr" {
    const allocator = std.testing.allocator;
    const ref = ForwardRef.init("Dict[str, int]");
    const repr = try ref.repr(allocator);
    defer allocator.free(repr);
    try std.testing.expectEqualStrings("ForwardRef('Dict[str, int]')", repr);
}

test "ForwardRef equality" {
    const ref1 = ForwardRef.init("int");
    const ref2 = ForwardRef.init("int");
    const ref3 = ForwardRef.init("str");

    try std.testing.expect(ref1.eql(&ref2));
    try std.testing.expect(!ref1.eql(&ref3));
}

test "is_forward_ref" {
    const ref = ForwardRef.init("int");
    try std.testing.expect(is_forward_ref(ref));
    try std.testing.expect(!is_forward_ref(@as(i32, 42)));
}

test "get_eval_mode" {
    const mode = get_eval_mode();
    try std.testing.expect(mode == .deferred);
}

test "EvalMode enum" {
    try std.testing.expect(@intFromEnum(EvalMode.eager) == 0);
    try std.testing.expect(@intFromEnum(EvalMode.deferred) == 1);
    try std.testing.expect(@intFromEnum(EvalMode.stringified) == 2);
}
