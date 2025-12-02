/// Python dataclasses module - Data class decorators and functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "dataclass", genDataclass }, .{ "field", genField }, .{ "Field", genField },
    .{ "fields", genFields }, .{ "asdict", genAsdict }, .{ "astuple", genEmpty },
    .{ "make_dataclass", genMakeDataclass }, .{ "replace", genReplace }, .{ "is_dataclass", genFalse },
    .{ "MISSING", genMISSING }, .{ "KW_ONLY", genKW_ONLY }, .{ "FrozenInstanceError", genFrozenError },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genMISSING(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { _missing: bool = true }{}"); }
fn genKW_ONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { _kw_only: bool = true }{}"); }
fn genFrozenError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"FrozenInstanceError\""); }
fn genMakeDataclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { _is_dataclass: bool = true }"); }
fn genFields(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]struct { name: []const u8, type_: []const u8 }{}"); }
fn genAsdict(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "hashmap_helper.StringHashMap([]const u8).init(__global_allocator)"); }
fn genField(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { default: ?[]const u8 = null, default_factory: ?*anyopaque = null, repr: bool = true, hash: ?bool = null, init: bool = true, compare: bool = true, metadata: ?hashmap_helper.StringHashMap([]const u8) = null, kw_only: bool = false }{}"); }

fn genDataclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else try self.emit("struct { _is_dataclass: bool = true }{}");
}

fn genReplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else try self.emit("void{}");
}
