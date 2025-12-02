/// Python dataclasses module - Data class decorators and functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "dataclass", genDataclass }, .{ "field", genConst("struct { default: ?[]const u8 = null, default_factory: ?*anyopaque = null, repr: bool = true, hash: ?bool = null, init: bool = true, compare: bool = true, metadata: ?hashmap_helper.StringHashMap([]const u8) = null, kw_only: bool = false }{}") },
    .{ "Field", genConst("struct { default: ?[]const u8 = null, default_factory: ?*anyopaque = null, repr: bool = true, hash: ?bool = null, init: bool = true, compare: bool = true, metadata: ?hashmap_helper.StringHashMap([]const u8) = null, kw_only: bool = false }{}") },
    .{ "fields", genConst("&[_]struct { name: []const u8, type_: []const u8 }{}") },
    .{ "asdict", genConst("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)") },
    .{ "astuple", genConst(".{}") },
    .{ "make_dataclass", genConst("struct { _is_dataclass: bool = true }") },
    .{ "replace", genReplace }, .{ "is_dataclass", genConst("false") },
    .{ "MISSING", genConst("struct { _missing: bool = true }{}") },
    .{ "KW_ONLY", genConst("struct { _kw_only: bool = true }{}") },
    .{ "FrozenInstanceError", genConst("\"FrozenInstanceError\"") },
});

fn genDataclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("struct { _is_dataclass: bool = true }{}");
}

fn genReplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("void{}");
}
