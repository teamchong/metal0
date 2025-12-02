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

/// Generates wrap3: pre + arg0 + mid1 + arg1 + mid2 + arg2 + suf, or default (requires 3+ args)
pub fn wrap3(comptime pre: []const u8, comptime mid1: []const u8, comptime mid2: []const u8, comptime suf: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len >= 3) { try self.emit(pre); try self.genExpr(args[0]); try self.emit(mid1); try self.genExpr(args[1]); try self.emit(mid2); try self.genExpr(args[2]); try self.emit(suf); } else try self.emit(d);
    } }.f;
}

/// Generates type test: ((arg & mask) == expected) for stat module
pub fn typeTest(comptime expected: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit("(("); try self.genExpr(args[0]); try self.emit(" & 0o170000) == " ++ expected ++ ")"); } else try self.emit("false");
    } }.f;
}

/// Generates wrapN: pre + arg[n] + suf, or default
pub fn wrapN(comptime n: usize, comptime pre: []const u8, comptime suf: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > n) { try self.emit(pre); try self.genExpr(args[n]); try self.emit(suf); } else try self.emit(d);
    } }.f;
}

/// Generates log: blk: { const _m = arg; std.debug.print("LEVEL: {s}\n", .{_m}); break :blk; }
pub fn logLevel(comptime level: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) return;
        try self.emit("blk: { const _m = "); try self.genExpr(args[0]);
        try self.emit("; std.debug.print(\"" ++ level ++ ": {s}\\n\", .{_m}); break :blk; }");
    } }.f;
}

/// Generates codec result: .{ arg, arg.len } or default tuple
pub fn codecResult(comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit(".{ "); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[0]); try self.emit(".len }"); } else try self.emit(d);
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

// === Complex number helpers (cmath) ===

/// Generates complex from @builtin: .{ .re = @builtin(arg), .im = 0.0 }
pub fn complexBuiltin(comptime b: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(".{ .re = " ++ d ++ ", .im = 0.0 }"); return; }
        try self.emit(".{ .re = " ++ b ++ "(@as(f64, @floatFromInt("); try self.genExpr(args[0]); try self.emit("))), .im = 0.0 }");
    } }.f;
}

/// Generates complex from std.math: .{ .re = std.math.fn(arg), .im = 0.0 }
pub fn complexStdMath(comptime fn_name: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(".{ .re = " ++ d ++ ", .im = 0.0 }"); return; }
        try self.emit(".{ .re = std.math." ++ fn_name ++ "(@as(f64, @floatFromInt("); try self.genExpr(args[0]); try self.emit("))), .im = 0.0 }");
    } }.f;
}

// === Base64 helpers ===

/// Base64 encode using specified encoder
pub fn b64enc(comptime encoder: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) return;
        try self.emit("blk: { const d = "); try self.genExpr(args[0]);
        try self.emit("; const len = std.base64." ++ encoder ++ ".Encoder.calcSize(d.len); const buf = __global_allocator.alloc(u8, len) catch break :blk \"\"; break :blk std.base64." ++ encoder ++ ".Encoder.encode(buf, d); }");
    } }.f;
}

/// Base64 decode using specified decoder
pub fn b64dec(comptime decoder: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) return;
        try self.emit("blk: { const d = "); try self.genExpr(args[0]);
        try self.emit("; const len = std.base64." ++ decoder ++ ".Decoder.calcSizeForSlice(d) catch break :blk \"\"; const buf = __global_allocator.alloc(u8, len) catch break :blk \"\"; std.base64." ++ decoder ++ ".Decoder.decode(buf, d) catch break :blk \"\"; break :blk buf; }");
    } }.f;
}

/// Stub that discards arg and returns result
pub fn stub(comptime result: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) return;
        try self.emit("blk: { _ = "); try self.genExpr(args[0]); try self.emit("; break :blk " ++ result ++ "; }");
    } }.f;
}

// === Hash helpers ===

/// Generates hash constructor: hashlib.name() with optional initial data
pub fn hashNew(comptime name: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit("(blk: { var _h = hashlib." ++ name ++ "(); _h.update("); try self.genExpr(args[0]); try self.emit("); break :blk _h; })"); } else try self.emit("hashlib." ++ name ++ "()");
    } }.f;
}

/// Constant-time compare digest: returns true if both slices are equal
pub fn compareDigest() H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len < 2) return;
        try self.emit("blk: { const _a = "); try self.genExpr(args[0]); try self.emit("; const _b = "); try self.genExpr(args[1]);
        try self.emit("; if (_a.len != _b.len) break :blk false; var _diff: u8 = 0; for (_a, _b) |a_byte, b_byte| { _diff |= a_byte ^ b_byte; } break :blk _diff == 0; }");
    } }.f;
}

/// Compare two strings with std.mem.order
pub fn memOrder() H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len < 2) { try self.emit("@as(i64, 0)"); return; }
        try self.emit("std.mem.order(u8, "); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")");
    } }.f;
}

// === Unicode helpers ===

/// Character function: label: { const c = arg[0]; body }
pub fn charFunc(comptime label: []const u8, comptime default: []const u8, comptime body: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(default); return; }
        try self.emit(label ++ ": { const c = "); try self.genExpr(args[0]); try self.emit("[0]; " ++ body ++ " }");
    } }.f;
}

/// Check condition on arg: blk: { const x = arg; break :blk condition; }
pub fn checkCond(comptime cond: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit("blk: { const x = "); try self.genExpr(args[0]); try self.emit("; break :blk " ++ cond ++ "; }"); } else try self.emit("false");
    } }.f;
}

/// Debug print: std.debug.print(prefix ++ fmt, .{arg}) or default
pub fn debugPrint(comptime prefix: []const u8, comptime fmt: []const u8, comptime default: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(default); return; }
        try self.emit("std.debug.print(\"" ++ prefix ++ fmt ++ "\\n\", .{"); try self.genExpr(args[0]); try self.emit("})");
    } }.f;
}

/// Buffer print: bufPrint to get string representation
pub fn bufPrint(comptime fmt: []const u8, comptime default: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(default); return; }
        try self.emit("blk: { var buf: [4096]u8 = undefined; break :blk std.fmt.bufPrint(&buf, \"" ++ fmt ++ "\", .{"); try self.genExpr(args[0]); try self.emit("}) catch \"\"; }");
    } }.f;
}

/// Struct wrap: .{ .field = arg, ... } pattern
pub fn structField(comptime field: []const u8, comptime rest: []const u8, comptime default: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(default); return; }
        try self.emit("blk: { const _v = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ ." ++ field ++ " = _v" ++ rest ++ " }; }");
    } }.f;
}

/// Shift left: (1 << cast(arg)) pattern
pub fn shiftL(comptime pre: []const u8, comptime post: []const u8, comptime default: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(default); return; }
        try self.emit(pre); try self.genExpr(args[0]); try self.emit(post);
    } }.f;
}
