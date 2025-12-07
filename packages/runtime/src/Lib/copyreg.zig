//! CPython source: Lib/copyreg.py
//!
//! Provides functions for registering pickling support for types.
//!
//! Mirrors: CPython Lib/copyreg.py

const std = @import("std");

// ============================================================================
// Dispatch Table
// ============================================================================

/// Global dispatch table mapping types to reduction functions
var dispatch_table: ?std.StringHashMap(ReductionFn) = null;
var dispatch_allocator: ?std.mem.Allocator = null;

pub const ReductionFn = *const fn (*anyopaque) ReduceResult;

pub const ReduceResult = struct {
    callable: []const u8,
    args: []const []const u8,
    state: ?[]const u8,
    list_items: ?[]const []const u8,
    dict_items: ?[]const []const u8,
};

/// Initialize the dispatch table
pub fn initDispatchTable(allocator: std.mem.Allocator) void {
    if (dispatch_table == null) {
        dispatch_table = std.StringHashMap(ReductionFn).init(allocator);
        dispatch_allocator = allocator;
    }
}

/// Deinitialize the dispatch table
pub fn deinitDispatchTable() void {
    if (dispatch_table) |*dt| {
        dt.deinit();
        dispatch_table = null;
        dispatch_allocator = null;
    }
}

// ============================================================================
// pickle - Register a reduce function for a type
// ============================================================================

/// Register a reduce function for a type
pub fn pickle(
    type_name: []const u8,
    reduce_fn: ReductionFn,
) !void {
    if (dispatch_table) |*dt| {
        try dt.put(type_name, reduce_fn);
    }
}

/// Get the reduce function for a type
pub fn getReduceFn(type_name: []const u8) ?ReductionFn {
    if (dispatch_table) |dt| {
        return dt.get(type_name);
    }
    return null;
}

// ============================================================================
// constructor - Register a constructor for unpickling
// ============================================================================

/// Constructor registry
var constructor_table: ?std.StringHashMap(ConstructorFn) = null;

pub const ConstructorFn = *const fn ([]const []const u8) *anyopaque;

/// Register a constructor for a type
pub fn constructor(
    type_name: []const u8,
    ctor_fn: ConstructorFn,
) !void {
    if (constructor_table == null) {
        if (dispatch_allocator) |alloc| {
            constructor_table = std.StringHashMap(ConstructorFn).init(alloc);
        }
    }

    if (constructor_table) |*ct| {
        try ct.put(type_name, ctor_fn);
    }
}

/// Get constructor for a type
pub fn getConstructor(type_name: []const u8) ?ConstructorFn {
    if (constructor_table) |ct| {
        return ct.get(type_name);
    }
    return null;
}

// ============================================================================
// Extension Registry (for pickle protocol 2+)
// ============================================================================

/// Extension code registry
var extension_registry: ?std.StringHashMap(i32) = null;
var inverted_registry: ?std.AutoHashMap(i32, []const u8) = null;

/// Add extension code mapping
pub fn add_extension(
    module: []const u8,
    name: []const u8,
    code: i32,
) !void {
    if (dispatch_allocator) |alloc| {
        if (extension_registry == null) {
            extension_registry = std.StringHashMap(i32).init(alloc);
        }
        if (inverted_registry == null) {
            inverted_registry = std.AutoHashMap(i32, []const u8).init(alloc);
        }

        // Create key "module name"
        const key = try std.fmt.allocPrint(alloc, "{s} {s}", .{ module, name });

        if (extension_registry) |*er| {
            try er.put(key, code);
        }
        if (inverted_registry) |*ir| {
            try ir.put(code, key);
        }
    }
}

/// Remove extension code mapping
pub fn remove_extension(
    module: []const u8,
    name: []const u8,
    code: i32,
) void {
    _ = code;
    if (dispatch_allocator) |alloc| {
        const key = std.fmt.allocPrint(alloc, "{s} {s}", .{ module, name }) catch return;
        defer alloc.free(key);

        if (extension_registry) |*er| {
            _ = er.remove(key);
        }
    }
}

/// Clear all extension registrations
pub fn clear_extension_cache() void {
    if (extension_registry) |*er| {
        er.clearRetainingCapacity();
    }
    if (inverted_registry) |*ir| {
        ir.clearRetainingCapacity();
    }
}

// ============================================================================
// __reduce_ex__ helpers
// ============================================================================

/// Helper to create a simple reduce result
pub fn simpleReduce(
    callable: []const u8,
    args: []const []const u8,
) ReduceResult {
    return .{
        .callable = callable,
        .args = args,
        .state = null,
        .list_items = null,
        .dict_items = null,
    };
}

/// Helper to create a reduce result with state
pub fn reduceWithState(
    callable: []const u8,
    args: []const []const u8,
    state: []const u8,
) ReduceResult {
    return .{
        .callable = callable,
        .args = args,
        .state = state,
        .list_items = null,
        .dict_items = null,
    };
}

// ============================================================================
// _reconstructor - Default reconstructor for classes
// ============================================================================

/// Reconstruct an object (used by pickle)
pub fn _reconstructor(
    cls: []const u8,
    base: []const u8,
    state: ?[]const u8,
) !*anyopaque {
    _ = cls;
    _ = base;
    _ = state;
    // Would create a new instance and set its state
    return error.NotImplemented;
}

// ============================================================================
// Slot wrapper registrations
// ============================================================================

/// Register for __reduce__ slot
pub const ReduceSlot = struct {
    type_name: []const u8,
    reduce_fn: ReductionFn,
};

/// Common type registrations
pub fn registerBuiltinTypes(allocator: std.mem.Allocator) !void {
    initDispatchTable(allocator);

    // Would register reduce functions for built-in types like:
    // - complex
    // - set
    // - frozenset
    // - dict
    // - list
    // - etc.
}

// ============================================================================
// Tests
// ============================================================================

test "initDispatchTable" {
    const allocator = std.testing.allocator;
    initDispatchTable(allocator);
    defer deinitDispatchTable();

    try std.testing.expect(dispatch_table != null);
}

test "simpleReduce" {
    const result = simpleReduce("int", &.{"42"});
    try std.testing.expectEqualStrings("int", result.callable);
    try std.testing.expect(result.state == null);
}

test "reduceWithState" {
    const result = reduceWithState("MyClass", &.{}, "state_data");
    try std.testing.expectEqualStrings("MyClass", result.callable);
    try std.testing.expectEqualStrings("state_data", result.state.?);
}

test "pickle and getReduceFn" {
    const allocator = std.testing.allocator;
    initDispatchTable(allocator);
    defer deinitDispatchTable();

    const testReduce = struct {
        fn reduce(_: *anyopaque) ReduceResult {
            return simpleReduce("test", &.{});
        }
    }.reduce;

    try pickle("TestType", testReduce);
    const fn_ptr = getReduceFn("TestType");
    try std.testing.expect(fn_ptr != null);
}

test "getReduceFn missing" {
    const allocator = std.testing.allocator;
    initDispatchTable(allocator);
    defer deinitDispatchTable();

    const fn_ptr = getReduceFn("NonexistentType");
    try std.testing.expect(fn_ptr == null);
}

test "clear_extension_cache" {
    const allocator = std.testing.allocator;
    initDispatchTable(allocator);
    defer deinitDispatchTable();

    // Should not crash
    clear_extension_cache();
}
