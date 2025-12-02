/// Python faulthandler module - Dump Python tracebacks on fault signals
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "enable", genConst("{}") }, .{ "disable", genConst("{}") }, .{ "is_enabled", genConst("true") },
    .{ "dump_traceback", genConst("{}") }, .{ "dump_traceback_later", genConst("{}") },
    .{ "cancel_dump_traceback_later", genConst("{}") }, .{ "register", genConst("{}") }, .{ "unregister", genConst("{}") },
});
