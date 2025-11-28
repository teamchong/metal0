/// Python contextvars module - Context Variables
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// ContextVar
// ============================================================================

/// Generate contextvars.ContextVar(name, *, default=<missing>)
pub fn genContextVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const name = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .name = name, .value = null }; }");
    } else {
        try self.emit(".{ .name = \"\", .value = null }");
    }
}

// ============================================================================
// Token
// ============================================================================

/// Generate contextvars.Token - represents previous value for reset
pub fn genToken(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .var = null, .old_value = null }");
}

// ============================================================================
// Context
// ============================================================================

/// Generate contextvars.Context()
pub fn genContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .data = pyaot_runtime.PyDict([]const u8, ?anyopaque).init() }");
}

/// Generate contextvars.copy_context()
pub fn genCopy_context(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .data = pyaot_runtime.PyDict([]const u8, ?anyopaque).init() }");
}

// ============================================================================
// ContextVar Methods (for method call support)
// ============================================================================

/// Generate ContextVar.get(default=<missing>)
pub fn genContextVar_get(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]); // Return default
    } else {
        try self.emit("@as(?anyopaque, null)");
    }
}

/// Generate ContextVar.set(value)
pub fn genContextVar_set(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .var = null, .old_value = null }"); // Returns Token
}

/// Generate ContextVar.reset(token)
pub fn genContextVar_reset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// ============================================================================
// Context Methods
// ============================================================================

/// Generate Context.run(callable, *args, **kwargs)
pub fn genContext_run(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const callable = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk callable(); }");
    } else {
        try self.emit("@as(?anyopaque, null)");
    }
}

/// Generate Context.copy()
pub fn genContext_copy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genCopy_context(self, args);
}
