/// Python _pickle module - C accelerator for pickle (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _pickle.dumps(obj, protocol=None, *, fix_imports=True)
pub fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const obj = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = obj; break :blk \"\"; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate _pickle.dump(obj, file, protocol=None, *, fix_imports=True)
pub fn genDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _pickle.loads(data, *, fix_imports=True, encoding="ASCII", errors="strict")
pub fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const data = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = data; break :blk null; }");
    } else {
        try self.emit("null");
    }
}

/// Generate _pickle.load(file, *, fix_imports=True, encoding="ASCII", errors="strict")
pub fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _pickle.Pickler(file, protocol=None, *, fix_imports=True)
pub fn genPickler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .protocol = 4 }");
}

/// Generate _pickle.Unpickler(file, *, fix_imports=True, encoding="ASCII", errors="strict")
pub fn genUnpickler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

// Protocol constants
pub fn genHIGHEST_PROTOCOL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genDEFAULT_PROTOCOL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

// Exceptions
pub fn genPickleError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.PickleError");
}

pub fn genPicklingError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.PicklingError");
}

pub fn genUnpicklingError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UnpicklingError");
}
