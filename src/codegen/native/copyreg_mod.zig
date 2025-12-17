/// Python copyreg module - Register pickle support functions
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "pickle", h.c("{}") },
    .{ "constructor", h.pass("@as(?*const fn() anytype, null)") },
    .{ "dispatch_table", h.c("hashmap_helper.AutoHashMap(usize, ?*anyopaque).init(__global_allocator)") },
    .{ "_extension_registry", h.c("hashmap_helper.StringHashMap(i32).init(__global_allocator)") },
    .{ "_inverted_registry", h.c("hashmap_helper.AutoHashMap(i32, []const u8).init(__global_allocator)") },
    .{ "_extension_cache", h.c("hashmap_helper.AutoHashMap(i32, ?*anyopaque).init(__global_allocator)") },
    .{ "add_extension", h.c("{}") },
    .{ "remove_extension", h.c("{}") },
    .{ "clear_extension_cache", h.c("{}") },
    .{ "__newobj__", genNewobj },
    .{ "__newobj_ex__", genNewobjEx },
});

fn genNewobj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{}");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{}_newobj: {{ const cls = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; break :__m{}_newobj cls{{}}; }}", .{id});
}

fn genNewobjEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{}");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{}_newobj_ex: {{ const cls = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; break :__m{}_newobj_ex cls{{}}; }}", .{id});
}
