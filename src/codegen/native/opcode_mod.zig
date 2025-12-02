/// Python opcode module - Opcode definitions for Python bytecode
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "opname", genOpname }, .{ "opmap", genOpmap }, .{ "cmp_op", genCmpOp },
    .{ "hasarg", genEmptyU8 }, .{ "hasconst", genHasconst }, .{ "hasname", genHasname },
    .{ "hasjrel", genHasjrel }, .{ "hasjabs", genEmptyU8 }, .{ "haslocal", genHaslocal },
    .{ "hascompare", genHascompare }, .{ "hasfree", genHasfree }, .{ "hasexc", genHasexc },
    .{ "HAVE_ARGUMENT", genHaveArg }, .{ "EXTENDED_ARG", genExtendedArg },
    .{ "stack_effect", genStackEffect }, .{ "_specialized_opmap", genEmpty },
    .{ "_intrinsic_1_descs", genIntrinsic1 }, .{ "_intrinsic_2_descs", genIntrinsic2 },
});

fn genOpname(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"CACHE\", \"POP_TOP\", \"PUSH_NULL\", \"INTERPRETER_EXIT\", \"END_FOR\", \"END_SEND\", \"<6>\", \"<7>\", \"<8>\", \"NOP\", \"<10>\", \"UNARY_NEGATIVE\", \"UNARY_NOT\", \"<13>\", \"<14>\", \"UNARY_INVERT\", \"EXIT_INIT_CHECK\" }"); }
fn genOpmap(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .CACHE = 0, .POP_TOP = 1, .PUSH_NULL = 2, .INTERPRETER_EXIT = 3, .END_FOR = 4, .END_SEND = 5, .NOP = 9, .UNARY_NEGATIVE = 11, .UNARY_NOT = 12, .UNARY_INVERT = 15 }"); }
fn genCmpOp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"<\", \"<=\", \"==\", \"!=\", \">\", \">=\"}"); }
fn genEmptyU8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{}"); }
fn genHasconst(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{ 100 }"); }
fn genHasname(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{ 90, 91, 95, 96, 97, 98, 101, 106, 108, 109, 116 }"); }
fn genHasjrel(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{ 93, 110, 111, 112, 114, 115, 120, 149, 172 }"); }
fn genHaslocal(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{ 124, 125, 126, 180 }"); }
fn genHascompare(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{ 107 }"); }
fn genHasfree(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{ 135, 136, 137, 138 }"); }
fn genHasexc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{ 121 }"); }
fn genHaveArg(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 90)"); }
fn genExtendedArg(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 144)"); }
fn genStackEffect(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genIntrinsic1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"INTRINSIC_1_INVALID\", \"INTRINSIC_PRINT\", \"INTRINSIC_IMPORT_STAR\", \"INTRINSIC_STOPITERATION_ERROR\", \"INTRINSIC_ASYNC_GEN_WRAP\", \"INTRINSIC_UNARY_POSITIVE\", \"INTRINSIC_LIST_TO_TUPLE\", \"INTRINSIC_TYPEVAR\", \"INTRINSIC_PARAMSPEC\", \"INTRINSIC_TYPEVARTUPLE\", \"INTRINSIC_SUBSCRIPT_GENERIC\", \"INTRINSIC_TYPEALIAS\" }"); }
fn genIntrinsic2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"INTRINSIC_2_INVALID\", \"INTRINSIC_PREP_RERAISE_STAR\", \"INTRINSIC_TYPEVAR_WITH_BOUND\", \"INTRINSIC_TYPEVAR_WITH_CONSTRAINTS\", \"INTRINSIC_SET_FUNCTION_TYPE_PARAMS\" }"); }
