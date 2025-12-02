/// Python tokenize module - Tokenizer for Python source
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "tokenize", genConst("metal0_runtime.PyList(@TypeOf(.{ .type = @as(i32, 0), .string = \"\", .start = .{ @as(i32, 0), @as(i32, 0) }, .end = .{ @as(i32, 0), @as(i32, 0) }, .line = \"\" })).init()") },
    .{ "generate_tokens", genConst("metal0_runtime.PyList(@TypeOf(.{ .type = @as(i32, 0), .string = \"\", .start = .{ @as(i32, 0), @as(i32, 0) }, .end = .{ @as(i32, 0), @as(i32, 0) }, .line = \"\" })).init()") },
    .{ "detect_encoding", genConst(".{ \"utf-8\", metal0_runtime.PyList([]const u8).init() }") },
    .{ "open", genOpen }, .{ "untokenize", genConst("\"\"") },
    .{ "TokenInfo", genConst(".{ .type = @as(i32, 0), .string = \"\", .start = .{ @as(i32, 0), @as(i32, 0) }, .end = .{ @as(i32, 0), @as(i32, 0) }, .line = \"\" }") },
    .{ "TokenError", genConst("error.TokenError") }, .{ "StopTokenizing", genConst("error.StopTokenizing") },
    .{ "ENDMARKER", genConst("@as(i32, 0)") }, .{ "NAME", genConst("@as(i32, 1)") }, .{ "NUMBER", genConst("@as(i32, 2)") }, .{ "STRING", genConst("@as(i32, 3)") },
    .{ "NEWLINE", genConst("@as(i32, 4)") }, .{ "INDENT", genConst("@as(i32, 5)") }, .{ "DEDENT", genConst("@as(i32, 6)") }, .{ "OP", genConst("@as(i32, 54)") },
    .{ "ERRORTOKEN", genConst("@as(i32, 59)") }, .{ "COMMENT", genConst("@as(i32, 60)") }, .{ "NL", genConst("@as(i32, 61)") }, .{ "ENCODING", genConst("@as(i32, 62)") }, .{ "N_TOKENS", genConst("@as(i32, 63)") },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; break :blk std.fs.cwd().openFile(path, .{}) catch null; }"); }
    else { try self.emit("@as(?std.fs.File, null)"); }
}
