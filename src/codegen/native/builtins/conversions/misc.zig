/// Miscellaneous conversion/creation builtins: complex(), object()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Generate code for complex(real, imag)
/// Creates a complex number
pub fn genComplex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // complex() with no args returns 0j
        try self.emit("runtime.PyComplex.create(0.0, 0.0)");
        return;
    }

    if (args.len == 1) {
        // complex(x) - x can be a number or string
        try self.emit("runtime.PyComplex.fromValue(");
        try self.genExpr(args[0]);
        try self.emit(")");
        return;
    }

    // complex(real, imag)
    try self.emit("runtime.PyComplex.create(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate code for object()
/// Creates a unique base object instance (used as sentinel values)
/// Each call creates a new unique instance by returning a struct with unique identity
pub fn genObject(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Generate a unique object using a struct that has unique identity per call
    // In Python, object() returns a base object that can be used as a sentinel
    // We use runtime.createObject() which returns a unique *PyObject
    try self.emit("runtime.createObject()");
}
