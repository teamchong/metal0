/// Python dbm module - Interfaces to Unix databases
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Main Functions
// ============================================================================

/// Generate dbm.open(file, flag='r', mode=0o666)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .path = path, .data = pyaot_runtime.PyDict([]const u8, []const u8).init() }; }");
    } else {
        try self.emit(".{ .path = \"\", .data = pyaot_runtime.PyDict([]const u8, []const u8).init() }");
    }
}

/// Generate dbm.whichdb(filename)
pub fn genWhichdb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[]const u8, \"dbm.dumb\")");
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.DbmError");
}

// ============================================================================
// dbm.dumb functions
// ============================================================================

pub fn genDumb_open(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genOpen(self, args);
}

pub fn genDumb_error(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genError(self, args);
}

// ============================================================================
// dbm.gnu functions
// ============================================================================

pub fn genGnu_open(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genOpen(self, args);
}

pub fn genGnu_error(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genError(self, args);
}

// ============================================================================
// dbm.ndbm functions
// ============================================================================

pub fn genNdbm_open(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genOpen(self, args);
}

pub fn genNdbm_error(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genError(self, args);
}
