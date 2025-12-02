/// Python collections module - Counter, defaultdict, deque
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Counter", genCounter }, .{ "defaultdict", genDefaultdict }, .{ "deque", genDeque },
    .{ "OrderedDict", genOrderedDict }, .{ "namedtuple", genNamedtuple },
});

pub fn genCounter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("counter_blk: { const _iterable = ");
        try self.genExpr(args[0]);
        try self.emit("; var _counter = std.AutoArrayHashMap(@TypeOf(_iterable[0]), i64).init(__global_allocator); for (_iterable) |item| { const entry = _counter.getOrPut(item) catch continue; if (entry.found_existing) { entry.value_ptr.* += 1; } else { entry.value_ptr.* = 1; } } break :counter_blk _counter; }");
    } else {
        try self.emit("hashmap_helper.StringHashMap(i64).init(__global_allocator)");
    }
}

pub fn genDefaultdict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hashmap_helper.StringHashMap(i64).init(__global_allocator)");
}

pub fn genDeque(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("deque_blk: { const _iterable = ");
    try self.genExpr(args[0]);
    try self.emit("; var _deque = std.ArrayList(@TypeOf(_iterable[0])){}; for (_iterable) |item| { _deque.append(__global_allocator, item) catch continue; } break :deque_blk _deque; }");
}

pub fn genOrderedDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)");
}

pub fn genNamedtuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {}");
}
