/// Python _abc module - Internal ABC support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "get_cache_token", genConst("@as(u64, 0)") }, .{ "_abc_init", genConst("{}") },
    .{ "_abc_register", genReg }, .{ "_abc_instancecheck", genConst("false") },
    .{ "_abc_subclasscheck", genConst("false") }, .{ "_get_dump", genConst(".{ &[_]type{}, &[_]type{}, &[_]type{} }") },
    .{ "_reset_registry", genConst("{}") }, .{ "_reset_caches", genConst("{}") },
});

fn genReg(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) try self.genExpr(args[1]) else try self.emit("null");
}
