/// Shared module helper types and comptime generators for *_mod.zig files
const std = @import("std");
const ast = @import("ast");
pub const CodegenError = @import("main.zig").CodegenError;
pub const NativeCodegen = @import("main.zig").NativeCodegen;

/// Module handler function pointer type
pub const H = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// Generates a handler that emits a constant string
pub fn c(comptime v: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

/// Generates a handler that emits @as(i32, N)
pub fn I32(comptime n: comptime_int) H { return c(std.fmt.comptimePrint("@as(i32, {})", .{n})); }

/// Generates a handler that emits @as(i64, N)
pub fn I64(comptime n: comptime_int) H { return c(std.fmt.comptimePrint("@as(i64, {})", .{n})); }

/// Generates a handler that emits @as(u8, N)
pub fn U8(comptime n: comptime_int) H { return c(std.fmt.comptimePrint("@as(u8, {})", .{n})); }

/// Generates a handler that emits @as(u32, N)
pub fn U32(comptime n: comptime_int) H { return c(std.fmt.comptimePrint("@as(u32, {})", .{n})); }

/// Generates a handler that emits @as(f64, N)
pub fn F64(comptime n: comptime_float) H { return c(std.fmt.comptimePrint("@as(f64, {})", .{n})); }

/// Generates a handler that emits error.Name
pub fn err(comptime name: []const u8) H { return c("error." ++ name); }

/// Generates a handler that passes through first arg or emits default
pub fn pass(comptime default: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) try self.genExpr(args[0]) else try self.emit(default);
    } }.f;
}
