/// Python __future__ module - Future statement definitions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "annotations", genConst(".{ .compiler_flag = 0x100000 }") },
    .{ "division", genConst(".{ .compiler_flag = 0x2000 }") },
    .{ "absolute_import", genConst(".{ .compiler_flag = 0x4000 }") },
    .{ "with_statement", genConst(".{ .compiler_flag = 0x8000 }") },
    .{ "print_function", genConst(".{ .compiler_flag = 0x10000 }") },
    .{ "unicode_literals", genConst(".{ .compiler_flag = 0x20000 }") },
    .{ "generator_stop", genConst(".{ .compiler_flag = 0x80000 }") },
    .{ "nested_scopes", genConst(".{ .compiler_flag = 0x10 }") },
    .{ "generators", genConst(".{ .compiler_flag = 0x1000 }") },
});
