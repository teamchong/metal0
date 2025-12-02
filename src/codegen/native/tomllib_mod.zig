/// Python tomllib module - Parse TOML files (Python 3.11+)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "load", genLoad }, .{ "loads", genLoads }, .{ "TOMLDecodeError", h.err("TOMLDecodeError") },
});

fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const fp = "); try self.genExpr(args[0]); try self.emit("; _ = fp; break :blk .{}; }"); } else { try self.emit(".{}"); }
}

fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const s = "); try self.genExpr(args[0]); try self.emit("; _ = s; break :blk .{}; }"); } else { try self.emit(".{}"); }
}
