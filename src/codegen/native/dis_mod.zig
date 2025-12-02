/// Python dis module - Disassembler for Python bytecode
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "dis", genConst("{}") }, .{ "disassemble", genConst("{}") }, .{ "distb", genConst("{}") }, .{ "disco", genConst("{}") },
    .{ "code_info", genConst("\"\"") }, .{ "show_code", genConst("{}") },
    .{ "get_instructions", genConst("&[_]@TypeOf(.{ .opname = \"\", .opcode = @as(i32, 0), .arg = @as(i32, 0), .argval = @as(?*anyopaque, null), .argrepr = \"\", .offset = @as(i32, 0), .starts_line = @as(?i32, null), .is_jump_target = false }){}") },
    .{ "findlinestarts", genConst("&[_]struct { offset: i32, line: i32 }{}") },
    .{ "findlabels", genConst("&[_]i32{}") },
    .{ "stack_effect", genConst("@as(i32, 0)") },
    .{ "Bytecode", genConst(".{ .codeobj = @as(?*anyopaque, null), .first_line = @as(i32, 0), .current_offset = @as(?i32, null) }") },
    .{ "Instruction", genConst(".{ .opname = \"\", .opcode = @as(i32, 0), .arg = @as(i32, 0), .argval = @as(?*anyopaque, null), .argrepr = \"\", .offset = @as(i32, 0), .starts_line = @as(?i32, null), .is_jump_target = false }") },
    .{ "HAVE_ARGUMENT", genConst("@as(i32, 90)") }, .{ "EXTENDED_ARG", genConst("@as(i32, 144)") },
});
