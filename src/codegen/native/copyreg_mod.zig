/// Python copyreg module - Register pickle support functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "pickle", genUnit }, .{ "constructor", genConstructor }, .{ "dispatch_table", genDispatchTable },
    .{ "_extension_registry", genExtRegistry }, .{ "_inverted_registry", genInvRegistry },
    .{ "_extension_cache", genExtCache }, .{ "add_extension", genUnit }, .{ "remove_extension", genUnit },
    .{ "clear_extension_cache", genUnit }, .{ "__newobj__", genNewobj }, .{ "__newobj_ex__", genNewobj },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genDispatchTable(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "metal0_runtime.PyDict(usize, @TypeOf(.{ null, null })).init()"); }
fn genExtRegistry(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "metal0_runtime.PyDict(@TypeOf(.{ \"\", \"\" }), i32).init()"); }
fn genInvRegistry(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "metal0_runtime.PyDict(i32, @TypeOf(.{ \"\", \"\" })).init()"); }
fn genExtCache(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "metal0_runtime.PyDict(i32, ?anyopaque).init()"); }

fn genConstructor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else try self.emit("@as(?*const fn() anytype, null)");
}

fn genNewobj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const cls = "); try self.genExpr(args[0]); try self.emit("; break :blk cls{}; }"); } else try self.emit(".{}");
}
