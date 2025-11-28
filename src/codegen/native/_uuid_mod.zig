/// Python _uuid module - Internal UUID support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _uuid.getnode()
pub fn genGetnode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate _uuid.generate_time_safe()
pub fn genGenerateTimeSafe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\\x00\" ** 16, @as(i32, 0) }");
}

/// Generate _uuid.UuidCreate()
pub fn genUuidCreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\x00\" ** 16");
}

/// Generate _uuid.has_uuid_generate_time_safe constant
pub fn genHasUuidGenerateTimeSafe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}
