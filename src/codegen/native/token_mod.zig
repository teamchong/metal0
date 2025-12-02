/// Python token module - Token constants and utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genI32(comptime n: comptime_int) ModuleHandler {
    return genConst(std.fmt.comptimePrint("@as(i32, {})", .{n}));
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ENDMARKER", genI32(0) }, .{ "NAME", genI32(1) }, .{ "NUMBER", genI32(2) }, .{ "STRING", genI32(3) },
    .{ "NEWLINE", genI32(4) }, .{ "INDENT", genI32(5) }, .{ "DEDENT", genI32(6) }, .{ "OP", genI32(54) },
    .{ "ERRORTOKEN", genI32(59) }, .{ "COMMENT", genI32(60) }, .{ "NL", genI32(61) }, .{ "ENCODING", genI32(62) },
    .{ "N_TOKENS", genI32(63) }, .{ "NT_OFFSET", genI32(256) },
    .{ "tok_name", genConst("metal0_runtime.PyDict(i32, []const u8).init()") },
    .{ "EXACT_TOKEN_TYPES", genConst("metal0_runtime.PyDict([]const u8, i32).init()") },
    .{ "ISTERMINAL", genIsTerm }, .{ "ISNONTERMINAL", genIsNonterm }, .{ "ISEOF", genIsEof },
});

fn genIsTerm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const x = "); try self.genExpr(args[0]); try self.emit("; break :blk x < 256; }"); } else try self.emit("false");
}
fn genIsNonterm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const x = "); try self.genExpr(args[0]); try self.emit("; break :blk x >= 256; }"); } else try self.emit("false");
}
fn genIsEof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const x = "); try self.genExpr(args[0]); try self.emit("; break :blk x == 0; }"); } else try self.emit("false");
}
