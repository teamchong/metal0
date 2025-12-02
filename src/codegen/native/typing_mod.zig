/// Python typing module - Type hints (no-ops for AOT compilation)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Optional", genOptional }, .{ "List", h.c("std.ArrayList(*runtime.PyObject)") },
    .{ "Dict", h.c("hashmap_helper.StringHashMap(*runtime.PyObject)") },
    .{ "Set", h.c("hashmap_helper.StringHashMap(void)") }, .{ "Tuple", h.c("struct {}") },
    .{ "Union", h.c("*runtime.PyObject") }, .{ "Any", h.c("*runtime.PyObject") },
    .{ "Callable", h.c("*const fn () void") }, .{ "TypeVar", h.c("type") },
    .{ "Generic", h.c("type") }, .{ "cast", genCast },
    .{ "get_type_hints", h.c("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)") },
});

fn genOptional(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("?*runtime.PyObject"); return; }
    try self.emit("?"); try self.genExpr(args[0]);
}

fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.genExpr(args[1]); // cast(Type, value) just returns value
}
