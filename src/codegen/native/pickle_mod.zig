/// Python pickle module - Full object serialization with proper protocol support
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dumps", genDumps }, .{ "loads", genLoads }, .{ "dump", genDump }, .{ "load", genLoad },
    .{ "HIGHEST_PROTOCOL", h.I64(5) }, .{ "DEFAULT_PROTOCOL", h.I64(4) },
    .{ "PicklingError", h.err("PicklingError") }, .{ "UnpicklingError", h.err("UnpicklingError") },
    .{ "Pickler", h.c("runtime.pickle.Pickler.init(__global_allocator, 4)") },
    .{ "Unpickler", h.c("runtime.pickle.Unpickler") },
});

fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Get protocol if specified (2nd arg)
    var protocol: u8 = 4; // default
    if (args.len > 1 and args[1] == .constant and args[1].constant.value == .int) {
        protocol = @intCast(args[1].constant.value.int);
    }

    // Use the full pickle implementation
    try self.emit("(try runtime.pickle.dumpsWithProtocol(");
    try self.genExpr(args[0]);
    try self.emitFmt(", __global_allocator, {d}))", .{protocol});
}

fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("runtime.pickle.PickleValue{ .none = {} }");
        return;
    }
    // Use the full pickle implementation - returns PickleValue
    try self.emit("(runtime.pickle.loads(");
    try self.genExpr(args[0]);
    try self.emit(", __global_allocator) catch runtime.pickle.PickleValue{ .none = {} })");
}

fn genDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("pickle_dump_blk: { const _pickle_data = try runtime.pickle.dumps(");
    try self.genExpr(args[0]);
    try self.emit(", __global_allocator); const _file = ");
    try self.genExpr(args[1]);
    try self.emit("; _ = _file.write(_pickle_data) catch 0; break :pickle_dump_blk; }");
}

fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit("runtime.pickle.PickleValue{ .none = {} }");
        return;
    }
    try self.emit("pickle_load_blk: { const _file = ");
    try self.genExpr(args[0]);
    try self.emit("; const _content = _file.readToEndAlloc(__global_allocator, 100 * 1024 * 1024) catch break :pickle_load_blk runtime.pickle.PickleValue{ .none = {} }; break :pickle_load_blk (runtime.pickle.loads(_content, __global_allocator) catch runtime.pickle.PickleValue{ .none = {} }); }");
}
