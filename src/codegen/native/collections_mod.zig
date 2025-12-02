/// Python collections module - Counter, defaultdict, deque
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Public exports for dispatch/builtins.zig
pub const genDefaultdict = h.discard("hashmap_helper.StringHashMap(i64).init(__global_allocator)");
pub const genOrderedDict = h.discard("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Counter", genCounter }, .{ "defaultdict", genDefaultdict }, .{ "deque", genDeque },
    .{ "OrderedDict", genOrderedDict }, .{ "namedtuple", h.discard("struct {}") },
});

pub const genCounter = h.wrap("counter_blk: { const _iterable = ", "; var _counter = std.AutoArrayHashMap(@TypeOf(_iterable[0]), i64).init(__global_allocator); for (_iterable) |item| { const entry = _counter.getOrPut(item) catch continue; if (entry.found_existing) { entry.value_ptr.* += 1; } else { entry.value_ptr.* = 1; } } break :counter_blk _counter; }", "hashmap_helper.StringHashMap(i64).init(__global_allocator)");

pub const genDeque = h.wrap("deque_blk: { const _iterable = ", "; var _deque = std.ArrayList(@TypeOf(_iterable[0])){}; for (_iterable) |item| { _deque.append(__global_allocator, item) catch continue; } break :deque_blk _deque; }", "std.ArrayList(i64){}");

