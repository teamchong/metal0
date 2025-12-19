/// Miscellaneous conversion/creation builtins: complex(), object()
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const builder_mod = @import("codegen.builder");

/// Generate code for complex(real, imag)
/// Creates a complex number
pub fn genComplex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // complex() with no args returns 0j
        const b = try self.getBuilder();
        try b.write("runtime.PyComplex.create(0.0, 0.0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    if (args.len == 1) {
        // complex(x) - x can be a number or string
        {
            const b = try self.getBuilder();
            try b.write("runtime.PyComplex.fromValue(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(")");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        return;
    }

    // complex(real, imag)
    {
        const b = try self.getBuilder();
        try b.write("runtime.PyComplex.create(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.write(", ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[1]);
    {
        const b = try self.getBuilder();
        try b.write(")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for object()
/// Creates a unique base object instance (used as sentinel values)
/// Each call creates a new unique instance by returning a struct with unique identity
pub fn genObject(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Generate a unique object using a struct that has unique identity per call
    // In Python, object() returns a base object that can be used as a sentinel
    // We use runtime.createObject() which returns a unique *PyObject
    const b = try self.getBuilder();
    try b.write("runtime.createObject()");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
