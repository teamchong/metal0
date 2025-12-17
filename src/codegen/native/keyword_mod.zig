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

const genIskeyword = h.listContains("iskw", kwlist, "std.mem.eql(u8, __search, __item)");

const genIssoftkeyword = h.listContains("issk", softkwlist, "std.mem.eql(u8, __search, __item)");
