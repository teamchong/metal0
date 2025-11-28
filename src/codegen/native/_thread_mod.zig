/// Python _thread module - Low-level threading primitives
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Thread Functions
// ============================================================================

/// Generate _thread.start_new_thread(function, args[, kwargs])
pub fn genStart_new_thread(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const func = ");
        try self.genExpr(args[0]);
        try self.emit("; const thread = std.Thread.spawn(.{}, func, .{}) catch break :blk @as(i64, -1); break :blk @as(i64, @intFromPtr(thread)); }");
    } else {
        try self.emit("@as(i64, -1)");
    }
}

/// Generate _thread.interrupt_main(signum=signal.SIGINT)
pub fn genInterrupt_main(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _thread.exit()
pub fn genExit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("return");
}

/// Generate _thread.allocate_lock()
pub fn genAllocate_lock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .mutex = std.Thread.Mutex{} }");
}

/// Generate _thread.get_ident()
pub fn genGet_ident(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, @intFromPtr(std.Thread.getCurrentId()))");
}

/// Generate _thread.get_native_id()
pub fn genGet_native_id(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, @intFromPtr(std.Thread.getCurrentId()))");
}

/// Generate _thread.stack_size([size])
pub fn genStack_size(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate _thread.TIMEOUT_MAX
pub fn genTIMEOUT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 4294967.0)"); // ~49.7 days in seconds
}

// ============================================================================
// Lock Type
// ============================================================================

/// Generate _thread.LockType
pub fn genLockType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{ .mutex = std.Thread.Mutex{} })");
}

/// Generate _thread.RLock
pub fn genRLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .mutex = std.Thread.Mutex{}, .count = 0, .owner = null }");
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ThreadError");
}
