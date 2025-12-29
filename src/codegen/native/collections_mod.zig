/// Python collections module - Counter, defaultdict, deque, namedtuple, ChainMap
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Public exports for dispatch/builtins.zig
pub fn genDefaultdict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // defaultdict(factory) - creates a dict with default_factory
    // Use runtime.IntDefaultDict which has default_factory field and __missing__ method
    if (args.len > 0) {
        const arg = args[0];
        // Detect the factory type - use runtime.FactoryType constants
        const factory_type: []const u8 = if (arg == .name) blk: {
            const name = arg.name.id;
            if (std.mem.eql(u8, name, "list")) {
                break :blk ".list";
            } else if (std.mem.eql(u8, name, "int")) {
                break :blk ".int";
            } else if (std.mem.eql(u8, name, "str")) {
                break :blk ".str";
            } else if (std.mem.eql(u8, name, "dict")) {
                break :blk ".dict";
            } else if (std.mem.eql(u8, name, "set")) {
                break :blk ".set";
            } else {
                // Unknown factory - use list as fallback
                break :blk ".list";
            }
        } else ".none";

        try self.emitFmt("runtime.IntDefaultDict(runtime.PyValue).initWithFactory(__global_allocator, {s})", .{factory_type});
    } else {
        // No factory - use none
        try self.emit("runtime.IntDefaultDict(runtime.PyValue).init(__global_allocator)");
    }
}

/// Generate code for OrderedDict(dict)
/// Don't use h.discard() as it causes "pointless discard" when arg is variable used elsewhere
pub fn genOrderedDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const arg = args[0];
        if (arg == .name) {
            // Variable - just emit the dict init (variable will be used elsewhere)
            try self.emit("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)");
        } else {
            // Non-variable - wrap in discard block
            try self.withInlineBlock("discard", args, struct {
                fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                    try c.emit("_ = ");
                    try c.genExpr(a[0]);
                    try c.emitFmt("; break :{s} hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)", .{label});
                }
            }.emit);
        }
    } else {
        try self.emit("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)");
    }
}

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
    if (args.len == 0) return error.UnsupportedSyntax;
    // Generate: { const __other = expr; for (__other.keys()) |__k| { if (obj.getPtr(__k)) |__p| { __p.* -= __other.get(__k) orelse 0; } } }
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
    // Generate: label: { var sum: i64 = 0; for (counter.values()) |v| sum += v; break :label sum; }
    // Note: withInlineBlock expects []ast.Node but we have obj as the counter
    // Create a temporary args slice with obj
    var temp_args = [_]ast.Node{obj};
    try self.withInlineBlock("counter_total", &temp_args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("var __sum: i64 = 0; for (");
            try c.genExpr(a[0]);
            try c.emitFmt(".values()) |__v| {{ __sum += __v; }} break :{s} __sum", .{label});
        }
    }.emit);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Counter", genCounter },
    .{ "defaultdict", genDefaultdict },
    .{ "deque", genDeque },
    .{ "OrderedDict", genOrderedDict },
    .{ "namedtuple", genNamedtuple },
    .{ "ChainMap", genChainMap },
    .{ "UserDict", genUserDict },
    .{ "UserList", genUserList },
    .{ "UserString", h.pass("\"\"") },
});

/// Generate code for UserDict(dict)
/// Don't use h.discard() as it causes "pointless discard" when arg is variable used elsewhere
pub fn genUserDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const arg = args[0];
        if (arg == .name) {
            // Variable - just emit the dict init (variable will be used elsewhere)
            try self.emit("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)");
        } else {
            // Non-variable - wrap in discard block
            try self.withInlineBlock("discard", args, struct {
                fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                    try c.emit("_ = ");
                    try c.genExpr(a[0]);
                    try c.emitFmt("; break :{s} hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)", .{label});
                }
            }.emit);
        }
    } else {
        try self.emit("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)");
    }
}

