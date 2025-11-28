/// Python marshal module - Internal Python object serialization
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate marshal.dump(value, file, version=4)
pub fn genDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate marshal.dumps(value, version=4)
pub fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const val = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = val; break :blk \"\"; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate marshal.load(file)
pub fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const file = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = file; break :blk null; }");
    } else {
        try self.emit("null");
    }
}

/// Generate marshal.loads(bytes)
pub fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const data = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = data; break :blk null; }");
    } else {
        try self.emit("null");
    }
}

/// Generate marshal.version constant
pub fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}
