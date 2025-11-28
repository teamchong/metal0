/// Python typing module - Type hints (no-ops for AOT compilation)
/// These are static type hints that have no runtime effect
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate typing.Optional[T] - just returns T
pub fn genOptional(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("?*runtime.PyObject");
        return;
    }
    try self.emit("?");
    try self.genExpr(args[0]);
}

/// Generate typing.List[T] - returns ArrayList type
pub fn genList(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("std.ArrayList(*runtime.PyObject)");
}

/// Generate typing.Dict[K, V] - returns HashMap type
pub fn genDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hashmap_helper.StringHashMap(*runtime.PyObject)");
}

/// Generate typing.Set[T] - returns HashSet type
pub fn genSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hashmap_helper.StringHashMap(void)");
}

/// Generate typing.Tuple[T, ...] - returns tuple struct
pub fn genTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {}");
}

/// Generate typing.Union[T, U] - returns generic type
pub fn genUnion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("*runtime.PyObject");
}

/// Generate typing.Any - returns PyObject
pub fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("*runtime.PyObject");
}

/// Generate typing.Callable[[Args], Return] - returns function pointer
pub fn genCallable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("*const fn () void");
}

/// Generate typing.TypeVar(name) - returns generic type placeholder
pub fn genTypeVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("type");
}

/// Generate typing.Generic[T] - base for generic classes
pub fn genGeneric(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("type");
}

/// Generate typing.cast(type, value) - no-op cast
pub fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    // cast(Type, value) just returns value - type checking is static
    try self.genExpr(args[1]);
}

/// Generate typing.get_type_hints(obj) - returns empty dict
pub fn genGetTypeHints(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hashmap_helper.StringHashMap(*runtime.PyObject).init(allocator)");
}
