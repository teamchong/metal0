/// Python _compat_pickle module - Pickle compatibility mappings for Python 2/3
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _compat_pickle.NAME_MAPPING dict
pub fn genNAME_MAPPING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _compat_pickle.IMPORT_MAPPING dict
pub fn genIMPORT_MAPPING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _compat_pickle.REVERSE_NAME_MAPPING dict
pub fn genREVERSE_NAME_MAPPING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _compat_pickle.REVERSE_IMPORT_MAPPING dict
pub fn genREVERSE_IMPORT_MAPPING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}
