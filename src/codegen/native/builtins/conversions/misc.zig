/// Miscellaneous conversion/creation builtins: complex(), object()
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const builder_mod = @import("codegen.builder");

// MIGRATED TO ZIGBUILDER

/// Helper: emit runtime.PyComplex.fromValue(expr) with guaranteed bracket matching
fn emitComplexFromValue(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    try self.emitCallCtx("runtime.PyComplex.fromValue", expr, struct {
        pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
            try s.genExpr(e);
        }
    }.f);
}

/// Helper: emit runtime.PyComplex.create(real, imag) with guaranteed bracket matching
fn emitComplexCreate(self: *NativeCodegen, real: ast.Node, imag: ast.Node) CodegenError!void {
    const Ctx = struct { r: ast.Node, i: ast.Node };
    try self.emitCallCtx("runtime.PyComplex.create", Ctx{ .r = real, .i = imag }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.genExpr(ctx.r);
            try s.emit(", ");
            try s.genExpr(ctx.i);
        }
    }.f);
}

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
        try emitComplexFromValue(self, args[0]);
        return;
    }

    // complex(real, imag)
    try emitComplexCreate(self, args[0], args[1]);
}

/// Generate code for object()
/// Creates a unique base object instance (used as sentinel values)
/// Each call creates a new unique instance by returning a struct with unique identity
pub fn genObject(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Generate a unique object using a struct that has unique identity per call
    // In Python, object() returns a base object that can be used as a sentinel
    // Wrap with PyValue.from() since createObject() returns *PyObject
    try self.emit("runtime.PyValue.from(runtime.createObject())");
}
