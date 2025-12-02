/// Python opcode module - Opcode definitions for Python bytecode
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "opname", genConst("&[_][]const u8{ \"CACHE\", \"POP_TOP\", \"PUSH_NULL\", \"INTERPRETER_EXIT\", \"END_FOR\", \"END_SEND\", \"<6>\", \"<7>\", \"<8>\", \"NOP\", \"<10>\", \"UNARY_NEGATIVE\", \"UNARY_NOT\", \"<13>\", \"<14>\", \"UNARY_INVERT\", \"EXIT_INIT_CHECK\" }") },
    .{ "opmap", genConst(".{ .CACHE = 0, .POP_TOP = 1, .PUSH_NULL = 2, .INTERPRETER_EXIT = 3, .END_FOR = 4, .END_SEND = 5, .NOP = 9, .UNARY_NEGATIVE = 11, .UNARY_NOT = 12, .UNARY_INVERT = 15 }") },
    .{ "cmp_op", genConst("&[_][]const u8{ \"<\", \"<=\", \"==\", \"!=\", \">\", \">=\"}") },
    .{ "hasarg", genConst("&[_]u8{}") }, .{ "hasconst", genConst("&[_]u8{ 100 }") },
    .{ "hasname", genConst("&[_]u8{ 90, 91, 95, 96, 97, 98, 101, 106, 108, 109, 116 }") },
    .{ "hasjrel", genConst("&[_]u8{ 93, 110, 111, 112, 114, 115, 120, 149, 172 }") },
    .{ "hasjabs", genConst("&[_]u8{}") }, .{ "haslocal", genConst("&[_]u8{ 124, 125, 126, 180 }") },
    .{ "hascompare", genConst("&[_]u8{ 107 }") }, .{ "hasfree", genConst("&[_]u8{ 135, 136, 137, 138 }") },
    .{ "hasexc", genConst("&[_]u8{ 121 }") },
    .{ "HAVE_ARGUMENT", genConst("@as(u8, 90)") }, .{ "EXTENDED_ARG", genConst("@as(u8, 144)") },
    .{ "stack_effect", genConst("@as(i32, 0)") }, .{ "_specialized_opmap", genConst(".{}") },
    .{ "_intrinsic_1_descs", genConst("&[_][]const u8{ \"INTRINSIC_1_INVALID\", \"INTRINSIC_PRINT\", \"INTRINSIC_IMPORT_STAR\", \"INTRINSIC_STOPITERATION_ERROR\", \"INTRINSIC_ASYNC_GEN_WRAP\", \"INTRINSIC_UNARY_POSITIVE\", \"INTRINSIC_LIST_TO_TUPLE\", \"INTRINSIC_TYPEVAR\", \"INTRINSIC_PARAMSPEC\", \"INTRINSIC_TYPEVARTUPLE\", \"INTRINSIC_SUBSCRIPT_GENERIC\", \"INTRINSIC_TYPEALIAS\" }") },
    .{ "_intrinsic_2_descs", genConst("&[_][]const u8{ \"INTRINSIC_2_INVALID\", \"INTRINSIC_PREP_RERAISE_STAR\", \"INTRINSIC_TYPEVAR_WITH_BOUND\", \"INTRINSIC_TYPEVAR_WITH_CONSTRAINTS\", \"INTRINSIC_SET_FUNCTION_TYPE_PARAMS\" }") },
});
