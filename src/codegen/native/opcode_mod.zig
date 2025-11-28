/// Python opcode module - Opcode definitions for Python bytecode
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate opcode.opname list
pub fn genOpname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"CACHE\", \"POP_TOP\", \"PUSH_NULL\", \"INTERPRETER_EXIT\", \"END_FOR\", \"END_SEND\", \"<6>\", \"<7>\", \"<8>\", \"NOP\", \"<10>\", \"UNARY_NEGATIVE\", \"UNARY_NOT\", \"<13>\", \"<14>\", \"UNARY_INVERT\", \"EXIT_INIT_CHECK\" }");
}

/// Generate opcode.opmap dict
pub fn genOpmap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .CACHE = 0, .POP_TOP = 1, .PUSH_NULL = 2, .INTERPRETER_EXIT = 3, .END_FOR = 4, .END_SEND = 5, .NOP = 9, .UNARY_NEGATIVE = 11, .UNARY_NOT = 12, .UNARY_INVERT = 15 }");
}

/// Generate opcode.cmp_op tuple
pub fn genCmpOp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"<\", \"<=\", \"==\", \"!=\", \">\", \">=\"}");
}

/// Generate opcode.hasarg list
pub fn genHasarg(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{}");
}

/// Generate opcode.hasconst list
pub fn genHasconst(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{ 100 }");
}

/// Generate opcode.hasname list
pub fn genHasname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{ 90, 91, 95, 96, 97, 98, 101, 106, 108, 109, 116 }");
}

/// Generate opcode.hasjrel list
pub fn genHasjrel(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{ 93, 110, 111, 112, 114, 115, 120, 149, 172 }");
}

/// Generate opcode.hasjabs list
pub fn genHasjabs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{}");
}

/// Generate opcode.haslocal list
pub fn genHaslocal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{ 124, 125, 126, 180 }");
}

/// Generate opcode.hascompare list
pub fn genHascompare(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{ 107 }");
}

/// Generate opcode.hasfree list
pub fn genHasfree(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{ 135, 136, 137, 138 }");
}

/// Generate opcode.hasexc list
pub fn genHasexc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{ 121 }");
}

/// Generate opcode.HAVE_ARGUMENT constant
pub fn genHaveArgument(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 90)");
}

/// Generate opcode.EXTENDED_ARG constant
pub fn genExtendedArg(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 144)");
}

/// Generate opcode.stack_effect(opcode, oparg=None, *, jump=None)
pub fn genStackEffect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate opcode._specialized_opmap dict
pub fn genSpecializedOpmap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate opcode._intrinsic_1_descs list
pub fn genIntrinsic1Descs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"INTRINSIC_1_INVALID\", \"INTRINSIC_PRINT\", \"INTRINSIC_IMPORT_STAR\", \"INTRINSIC_STOPITERATION_ERROR\", \"INTRINSIC_ASYNC_GEN_WRAP\", \"INTRINSIC_UNARY_POSITIVE\", \"INTRINSIC_LIST_TO_TUPLE\", \"INTRINSIC_TYPEVAR\", \"INTRINSIC_PARAMSPEC\", \"INTRINSIC_TYPEVARTUPLE\", \"INTRINSIC_SUBSCRIPT_GENERIC\", \"INTRINSIC_TYPEALIAS\" }");
}

/// Generate opcode._intrinsic_2_descs list
pub fn genIntrinsic2Descs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"INTRINSIC_2_INVALID\", \"INTRINSIC_PREP_RERAISE_STAR\", \"INTRINSIC_TYPEVAR_WITH_BOUND\", \"INTRINSIC_TYPEVAR_WITH_CONSTRAINTS\", \"INTRINSIC_SET_FUNCTION_TYPE_PARAMS\" }");
}
