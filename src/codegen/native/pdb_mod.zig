/// Python pdb module - Python debugger
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Pdb", genConst(".{ .skip = @as(?[]const []const u8, null), .nosigint = false }") },
    .{ "run", genConst("{}") }, .{ "runeval", genConst("@as(?*anyopaque, null)") }, .{ "runcall", genConst("@as(?*anyopaque, null)") },
    .{ "set_trace", genConst("{}") }, .{ "post_mortem", genConst("{}") }, .{ "pm", genConst("{}") }, .{ "help", genConst("{}") },
    .{ "Breakpoint", genConst(".{ .file = \"\", .line = @as(i32, 0), .temporary = false, .cond = @as(?[]const u8, null), .funcname = @as(?[]const u8, null), .enabled = true, .ignore = @as(i32, 0), .hits = @as(i32, 0), .number = @as(i32, 0) }") },
});
