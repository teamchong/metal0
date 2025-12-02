/// Python tokenize module - Tokenizer for Python source
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genI(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "tokenize", genTokenList }, .{ "generate_tokens", genTokenList }, .{ "detect_encoding", genDetectEncoding },
    .{ "open", genOpen }, .{ "untokenize", genEmptyStr }, .{ "TokenInfo", genTokenInfo },
    .{ "TokenError", genTokenError }, .{ "StopTokenizing", genStopTokenizing },
    .{ "ENDMARKER", genI(0) }, .{ "NAME", genI(1) }, .{ "NUMBER", genI(2) }, .{ "STRING", genI(3) },
    .{ "NEWLINE", genI(4) }, .{ "INDENT", genI(5) }, .{ "DEDENT", genI(6) }, .{ "OP", genI(54) },
    .{ "ERRORTOKEN", genI(59) }, .{ "COMMENT", genI(60) }, .{ "NL", genI(61) }, .{ "ENCODING", genI(62) }, .{ "N_TOKENS", genI(63) },
});

fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genTokenList(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "metal0_runtime.PyList(@TypeOf(.{ .type = @as(i32, 0), .string = \"\", .start = .{ @as(i32, 0), @as(i32, 0) }, .end = .{ @as(i32, 0), @as(i32, 0) }, .line = \"\" })).init()"); }
fn genDetectEncoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"utf-8\", metal0_runtime.PyList([]const u8).init() }"); }
fn genTokenInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .type = @as(i32, 0), .string = \"\", .start = .{ @as(i32, 0), @as(i32, 0) }, .end = .{ @as(i32, 0), @as(i32, 0) }, .line = \"\" }"); }
fn genTokenError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.TokenError"); }
fn genStopTokenizing(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.StopTokenizing"); }

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; break :blk std.fs.cwd().openFile(path, .{}) catch null; }"); }
    else { try self.emit("@as(?std.fs.File, null)"); }
}
