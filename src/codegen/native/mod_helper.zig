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
pub fn I32(comptime n: comptime_int) H {
    @setEvalBranchQuota(100000);
    return c(std.fmt.comptimePrint("@as(i32, {})", .{n}));
}

/// Generates a handler that emits @as(i64, N)
pub fn I64(comptime n: comptime_int) H { return c(std.fmt.comptimePrint("@as(i64, {})", .{n})); }

/// Generates a handler that emits @as(i16, N)
pub fn I16(comptime n: comptime_int) H { return c(std.fmt.comptimePrint("@as(i16, {})", .{n})); }

/// Generates a handler that emits @as(u8, N)
pub fn U8(comptime n: comptime_int) H { return c(std.fmt.comptimePrint("@as(u8, {})", .{n})); }

/// Generates a handler that emits @as(u16, N)
pub fn U16(comptime n: comptime_int) H { return c(std.fmt.comptimePrint("@as(u16, {})", .{n})); }

/// Generates a handler that emits @as(u32, N)
pub fn U32(comptime n: comptime_int) H { return c(std.fmt.comptimePrint("@as(u32, {})", .{n})); }

/// Generates a handler that emits @as(i32, 0xNN) in hex format
pub fn hex32(comptime n: comptime_int) H { return c(std.fmt.comptimePrint("@as(i32, 0x{x})", .{n})); }

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

/// Emit a unique labeled block start and return the label ID for break
pub fn emitUniqueBlockStart(self: *NativeCodegen, prefix: []const u8) CodegenError!u64 {
    const id = self.block_label_counter;
    self.block_label_counter += 1;
    try self.emitFmt("{s}_{d}: {{ ", .{ prefix, id });
    return id;
}

/// Emit a break with unique label
pub fn emitBlockBreak(self: *NativeCodegen, prefix: []const u8, id: u64) CodegenError!void {
    try self.emitFmt("; break :{s}_{d} ", .{ prefix, id });
}
