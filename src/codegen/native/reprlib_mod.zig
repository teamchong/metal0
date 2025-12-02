/// Python reprlib module - Alternate repr() implementation
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Repr", h.c(".{ .maxlevel = 6, .maxtuple = 6, .maxlist = 6, .maxarray = 5, .maxdict = 4, .maxset = 6, .maxfrozenset = 6, .maxdeque = 6, .maxstring = 30, .maxlong = 40, .maxother = 30, .fillvalue = \"...\" }") },
    .{ "repr", genReprFunc },
    .{ "recursive_repr", h.c("@as(?*const fn(anytype) anytype, null)") },
});

fn genReprFunc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const obj = "); try self.genExpr(args[0]); try self.emit("; break :blk std.fmt.allocPrint(metal0_allocator, \"{any}\", .{obj}) catch \"<repr error>\"; }"); } else try self.emit("\"\"");
}
