/// Python atexit module - Exit handlers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate atexit.register(func, *args, **kwargs) -> func
pub fn genRegister(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Return the function as-is (registration is no-op in AOT)
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate atexit.unregister(func) -> None
pub fn genUnregister(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate atexit._run_exitfuncs() -> None (internal)
pub fn genRunExitfuncs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate atexit._clear() -> None (internal)
pub fn genClear(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate atexit._ncallbacks() -> int (internal)
pub fn genNcallbacks(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}
