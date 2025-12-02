/// Python copyreg module - Register pickle support functions
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "pickle", h.c("{}") }, .{ "constructor", genConstructor }, .{ "dispatch_table", h.c("metal0_runtime.PyDict(usize, @TypeOf(.{ null, null })).init()") },
    .{ "_extension_registry", h.c("metal0_runtime.PyDict(@TypeOf(.{ \"\", \"\" }), i32).init()") },
    .{ "_inverted_registry", h.c("metal0_runtime.PyDict(i32, @TypeOf(.{ \"\", \"\" })).init()") },
    .{ "_extension_cache", h.c("metal0_runtime.PyDict(i32, ?anyopaque).init()") },
    .{ "add_extension", h.c("{}") }, .{ "remove_extension", h.c("{}") },
    .{ "clear_extension_cache", h.c("{}") }, .{ "__newobj__", genNewobj }, .{ "__newobj_ex__", genNewobj },
});

fn genConstructor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*const fn() anytype, null)");
}

fn genNewobj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const cls = "); try self.genExpr(args[0]); try self.emit("; break :blk cls{}; }"); } else try self.emit(".{}");
}
