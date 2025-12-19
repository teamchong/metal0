/// Python fractions module - Rational number arithmetic
/// MIGRATED TO ZIGBUILDER
/// Uses runtime.Fraction to avoid monomorphization explosion from inline struct emission
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Fraction", genFraction },
    .{ "gcd", h.wrap2Blk("gcd", "var _a: i64 = @intCast(__v0); var _b: i64 = @intCast(__v1); if (_a < 0) _a = -_a; if (_b < 0) _b = -_b; while (_b != 0) { const t = _b; _b = @mod(_a, _b); _a = t; }", "_a", "@as(i64, 1)") },
});

fn genFraction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    // Use runtime.Fraction instead of inline struct - compiles ONCE, not per call
    try b.write("runtime.Fraction");
    if (args.len == 0) {
        // Type reference only (R = fractions.Fraction) - just emit the type
        // The caller (assign.zig) should handle emitting "const R = " prefix
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    } else if (args.len == 1) {
        try b.write(".init(");
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.write(", 1)");
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
    } else if (args.len >= 2) {
        try b.write(".init(");
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.write(", ");
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
        try self.genExpr(args[1]);
        {
            const b3 = try self.getBuilder();
            try b3.write(")");
            const output3 = b3.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output3);
        }
    }
}
