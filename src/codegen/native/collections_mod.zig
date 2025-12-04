/// Python collections module - Counter, defaultdict, deque, namedtuple, ChainMap
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Public exports for dispatch/builtins.zig
pub fn genDefaultdict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // defaultdict(factory) - factory is used for missing key access
    // We don't fully support this semantic, just create an empty dict
    // Don't use h.discard() as it causes "pointless discard" errors when
    // the factory arg is a variable that's used elsewhere in the function
    //
    // If we have args, just reference them in a way that doesn't trigger warnings
    if (args.len > 0) {
        // For variable arguments that might be used elsewhere, use &var (address-of)
        // This tells Zig we're intentionally referencing it without consuming
        const arg = args[0];
        if (arg == .name) {
            // Variable - just emit the dict init (variable will be used elsewhere)
            try self.emit("hashmap_helper.StringHashMap(i64).init(__global_allocator)");
        } else {
            // Non-variable (like int, str, list literals) - wrap in discard block
            const id = h.emitUniqueBlockStart(self, "discard") catch 0;
            try self.emit("_ = ");
            try self.genExpr(arg);
            h.emitBlockBreak(self, "discard", id) catch {};
            try self.emit("hashmap_helper.StringHashMap(i64).init(__global_allocator); }");
        }
    } else {
        try self.emit("hashmap_helper.StringHashMap(i64).init(__global_allocator)");
    }
}
pub const genOrderedDict = h.discard("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)");

// Counter method handlers for method dispatch
const MethodHandler = *const fn (*NativeCodegen, ast.Node, []ast.Node) CodegenError!void;

pub const CounterMethods = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "most_common", genCounterMostCommon },
    .{ "elements", genCounterElements },
    .{ "subtract", genCounterSubtract },
    .{ "total", genCounterTotal },
});

/// Generate code for Counter.most_common(n)
/// Returns list of (element, count) tuples sorted by count descending
pub fn genCounterMostCommon(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // Generate: runtime.counterMostCommon(counter, n)
    try self.emit("runtime.counterMostCommon(__global_allocator, ");
    try self.genExpr(obj);
    if (args.len > 0) {
        try self.emit(", @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit(", null");
    }
    try self.emit(")");
}

/// Generate code for Counter.elements()
/// Returns iterator over elements repeating each as many times as its count
pub fn genCounterElements(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    // Generate: runtime.counterElements(counter)
    try self.emit("runtime.counterElements(__global_allocator, ");
    try self.genExpr(obj);
    try self.emit(")");
}

/// Generate code for Counter.subtract(iterable_or_mapping)
/// Subtracts counts (can go negative)
pub fn genCounterSubtract(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    // Generate: { for (other.keys()) |k| { counter.getPtr(k).?.* -= other.get(k).?; } }
    try self.emit("{ const __other = ");
    try self.genExpr(args[0]);
    try self.emit("; for (__other.keys()) |__k| { if (");
    try self.genExpr(obj);
    try self.emit(".getPtr(__k)) |__p| { __p.* -= __other.get(__k) orelse 0; } } }");
}

/// Generate code for Counter.total()
/// Returns sum of all counts
pub fn genCounterTotal(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    // Generate: blk: { var sum: i64 = 0; for (counter.values()) |v| sum += v; break :blk sum; }
    try self.emit("counter_total_blk: { var __sum: i64 = 0; for (");
    try self.genExpr(obj);
    try self.emit(".values()) |__v| { __sum += __v; } break :counter_total_blk __sum; }");
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Counter", genCounter },
    .{ "defaultdict", genDefaultdict },
    .{ "deque", genDeque },
    .{ "OrderedDict", genOrderedDict },
    .{ "namedtuple", genNamedtuple },
    .{ "ChainMap", genChainMap },
    .{ "UserDict", h.discard("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)") },
    .{ "UserList", h.discard("std.ArrayList(*runtime.PyObject){}") },
    .{ "UserString", h.pass("\"\"") },
});

// Counter and Deque need comptime dispatch to handle ArrayList vs slice
// Use runtime.iterSlice() to normalize ArrayList to slice first
pub const genCounter = h.wrap(
    "counter_blk: { const _iter_raw = ",
    "; const _iterable = runtime.iterSlice(_iter_raw); var _counter = std.AutoArrayHashMap(@TypeOf(_iterable[0]), i64).init(__global_allocator); for (_iterable) |item| { const entry = _counter.getOrPut(item) catch continue; if (entry.found_existing) { entry.value_ptr.* += 1; } else { entry.value_ptr.* = 1; } } break :counter_blk _counter; }",
    "hashmap_helper.StringHashMap(i64).init(__global_allocator)",
);

pub const genDeque = h.wrap(
    "deque_blk: { const _iter_raw = ",
    "; const _iterable = runtime.iterSlice(_iter_raw); var _deque = std.ArrayList(@TypeOf(_iterable[0])){}; for (_iterable) |item| { _deque.append(__global_allocator, item) catch continue; } break :deque_blk _deque; }",
    "std.ArrayList(i64){}",
);

/// Generate code for collections.namedtuple(typename, field_names)
/// Returns a struct type that can be instantiated
pub fn genNamedtuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // namedtuple returns a type factory - emit a generic struct maker
    // Usage: Point = namedtuple('Point', ['x', 'y']) -> Point becomes a type
    // Then Point(1, 2) creates an instance
    // For simplicity, emit code that creates an anonymous struct
    if (args.len < 2) {
        try self.emit("struct {}");
        return;
    }
    // Extract field names from second argument (should be a list/tuple)
    try self.emit("struct { ");
    // Try to get field names statically if possible
    if (args[1] == .list) {
        for (args[1].list.elts, 0..) |elt, i| {
            if (i > 0) try self.emit(", ");
            if (elt == .constant and elt.constant.value == .string) {
                const field_name = elt.constant.value.string;
                try self.emitFmt("{s}: @TypeOf(undefined)", .{field_name});
            } else {
                try self.emitFmt("@\"{d}\": @TypeOf(undefined)", .{i});
            }
        }
    } else if (args[1] == .constant and args[1].constant.value == .string) {
        // namedtuple('Point', 'x y') format - split by space
        const fields_str = args[1].constant.value.string;
        var iter = std.mem.splitScalar(u8, fields_str, ' ');
        var i: usize = 0;
        while (iter.next()) |field| {
            if (field.len == 0) continue;
            if (i > 0) try self.emit(", ");
            try self.emitFmt("{s}: @TypeOf(undefined)", .{field});
            i += 1;
        }
    }
    try self.emit(" }");
}

/// Generate code for collections.ChainMap(*maps)
/// A ChainMap groups multiple dicts into a single view
pub fn genChainMap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("chainmap_blk: { var _maps = std.ArrayList(hashmap_helper.StringHashMap(*runtime.PyObject)){}; break :chainmap_blk _maps; }");
        return;
    }
    try self.emit("chainmap_blk: { var _maps = std.ArrayList(@TypeOf(");
    try self.genExpr(args[0]);
    try self.emit(")){}; ");
    for (args) |arg| {
        try self.emit("_maps.append(__global_allocator, ");
        try self.genExpr(arg);
        try self.emit(") catch {}; ");
    }
    try self.emit("break :chainmap_blk _maps; }");
}
