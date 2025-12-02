/// Python _pickle module - C accelerator for pickle (internal)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dumps", genDumps }, .{ "dump", h.c("{}") }, .{ "loads", genLoads }, .{ "load", h.c("null") },
    .{ "Pickler", h.c(".{ .protocol = 4 }") }, .{ "Unpickler", h.c(".{}") }, .{ "HIGHEST_PROTOCOL", h.I32(5) }, .{ "DEFAULT_PROTOCOL", h.I32(4) },
    .{ "PickleError", h.err("PickleError") }, .{ "PicklingError", h.err("PicklingError") }, .{ "UnpicklingError", h.err("UnpicklingError") },
});

fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const obj = "); try self.genExpr(args[0]); try self.emit("; _ = obj; break :blk \"\"; }"); } else { try self.emit("\"\""); }
}

fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const data = "); try self.genExpr(args[0]); try self.emit("; _ = data; break :blk null; }"); } else { try self.emit("null"); }
}
