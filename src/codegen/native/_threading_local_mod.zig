/// Python _threading_local module - Internal threading.local support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _threading_local.local()
pub fn genLocal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _threading_local._localimpl class
pub fn genLocalimpl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .key = \"\", .dicts = .{}, .localargs = .{}, .localkwargs = .{}, .loclock = .{} }");
}

/// Generate _threading_local._localimpl_create_dict()
pub fn genLocalimplCreateDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate local.__init__()
pub fn genInit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate local.__getattribute__(name)
pub fn genGetattribute(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate local.__setattr__(name, value)
pub fn genSetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate local.__delattr__(name)
pub fn genDelattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}
