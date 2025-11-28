/// Python plistlib module - Apple plist file handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate plistlib.load(fp, *, fmt=None, dict_type=dict)
pub fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate plistlib.loads(data, *, fmt=None, dict_type=dict)
pub fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate plistlib.dump(value, fp, *, fmt=FMT_XML, sort_keys=True, skipkeys=False)
pub fn genDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate plistlib.dumps(value, *, fmt=FMT_XML, sort_keys=True, skipkeys=False)
pub fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate plistlib.UID class (unique identifier for keyed archive)
pub fn genUID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const data = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .data = data }; }");
    } else {
        try self.emit(".{ .data = @as(i64, 0) }");
    }
}

// ============================================================================
// Format constants
// ============================================================================

pub fn genFMT_XML(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genFMT_BINARY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

// ============================================================================
// Deprecated classes (for backwards compatibility)
// ============================================================================

/// Generate plistlib.Dict class (deprecated)
pub fn genDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate plistlib.Data class (deprecated, use bytes instead)
pub fn genData(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genInvalidFileException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.InvalidFileException");
}

// ============================================================================
// Deprecated functions (for backwards compatibility)
// ============================================================================

/// Generate plistlib.readPlist(pathOrFile) - deprecated
pub fn genReadPlist(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate plistlib.writePlist(value, pathOrFile) - deprecated
pub fn genWritePlist(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate plistlib.readPlistFromBytes(data) - deprecated
pub fn genReadPlistFromBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate plistlib.writePlistToBytes(value) - deprecated
pub fn genWritePlistToBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}
