/// Python keyword module - Test whether strings are Python keywords
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate keyword.iskeyword(s)
pub fn genIskeyword(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const s = ");
        try self.genExpr(args[0]);
        try self.emit("; const keywords = [_][]const u8{ \"False\", \"None\", \"True\", \"and\", \"as\", \"assert\", \"async\", \"await\", \"break\", \"class\", \"continue\", \"def\", \"del\", \"elif\", \"else\", \"except\", \"finally\", \"for\", \"from\", \"global\", \"if\", \"import\", \"in\", \"is\", \"lambda\", \"nonlocal\", \"not\", \"or\", \"pass\", \"raise\", \"return\", \"try\", \"while\", \"with\", \"yield\" }; for (keywords) |kw| { if (std.mem.eql(u8, s, kw)) break :blk true; } break :blk false; }");
    } else {
        try self.emit("false");
    }
}

/// Generate keyword.kwlist
pub fn genKwlist(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).fromSlice(&[_][]const u8{ \"False\", \"None\", \"True\", \"and\", \"as\", \"assert\", \"async\", \"await\", \"break\", \"class\", \"continue\", \"def\", \"del\", \"elif\", \"else\", \"except\", \"finally\", \"for\", \"from\", \"global\", \"if\", \"import\", \"in\", \"is\", \"lambda\", \"nonlocal\", \"not\", \"or\", \"pass\", \"raise\", \"return\", \"try\", \"while\", \"with\", \"yield\" })");
}

/// Generate keyword.softkwlist (Python 3.10+)
pub fn genSoftkwlist(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).fromSlice(&[_][]const u8{ \"_\", \"case\", \"match\", \"type\" })");
}

/// Generate keyword.issoftkeyword(s)
pub fn genIssoftkeyword(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const s = ");
        try self.genExpr(args[0]);
        try self.emit("; const softkw = [_][]const u8{ \"_\", \"case\", \"match\", \"type\" }; for (softkw) |kw| { if (std.mem.eql(u8, s, kw)) break :blk true; } break :blk false; }");
    } else {
        try self.emit("false");
    }
}
