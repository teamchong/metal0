/// Python _threading_local module - Internal threading.local support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "local", genEmpty }, .{ "_localimpl", genLocalimpl }, .{ "_localimpl_create_dict", genEmpty }, .{ "__init__", genUnit }, .{ "__getattribute__", genNull }, .{ "__setattr__", genUnit }, .{ "__delattr__", genUnit },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genLocalimpl(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .key = \"\", .dicts = .{}, .localargs = .{}, .localkwargs = .{}, .loclock = .{} }"); }
