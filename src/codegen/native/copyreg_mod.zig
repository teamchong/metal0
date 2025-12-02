/// Python copyreg module - Register pickle support functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "pickle", genConst("{}") }, .{ "constructor", genConstructor }, .{ "dispatch_table", genConst("metal0_runtime.PyDict(usize, @TypeOf(.{ null, null })).init()") },
    .{ "_extension_registry", genConst("metal0_runtime.PyDict(@TypeOf(.{ \"\", \"\" }), i32).init()") },
    .{ "_inverted_registry", genConst("metal0_runtime.PyDict(i32, @TypeOf(.{ \"\", \"\" })).init()") },
    .{ "_extension_cache", genConst("metal0_runtime.PyDict(i32, ?anyopaque).init()") },
    .{ "add_extension", genConst("{}") }, .{ "remove_extension", genConst("{}") },
    .{ "clear_extension_cache", genConst("{}") }, .{ "__newobj__", genNewobj }, .{ "__newobj_ex__", genNewobj },
});

fn genConstructor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*const fn() anytype, null)");
}

fn genNewobj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const cls = "); try self.genExpr(args[0]); try self.emit("; break :blk cls{}; }"); } else try self.emit(".{}");
}
