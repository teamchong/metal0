/// Python _threading_local module - Internal threading.local support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "local", genConst(".{}") }, .{ "_localimpl", genConst(".{ .key = \"\", .dicts = .{}, .localargs = .{}, .localkwargs = .{}, .loclock = .{} }") },
    .{ "_localimpl_create_dict", genConst(".{}") }, .{ "__init__", genConst("{}") },
    .{ "__getattribute__", genConst("null") }, .{ "__setattr__", genConst("{}") }, .{ "__delattr__", genConst("{}") },
});
