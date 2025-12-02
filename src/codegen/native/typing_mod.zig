/// Python typing module - Type hints (no-ops for AOT compilation)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Optional", genOptional }, .{ "List", genList }, .{ "Dict", genDict }, .{ "Set", genSet },
    .{ "Tuple", genStruct }, .{ "Union", genPyObj }, .{ "Any", genPyObj }, .{ "Callable", genCallable },
    .{ "TypeVar", genType }, .{ "Generic", genType }, .{ "cast", genCast }, .{ "get_type_hints", genGetTypeHints },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genList(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "std.ArrayList(*runtime.PyObject)"); }
fn genDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "hashmap_helper.StringHashMap(*runtime.PyObject)"); }
fn genSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "hashmap_helper.StringHashMap(void)"); }
fn genStruct(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct {}"); }
fn genPyObj(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "*runtime.PyObject"); }
fn genCallable(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "*const fn () void"); }
fn genType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "type"); }
fn genGetTypeHints(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)"); }

fn genOptional(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("?*runtime.PyObject"); return; }
    try self.emit("?"); try self.genExpr(args[0]);
}

fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.genExpr(args[1]); // cast(Type, value) just returns value
}
