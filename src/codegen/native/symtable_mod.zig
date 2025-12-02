/// Python symtable module - Symbol table access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "symtable", genSymtable }, .{ "SymbolTable", genSymbolTable },
    .{ "Symbol", genSymbol }, .{ "Function", genFunction }, .{ "Class", genClass },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }

fn genSymtable(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"<module>\", .type = \"module\", .lineno = 1, .is_optimized = false, .is_nested = false, .has_children = false, .has_exec = false, .has_import_star = false, .has_varargs = false, .has_varkeywords = false }"); }
fn genSymbolTable(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .type = \"module\", .id = 0 }"); }
fn genSymbol(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .is_referenced = false, .is_imported = false, .is_parameter = false, .is_global = false, .is_nonlocal = false, .is_declared_global = false, .is_local = false, .is_annotated = false, .is_free = false, .is_assigned = false, .is_namespace = false }"); }
fn genFunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .type = \"function\", .id = 0 }"); }
fn genClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .type = \"class\", .id = 0 }"); }
