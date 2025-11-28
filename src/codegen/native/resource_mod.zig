/// Python resource module - Unix resource usage and limits
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate resource.getrusage(who) - return resource usage
pub fn genGetrusage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Return a struct with ru_utime, ru_stime, etc.
    try self.emit(".{ .ru_utime = 0.0, .ru_stime = 0.0, .ru_maxrss = 0, .ru_ixrss = 0, .ru_idrss = 0, .ru_isrss = 0, .ru_minflt = 0, .ru_majflt = 0, .ru_nswap = 0, .ru_inblock = 0, .ru_oublock = 0, .ru_msgsnd = 0, .ru_msgrcv = 0, .ru_nsignals = 0, .ru_nvcsw = 0, .ru_nivcsw = 0 }");
}

/// Generate resource.getrlimit(resource) - return (soft, hard) limits
pub fn genGetrlimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i64, -1), @as(i64, -1) }");
}

/// Generate resource.setrlimit(resource, limits) - set resource limits
pub fn genSetrlimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate resource.prlimit(pid, resource, limits) - get/set process resource limits
pub fn genPrlimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i64, -1), @as(i64, -1) }");
}

/// Generate resource.getpagesize() - return system page size
pub fn genGetpagesize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 4096)");
}

// ============================================================================
// Resource type constants (who argument for getrusage)
// ============================================================================

pub fn genRUSAGE_SELF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genRUSAGE_CHILDREN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -1)");
}

pub fn genRUSAGE_BOTH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -2)");
}

pub fn genRUSAGE_THREAD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

// ============================================================================
// Resource limit constants (resource argument for getrlimit/setrlimit)
// ============================================================================

pub fn genRLIMIT_CPU(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genRLIMIT_FSIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genRLIMIT_DATA(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genRLIMIT_STACK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genRLIMIT_CORE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genRLIMIT_RSS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genRLIMIT_NPROC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

pub fn genRLIMIT_NOFILE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 7)");
}

pub fn genRLIMIT_MEMLOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genRLIMIT_AS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 9)");
}

pub fn genRLIMIT_LOCKS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 10)");
}

pub fn genRLIMIT_SIGPENDING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 11)");
}

pub fn genRLIMIT_MSGQUEUE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 12)");
}

pub fn genRLIMIT_NICE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 13)");
}

pub fn genRLIMIT_RTPRIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 14)");
}

pub fn genRLIMIT_RTTIME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 15)");
}

pub fn genRLIM_INFINITY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, -1)");
}
