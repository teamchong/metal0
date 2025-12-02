/// Python typing module - Type hints (no-ops for AOT compilation)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Optional", genOptional }, .{ "List", genConst("std.ArrayList(*runtime.PyObject)") },
    .{ "Dict", genConst("hashmap_helper.StringHashMap(*runtime.PyObject)") },
    .{ "Set", genConst("hashmap_helper.StringHashMap(void)") }, .{ "Tuple", genConst("struct {}") },
    .{ "Union", genConst("*runtime.PyObject") }, .{ "Any", genConst("*runtime.PyObject") },
    .{ "Callable", genConst("*const fn () void") }, .{ "TypeVar", genConst("type") },
    .{ "Generic", genConst("type") }, .{ "cast", genCast },
    .{ "get_type_hints", genConst("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)") },
});

fn genOptional(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("?*runtime.PyObject"); return; }
    try self.emit("?"); try self.genExpr(args[0]);
}

fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.genExpr(args[1]); // cast(Type, value) just returns value
}
