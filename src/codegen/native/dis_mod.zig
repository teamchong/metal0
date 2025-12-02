/// Python dis module - Disassembler for Python bytecode
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "dis", genUnit }, .{ "disassemble", genUnit }, .{ "distb", genUnit }, .{ "disco", genUnit },
    .{ "code_info", genEmptyStr }, .{ "show_code", genUnit }, .{ "get_instructions", genInstructions },
    .{ "findlinestarts", genLineStarts }, .{ "findlabels", genLabels }, .{ "stack_effect", genI32(0) },
    .{ "Bytecode", genBytecode }, .{ "Instruction", genInstruction },
    .{ "HAVE_ARGUMENT", genI32(90) }, .{ "EXTENDED_ARG", genI32(144) },
});

fn genLabels(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]i32{}"); }
fn genLineStarts(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]struct { offset: i32, line: i32 }{}"); }
fn genBytecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .codeobj = @as(?*anyopaque, null), .first_line = @as(i32, 0), .current_offset = @as(?i32, null) }"); }
fn genInstruction(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .opname = \"\", .opcode = @as(i32, 0), .arg = @as(i32, 0), .argval = @as(?*anyopaque, null), .argrepr = \"\", .offset = @as(i32, 0), .starts_line = @as(?i32, null), .is_jump_target = false }"); }
fn genInstructions(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{ .opname = \"\", .opcode = @as(i32, 0), .arg = @as(i32, 0), .argval = @as(?*anyopaque, null), .argrepr = \"\", .offset = @as(i32, 0), .starts_line = @as(?i32, null), .is_jump_target = false }){}"); }
