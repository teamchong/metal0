/// Python symtable module - Symbol table access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "symtable", genConst(".{ .name = \"<module>\", .type = \"module\", .lineno = 1, .is_optimized = false, .is_nested = false, .has_children = false, .has_exec = false, .has_import_star = false, .has_varargs = false, .has_varkeywords = false }") },
    .{ "SymbolTable", genConst(".{ .name = \"\", .type = \"module\", .id = 0 }") },
    .{ "Symbol", genConst(".{ .name = \"\", .is_referenced = false, .is_imported = false, .is_parameter = false, .is_global = false, .is_nonlocal = false, .is_declared_global = false, .is_local = false, .is_annotated = false, .is_free = false, .is_assigned = false, .is_namespace = false }") },
    .{ "Function", genConst(".{ .name = \"\", .type = \"function\", .id = 0 }") },
    .{ "Class", genConst(".{ .name = \"\", .type = \"class\", .id = 0 }") },
});