/// Generate code for UserList(list)
/// Don't use h.discard() as it causes "pointless discard" when arg is variable used elsewhere
pub fn genUserList(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const arg = args[0];
        if (arg == .name) {
            // Variable - just emit the list init (variable will be used elsewhere)
            try self.emit("std.ArrayListUnmanaged(*runtime.PyObject){}");
        } else {
            // Non-variable - wrap in discard block
            try self.withInlineBlock("discard", args, struct {
                fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                    try c.emit("_ = ");
                    try c.genExpr(a[0]);
                    try c.emitFmt("; break :{s} std.ArrayListUnmanaged(*runtime.PyObject){{}}", .{label});
                }
            }.emit);
        }
    } else {
        try self.emit("std.ArrayListUnmanaged(*runtime.PyObject){}");
    }
}

// Counter needs dynamic unique IDs for each invocation
pub fn genCounter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("counter", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const _iter_raw = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; const _iterable = runtime.iterSlice(_iter_raw); var _counter = std.AutoArrayHashMap(@TypeOf(_iterable[0]), i64).init(__global_allocator); for (_iterable) |item| {{ const entry = _counter.getOrPut(item) catch continue; if (entry.found_existing) {{ entry.value_ptr.* += 1; }} else {{ entry.value_ptr.* = 1; }} }} break :{s} _counter", .{label});
            }
        }.emit);
    } else {
        try self.emit("hashmap_helper.StringHashMap(i64).init(__global_allocator)");
    }
}

// Deque needs dynamic unique IDs for each invocation
pub fn genDeque(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("deque", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const _iter_raw = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; const _iterable = runtime.iterSlice(_iter_raw); var _deque = std.ArrayListUnmanaged(@TypeOf(_iterable[0])){{}}; for (_iterable) |item| {{ _deque.append(__global_allocator, item) catch continue; }} break :{s} _deque", .{label});
            }
        }.emit);
    } else {
        try self.emit("std.ArrayListUnmanaged(i64){}");
    }
}

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
    const b = try self.getBuilder();
    try b.write("struct { ");
    // Try to get field names statically if possible
    if (args[1] == .list) {
        for (args[1].list.elts, 0..) |elt, i| {
            if (i > 0) try b.write(", ");
            if (elt == .constant and elt.constant.value == .string) {
                const field_name = elt.constant.value.string;
                try b.writeFmt("{s}: @TypeOf(undefined)", .{field_name});
            } else {
                try b.writeFmt("@\"{d}\": @TypeOf(undefined)", .{i});
            }
        }
    } else if (args[1] == .constant and args[1].constant.value == .string) {
        // namedtuple('Point', 'x y') format - split by space
        const fields_str = args[1].constant.value.string;
        var iter = std.mem.splitScalar(u8, fields_str, ' ');
        var i: usize = 0;
        while (iter.next()) |field| {
            if (field.len == 0) continue;
            if (i > 0) try b.write(", ");
            try b.writeFmt("{s}: @TypeOf(undefined)", .{field});
            i += 1;
        }
    }
    try b.write(" }");
    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
}

/// Generate code for collections.ChainMap(*maps)
/// A ChainMap groups multiple dicts into a single view
pub fn genChainMap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.withInlineBlock("chainmap", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
                try c.emitFmt("var _maps = std.ArrayListUnmanaged(hashmap_helper.StringHashMap(*runtime.PyObject)){{}}; break :{s} _maps", .{label});
            }
        }.emit);
        return;
    }
    try self.withInlineBlock("chainmap", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("var _maps = std.ArrayListUnmanaged(@TypeOf(");
            try c.genExpr(a[0]);
            try c.emit(")){}; ");
            for (a) |arg| {
                try c.emit("_maps.append(__global_allocator, ");
                try c.genExpr(arg);
                try c.emit(") catch unreachable; ");
            }
            try c.emitFmt("break :{s} _maps", .{label});
        }
    }.emit);
}
