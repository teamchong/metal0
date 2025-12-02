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

/// Generates a handler that discards all args and returns a default value
/// Use this for stub functions that need to consume their arguments
pub fn discard(comptime ret: []const u8) H {
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len == 0) {
                try self.emit(ret);
                return;
            }
            // Generate: blk: { _ = arg1; _ = arg2; break :blk default; }
            const id = emitUniqueBlockStart(self, "discard") catch 0;
            for (args, 0..) |arg, i| {
                // Emit: _ = arg; (semicolon only needed before next arg, emitBlockBreak adds one)
                if (i > 0) try self.emit(" ");
                try self.emit("_ = ");
                try self.genExpr(arg);
                if (i < args.len - 1) try self.emit(";"); // semicolon between args, not after last
            }
            // emitBlockBreak adds "; break :label " so no trailing semicolon needed on last arg
            emitBlockBreak(self, "discard", id) catch {};
            try self.emit(ret);
            try self.emit("; }");
        }
    }.f;
}

/// Generates a handler that passes through first arg or emits default
pub fn pass(comptime default: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) try self.genExpr(args[0]) else try self.emit(default);
    } }.f;
}

// === Math helpers ===

/// Generates @builtin(@as(f64, arg)) or default
pub fn builtin1(comptime b: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit(b ++ "(@as(f64, "); try self.genExpr(args[0]); try self.emit("))"); } else try self.emit(d);
    } }.f;
}

/// Generates std.math.fn(@as(f64, arg)) or default
pub fn stdmath1(comptime fn_name: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit("std.math." ++ fn_name ++ "(@as(f64, "); try self.genExpr(args[0]); try self.emit("))"); } else try self.emit(d);
    } }.f;
}

/// Generates std.math.fn(f64, @as(f64, arg)) or default
pub fn stdmathT(comptime fn_name: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit("std.math." ++ fn_name ++ "(f64, @as(f64, "); try self.genExpr(args[0]); try self.emit("))"); } else try self.emit(d);
    } }.f;
}

/// Generates std.math.fn(@as(f64, a), @as(f64, b)) or default
pub fn stdmath2(comptime fn_name: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len >= 2) { try self.emit("std.math." ++ fn_name ++ "(@as(f64, "); try self.genExpr(args[0]); try self.emit("), @as(f64, "); try self.genExpr(args[1]); try self.emit("))"); } else try self.emit(d);
    } }.f;
}

// === Operator helpers ===

/// Generates binary operator: (a op b) or default
pub fn binop(comptime op: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len >= 2) { try self.emit("("); try self.genExpr(args[0]); try self.emit(op); try self.genExpr(args[1]); try self.emit(")"); } else try self.emit(d);
    } }.f;
}

/// Generates unary: pre + arg + suf
pub fn unary(comptime pre: []const u8, comptime suf: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit(pre); try self.genExpr(args[0]); try self.emit(suf); } else try self.emit("@as(i64, 0)");
    } }.f;
}

/// Generates shift: (a op @intCast(b)) or default
pub fn shift(comptime op: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len >= 2) { try self.emit("("); try self.genExpr(args[0]); try self.emit(op); try self.emit("@intCast("); try self.genExpr(args[1]); try self.emit("))"); } else try self.emit("@as(i64, 0)");
    } }.f;
}

/// Generates wrap: pre + arg + suf, or default
pub fn wrap(comptime pre: []const u8, comptime suf: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit(pre); try self.genExpr(args[0]); try self.emit(suf); } else try self.emit(d);
    } }.f;
}

/// Passthrough Nth argument (0-indexed) or default
pub fn passN(comptime n: usize, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > n) try self.genExpr(args[n]) else try self.emit(d);
    } }.f;
}

/// Generates wrap2: pre + arg0 + mid + arg1 + suf, or default (requires 2+ args)
pub fn wrap2(comptime pre: []const u8, comptime mid: []const u8, comptime suf: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len >= 2) { try self.emit(pre); try self.genExpr(args[0]); try self.emit(mid); try self.genExpr(args[1]); try self.emit(suf); } else try self.emit(d);
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
