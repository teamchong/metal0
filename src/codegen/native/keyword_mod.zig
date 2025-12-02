/// Python keyword module - Test whether strings are Python keywords
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

const kwlist = "\"False\", \"None\", \"True\", \"and\", \"as\", \"assert\", \"async\", \"await\", \"break\", \"class\", \"continue\", \"def\", \"del\", \"elif\", \"else\", \"except\", \"finally\", \"for\", \"from\", \"global\", \"if\", \"import\", \"in\", \"is\", \"lambda\", \"nonlocal\", \"not\", \"or\", \"pass\", \"raise\", \"return\", \"try\", \"while\", \"with\", \"yield\"";
const softkwlist = "\"_\", \"case\", \"match\", \"type\"";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "iskeyword", genIskeyword }, .{ "issoftkeyword", genIssoftkeyword },
    .{ "kwlist", h.c("metal0_runtime.PyList([]const u8).fromSlice(&[_][]const u8{ " ++ kwlist ++ " })") },
    .{ "softkwlist", h.c("metal0_runtime.PyList([]const u8).fromSlice(&[_][]const u8{ " ++ softkwlist ++ " })") },
});

fn genIskeyword(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("false"); return; }
    try self.emit("blk: { const s = "); try self.genExpr(args[0]);
    try self.emit("; const keywords = [_][]const u8{ " ++ kwlist ++ " }; for (keywords) |kw| { if (std.mem.eql(u8, s, kw)) break :blk true; } break :blk false; }");
}

fn genIssoftkeyword(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("false"); return; }
    try self.emit("blk: { const s = "); try self.genExpr(args[0]);
    try self.emit("; const softkw = [_][]const u8{ " ++ softkwlist ++ " }; for (softkw) |kw| { if (std.mem.eql(u8, s, kw)) break :blk true; } break :blk false; }");
}
