/// Python _pydecimal module - Pure Python decimal implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _pydecimal.Decimal(value=0, context=None)
pub fn genDecimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const v = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = v; break :blk .{ .sign = 0, .int = 0, .exp = 0, .is_special = false }; }");
    } else {
        try self.emit(".{ .sign = 0, .int = 0, .exp = 0, .is_special = false }");
    }
}

/// Generate _pydecimal.Context(prec=None, rounding=None, Emin=None, Emax=None, capitals=None, clamp=None, flags=None, traps=None)
pub fn genContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }");
}

/// Generate _pydecimal.localcontext(ctx=None, **kwargs)
pub fn genLocalcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }");
}

/// Generate _pydecimal.getcontext()
pub fn genGetcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }");
}

/// Generate _pydecimal.setcontext(context)
pub fn genSetcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}
