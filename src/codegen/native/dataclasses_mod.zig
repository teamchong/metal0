/// Python dataclasses module - Data class decorators and functions
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dataclass", genDataclass }, .{ "field", h.c("struct { default: ?[]const u8 = null, default_factory: ?*anyopaque = null, repr: bool = true, hash: ?bool = null, init: bool = true, compare: bool = true, metadata: ?hashmap_helper.StringHashMap([]const u8) = null, kw_only: bool = false }{}") },
    .{ "Field", h.c("struct { default: ?[]const u8 = null, default_factory: ?*anyopaque = null, repr: bool = true, hash: ?bool = null, init: bool = true, compare: bool = true, metadata: ?hashmap_helper.StringHashMap([]const u8) = null, kw_only: bool = false }{}") },
    .{ "fields", h.c("&[_]struct { name: []const u8, type_: []const u8 }{}") },
    .{ "asdict", h.c("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)") },
    .{ "astuple", h.c(".{}") },
    .{ "make_dataclass", h.c("struct { _is_dataclass: bool = true }") },
    .{ "replace", genReplace }, .{ "is_dataclass", h.c("false") },
    .{ "MISSING", h.c("struct { _missing: bool = true }{}") },
    .{ "KW_ONLY", h.c("struct { _kw_only: bool = true }{}") },
    .{ "FrozenInstanceError", h.c("\"FrozenInstanceError\"") },
});

fn genDataclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("struct { _is_dataclass: bool = true }{}");
}

fn genReplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("void{}");
}
