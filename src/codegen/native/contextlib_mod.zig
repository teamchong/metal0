/// Python contextlib module - Context managers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate contextlib.contextmanager decorator
/// Turns a generator into a context manager
pub fn genContextmanager(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // contextmanager is a decorator - pass through the function
    _ = args;
    try self.emit("struct { pub fn wrap(f: anytype) @TypeOf(f) { return f; } }.wrap");
}

/// Generate contextlib.suppress(*exceptions)
/// Returns a context manager that suppresses exceptions
pub fn genSuppress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Returns a no-op context manager struct
    try self.emit("struct { pub fn __enter__(self: @This()) void { _ = __self; } pub fn __exit__(self: @This(), exc: anytype) bool { _ = __self; _ = exc; return true; } }{}");
}

/// Generate contextlib.redirect_stdout(new_target)
/// Redirects stdout to new target
pub fn genRedirectStdout(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Placeholder - stdout redirection is complex in AOT
    try self.emit("struct { pub fn __enter__(self: @This()) void { _ = __self; } pub fn __exit__(self: @This(), exc: anytype) void { _ = __self; _ = exc; } }{}");
}

/// Generate contextlib.redirect_stderr(new_target)
pub fn genRedirectStderr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { pub fn __enter__(self: @This()) void { _ = __self; } pub fn __exit__(self: @This(), exc: anytype) void { _ = __self; _ = exc; } }{}");
}

/// Generate contextlib.closing(thing)
/// Returns context manager that closes thing on exit
pub fn genClosing(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    // Return the object itself - closing happens via __exit__
    try self.genExpr(args[0]);
}

/// Generate contextlib.nullcontext(enter_result=None)
/// No-op context manager
pub fn genNullcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("null");
    }
}

/// Generate contextlib.ExitStack()
/// Stack of context managers
pub fn genExitStack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Returns a simple struct that can push/pop context managers
    try self.emit("struct { stack: std.ArrayList(*anyopaque) = .{}, pub fn enter_context(__self: *@This(), cm: anytype) void { _ = __self; _ = cm; } pub fn close(__self: *@This()) void { __self.stack.deinit(__global_allocator); } }{}");
}

// Function map for module_functions.zig
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "contextmanager", genContextmanager },
    .{ "suppress", genSuppress },
    .{ "redirect_stdout", genRedirectStdout },
    .{ "redirect_stderr", genRedirectStderr },
    .{ "closing", genClosing },
    .{ "nullcontext", genNullcontext },
    .{ "ExitStack", genExitStack },
});
