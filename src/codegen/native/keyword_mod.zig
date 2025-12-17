/// Python keyword module - Test whether strings are Python keywords
const std = @import("std");
const h = @import("mod_helper.zig");

const kwlist = "\"False\", \"None\", \"True\", \"and\", \"as\", \"assert\", \"async\", \"await\", \"break\", \"class\", \"continue\", \"def\", \"del\", \"elif\", \"else\", \"except\", \"finally\", \"for\", \"from\", \"global\", \"if\", \"import\", \"in\", \"is\", \"lambda\", \"nonlocal\", \"not\", \"or\", \"pass\", \"raise\", \"return\", \"try\", \"while\", \"with\", \"yield\"";
const softkwlist = "\"_\", \"case\", \"match\", \"type\"";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "iskeyword", genIskeyword },
    .{ "issoftkeyword", genIssoftkeyword },
    .{ "kwlist", h.c("(try runtime.NativeList.fromStringSlice(__global_allocator, &[_][]const u8{ " ++ kwlist ++ " }))") },
    .{ "softkwlist", h.c("(try runtime.NativeList.fromStringSlice(__global_allocator, &[_][]const u8{ " ++ softkwlist ++ " }))") },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genIskeyword(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("false"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_iskw: {{ const s = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const keywords = [_][]const u8{ " ++ kwlist ++ " }; for (keywords) |kw| { if (std.mem.eql(u8, s, kw)) break :__m");
    try self.emitFmt("{d}_iskw true; }} break :__m{d}_iskw false; }})", .{ id, id });
}

fn genIssoftkeyword(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("false"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_issk: {{ const s = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const softkw = [_][]const u8{ " ++ softkwlist ++ " }; for (softkw) |kw| { if (std.mem.eql(u8, s, kw)) break :__m");
    try self.emitFmt("{d}_issk true; }} break :__m{d}_issk false; }})", .{ id, id });
}
