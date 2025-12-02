/// Python _opcode module - Internal opcode support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "stack_effect", genConst("@as(i32, 0)") }, .{ "is_valid", genConst("true") }, .{ "has_arg", genConst("true") },
    .{ "has_const", genConst("false") }, .{ "has_name", genConst("false") }, .{ "has_jump", genConst("false") },
    .{ "has_free", genConst("false") }, .{ "has_local", genConst("false") }, .{ "has_exc", genConst("false") },
});
