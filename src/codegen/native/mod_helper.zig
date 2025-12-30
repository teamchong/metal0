/// Shared module helper types and comptime generators for *_mod.zig files
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
pub const CodegenError = @import("main.zig").CodegenError;
pub const NativeCodegen = @import("main.zig").NativeCodegen;
const expr_emitter = @import("expr_emitter.zig");

/// Module handler function pointer type
pub const H = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// Generates a handler that emits a constant string
pub fn c(comptime v: []const u8) H {
    return struct { pub fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
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
    const Ctx = struct { args: []ast.Node };
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len == 0) {
                try self.emit(ret);
                return;
            }
            // Generate: (__m{id}_discard: { _ = arg1; _ = arg2; break :__m{id}_discard default; })
            try self.withInlineBlock("discard", Ctx{ .args = args }, struct {
                fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
                    for (ctx.args, 0..) |arg, i| {
                        if (i > 0) try s.emit(" ");
                        try s.emit("_ = ");
                        try s.genExpr(arg);
                        if (i < ctx.args.len - 1) try s.emit(";");
                    }
                    try s.emitFmt("; break :{s} {s}", .{ label, ret });
                }
            }.emit);
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
        if (args.len > 0) {
            try self.emitCallCtx(b, args[0], struct {
                pub fn emit(s: *NativeCodegen, arg: ast.Node) CodegenError!void {
                    try s.emitCallCtx("@as", arg, struct {
                        pub fn inner(ss: *NativeCodegen, a: ast.Node) CodegenError!void {
                            try ss.emit("f64, ");
                            try ss.genExpr(a);
                        }
                    }.inner);
                }
            }.emit);
        } else try self.emit(d);
    } }.f;
}

/// Generates std.math.fn(@as(f64, arg)) or default
pub fn stdmath1(comptime fn_name: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) {
            try self.emitCallCtx("std.math." ++ fn_name, args[0], struct {
                pub fn emit(s: *NativeCodegen, arg: ast.Node) CodegenError!void {
                    try s.emitCallCtx("@as", arg, struct {
                        pub fn inner(ss: *NativeCodegen, a: ast.Node) CodegenError!void {
                            try ss.emit("f64, ");
                            try ss.genExpr(a);
                        }
                    }.inner);
                }
            }.emit);
        } else try self.emit(d);
    } }.f;
}

/// Generates std.math.fn(f64, @as(f64, arg)) or default
pub fn stdmathT(comptime fn_name: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) {
            try self.emitCallCtx("std.math." ++ fn_name, args[0], struct {
                pub fn emit(s: *NativeCodegen, arg: ast.Node) CodegenError!void {
                    try s.emit("f64, ");
                    try s.emitCallCtx("@as", arg, struct {
                        pub fn inner(ss: *NativeCodegen, a: ast.Node) CodegenError!void {
                            try ss.emit("f64, ");
                            try ss.genExpr(a);
                        }
                    }.inner);
                }
            }.emit);
        } else try self.emit(d);
    } }.f;
}

/// Generates std.math.fn(@as(f64, a), @as(f64, b)) or default
pub fn stdmath2(comptime fn_name: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len >= 2) {
            const Args = struct { a: ast.Node, b: ast.Node };
            try self.emitCallCtx("std.math." ++ fn_name, Args{ .a = args[0], .b = args[1] }, struct {
                pub fn emit(s: *NativeCodegen, ctx: Args) CodegenError!void {
                    try s.emitCallCtx("@as", ctx.a, struct {
                        pub fn inner(ss: *NativeCodegen, a: ast.Node) CodegenError!void {
                            try ss.emit("f64, ");
                            try ss.genExpr(a);
                        }
                    }.inner);
                    try s.emit(", ");
                    try s.emitCallCtx("@as", ctx.b, struct {
                        pub fn inner2(ss: *NativeCodegen, b: ast.Node) CodegenError!void {
                            try ss.emit("f64, ");
                            try ss.genExpr(b);
                        }
                    }.inner2);
                }
            }.emit);
        } else try self.emit(d);
    } }.f;
}

// === Operator helpers ===

/// Generates binary operator: (a op b) or default
pub fn binop(comptime op: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len >= 2) {
            const Args = struct { a: ast.Node, b: ast.Node };
            try self.withParensCtx(Args{ .a = args[0], .b = args[1] }, struct {
                pub fn emit(s: *NativeCodegen, ctx: Args) CodegenError!void {
                    try s.genExpr(ctx.a);
                    try s.emit(op);
                    try s.genExpr(ctx.b);
                }
            }.emit);
        } else try self.emit(d);
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
        if (args.len >= 2) {
            const Args = struct { a: ast.Node, b: ast.Node };
            try self.withParensCtx(Args{ .a = args[0], .b = args[1] }, struct {
                pub fn emit(s: *NativeCodegen, ctx: Args) CodegenError!void {
                    try s.genExpr(ctx.a);
                    try s.emit(op);
                    try s.emitCallCtx("@intCast", ctx.b, struct {
                        pub fn inner(ss: *NativeCodegen, b: ast.Node) CodegenError!void {
                            try ss.genExpr(b);
                        }
                    }.inner);
                }
            }.emit);
        } else try self.emit("@as(i64, 0)");
    } }.f;
}

/// Generates wrap: pre + arg + suf, or default
/// WARNING: If pre contains "blk:", this will cause label conflicts on nested calls.
/// Use wrapBlk() instead for labeled blocks.
pub fn wrap(comptime pre: []const u8, comptime suf: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit(pre); try self.genExpr(args[0]); try self.emit(suf); } else try self.emit(d);
    } }.f;
}

/// Generates wrap with unique block label: __m{id}_name: { const __v = arg; body break :__m{id}_name result; }
/// Use this instead of wrap() when you need a labeled block to avoid naming conflicts.
/// @param name: short identifier for the block (e.g., "sig", "ipaddr")
/// @param body: code using __v (the captured arg), WITHOUT the final break statement
/// @param result: expression to return from the block (can use __v)
/// @param d: default value when no args
pub fn wrapBlk(comptime name: []const u8, comptime body: []const u8, comptime result: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(d); return; }
        const label = try self.emitInlineBlockStart(name);
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; {s} break :{s} {s}; ", .{ body, label, result });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Generates discard block with unique label: __m{id}_name: { _ = arg; break :__m{id}_name result; }
/// Use for stubs that need to consume arg but return a constant
pub fn discardBlk(comptime name: []const u8, comptime result: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(d); return; }
        const label = try self.emitInlineBlockStart(name);
        try self.emit("_ = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} {s}; ", .{ label, result });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Generates struct construction with unique block: __m{id}_name: { const __v = arg; break :__m{id}_name .{ fields }; }
/// @param name: short identifier
/// @param fields: struct literal body, use __v for the captured arg (e.g., ".address = __v, .version = 4")
/// @param d: default struct literal
pub fn structBlk(comptime name: []const u8, comptime fields: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(d); return; }
        const label = try self.emitInlineBlockStart(name);
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} .{{ {s} }}; ", .{ label, fields });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Passthrough Nth argument (0-indexed) or default
pub fn passN(comptime n: usize, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > n) try self.genExpr(args[n]) else try self.emit(d);
    } }.f;
}

/// Generates wrap2: pre + arg0 + mid + arg1 + suf, or default (requires 2+ args)
/// WARNING: If pre contains "blk:", this will cause label conflicts. Use wrap2Blk() instead.
pub fn wrap2(comptime pre: []const u8, comptime mid: []const u8, comptime suf: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len >= 2) { try self.emit(pre); try self.genExpr(args[0]); try self.emit(mid); try self.genExpr(args[1]); try self.emit(suf); } else try self.emit(d);
    } }.f;
}

/// Generates wrap2 with unique block: __m{id}_name: { const __v0 = arg0; const __v1 = arg1; body break :__m{id}_name result; }
/// @param name: short identifier
/// @param body: code using __v0 and __v1, WITHOUT the final break statement
/// @param result: expression to return (can use __v0, __v1)
/// @param d: default when < 2 args
pub fn wrap2Blk(comptime name: []const u8, comptime body: []const u8, comptime result: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len < 2) { try self.emit(d); return; }
        const label = try self.emitInlineBlockStart(name);
        try self.emit("const __v0 = ");
        try self.genExpr(args[0]);
        try self.emit("; const __v1 = ");
        try self.genExpr(args[1]);
        try self.emitFmt("; {s} break :{s} {s}; ", .{ body, label, result });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Generates wrap3Blk with unique ID: captures 3 args as __v0, __v1, __v2, executes body, returns result
pub fn wrap3Blk(comptime name: []const u8, comptime body: []const u8, comptime result: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len < 3) { try self.emit(d); return; }
        const label = try self.emitInlineBlockStart(name);
        try self.emit("const __v0 = ");
        try self.genExpr(args[0]);
        try self.emit("; const __v1 = ");
        try self.genExpr(args[1]);
        try self.emit("; const __v2 = ");
        try self.genExpr(args[2]);
        try self.emitFmt("; {s} break :{s} {s}; ", .{ body, label, result });
        try self.emitInlineBlockEnd();
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
        if (args.len > 0) {
            try self.withParensCtx(args[0], struct {
                pub fn emit(s: *NativeCodegen, arg: ast.Node) CodegenError!void {
                    try s.withParensCtx(arg, struct {
                        pub fn inner(ss: *NativeCodegen, a: ast.Node) CodegenError!void {
                            try ss.genExpr(a);
                            try ss.emit(" & 0o170000");
                        }
                    }.inner);
                    try s.emit(" == " ++ expected);
                }
            }.emit);
        } else try self.emit("false");
    } }.f;
}

/// Generates wrapN: pre + arg[n] + suf, or default
pub fn wrapN(comptime n: usize, comptime pre: []const u8, comptime suf: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > n) { try self.emit(pre); try self.genExpr(args[n]); try self.emit(suf); } else try self.emit(d);
    } }.f;
}

/// Generates log: __m{id}_log: { const _m = arg; std.debug.print("LEVEL: {s}\n", .{_m}); break :__m{id}_log; }
pub fn logLevel(comptime level: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) return error.UnsupportedSyntax;
        const label = try self.emitInlineBlockStart("log");
        try self.emit("const _m = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; std.debug.print(\"{s}: {{s}}\\n\", .{{_m}}); break :{s}; ", .{ level, label });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Generates codec result: .{ arg, arg.len } or default tuple
pub fn codecResult(comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit(".{ "); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[0]); try self.emit(".len }"); } else try self.emit(d);
    } }.f;
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
        if (args.len == 0) return error.UnsupportedSyntax;
        const label = try self.emitInlineBlockStart("b64enc");
        try self.emit("const d = ");
        try self.genExpr(args[0]);
        try self.emit("; const len = std.base64." ++ encoder ++ ".Encoder.calcSize(d.len); const buf = __global_allocator.alloc(u8, len) catch break :");
        try self.emitFmt("{s} \"\"; break :{s} std.base64." ++ encoder ++ ".Encoder.encode(buf, d); ", .{ label, label });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Base64 decode using specified decoder
pub fn b64dec(comptime decoder: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) return error.UnsupportedSyntax;
        const label = try self.emitInlineBlockStart("b64dec");
        try self.emit("const d = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; const len = std.base64." ++ decoder ++ ".Decoder.calcSizeForSlice(d) catch break :{s} \"\"; const buf = __global_allocator.alloc(u8, len) catch break :{s} \"\"; std.base64." ++ decoder ++ ".Decoder.decode(buf, d) catch break :{s} \"\"; break :{s} buf; ", .{ label, label, label, label });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Stub that discards arg and returns result
pub fn stub(comptime result: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) return error.UnsupportedSyntax;
        const label = try self.emitInlineBlockStart("stub");
        try self.emit("_ = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} {s}; ", .{ label, result });
        try self.emitInlineBlockEnd();
    } }.f;
}

// === Hash helpers ===

/// Generates hash constructor: hashlib.name() with optional initial data
pub fn hashNew(comptime name: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) {
            const label = try self.emitInlineBlockStart("hash");
            try self.emit("var _h = hashlib." ++ name ++ "(); _h.update(");
            try self.genExpr(args[0]);
            try self.emitFmt("); break :{s} _h; ", .{label});
            try self.emitInlineBlockEnd();
        } else try self.emit("hashlib." ++ name ++ "()");
    } }.f;
}

/// Constant-time compare digest: returns true if both slices are equal
pub fn compareDigest() H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len < 2) return error.UnsupportedSyntax;
        const label = try self.emitInlineBlockStart("cmp");
        try self.emit("const _a = ");
        try self.genExpr(args[0]);
        try self.emit("; const _b = ");
        try self.genExpr(args[1]);
        try self.emitFmt("; if (_a.len != _b.len) break :{s} false; var _diff: u8 = 0; for (_a, _b) |a_byte, b_byte| {{ _diff |= a_byte ^ b_byte; }} break :{s} _diff == 0; ", .{ label, label });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Compare two strings with std.mem.order
pub fn memOrder() H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len < 2) { try self.emit("@as(i64, 0)"); return; }
        const Args = struct { a: ast.Node, b: ast.Node };
        try self.emitCallCtx("std.mem.order", Args{ .a = args[0], .b = args[1] }, struct {
            pub fn emit(s: *NativeCodegen, ctx: Args) CodegenError!void {
                try s.emit("u8, ");
                try s.genExpr(ctx.a);
                try s.emit(", ");
                try s.genExpr(ctx.b);
            }
        }.emit);
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

/// Check condition on arg: __m{id}_check: { const x = arg; break :__m{id}_check condition; }
pub fn checkCond(comptime cond: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) {
            const label = try self.emitInlineBlockStart("check");
            try self.emit("const x = ");
            try self.genExpr(args[0]);
            try self.emitFmt("; break :{s} {s}; ", .{ label, cond });
            try self.emitInlineBlockEnd();
        } else try self.emit("false");
    } }.f;
}

/// Debug print: std.debug.print(prefix ++ fmt, .{arg}) or default
pub fn debugPrint(comptime prefix: []const u8, comptime fmt: []const u8, comptime default: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(default); return; }
        try self.emit("runtime.print(\"" ++ prefix ++ fmt ++ "\\n\", .{"); try self.genExpr(args[0]); try self.emit("})");
    } }.f;
}

/// Buffer print: bufPrint to get string representation
pub fn bufPrint(comptime fmt: []const u8, comptime default: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(default); return; }
        const label = try self.emitInlineBlockStart("buf");
        try self.emitFmt("var buf: [4096]u8 = undefined; break :{s} std.fmt.bufPrint(&buf, \"{s}\", .{{", .{ label, fmt });
        try self.genExpr(args[0]);
        try self.emit("}) catch \"\"; ");
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Struct wrap: .{ .field = arg, ... } pattern
pub fn structField(comptime field: []const u8, comptime rest: []const u8, comptime default: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(default); return; }
        const label = try self.emitInlineBlockStart("struct");
        try self.emit("const _v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} .{{ .{s} = _v{s} }}; ", .{ label, field, rest });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Shift left: (1 << cast(arg)) pattern
pub fn shiftL(comptime pre: []const u8, comptime post: []const u8, comptime default: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(default); return; }
        try self.emit(pre); try self.genExpr(args[0]); try self.emit(post);
    } }.f;
}

// === Advanced Pattern Helpers (Maintainability Infrastructure) ===
//
// These helpers provide reusable code generation patterns with automatic unique ID management.
// All helpers use ZigBuilder API to generate unique labels and prevent shadowing issues.

/// Generates a list membership checker: for (items) |item| if (compare(__search, __item)) break :label true;
/// Use for functions like iskeyword that check if a value is in a compile-time list.
///
/// Example usage:
///   const keywords = "\"if\", \"for\", \"while\"";
///   const genIskeyword = listContains("iskw", keywords, "std.mem.eql(u8, __search, __item)");
///
/// @param name: block name identifier
/// @param list_items: comma-separated list items (e.g., "\"foo\", \"bar\"")
/// @param compare: comparison expression using __search and __item (e.g., "std.mem.eql(u8, __search, __item)")
pub fn listContains(comptime name: []const u8, comptime list_items: []const u8, comptime compare: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit("false"); return; }
        const label = try self.emitInlineBlockStart(name);
        try self.emit("const __search = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; const __items = [_][]const u8{{ {s} }}; for (__items) |__item| {{ if ({s}) break :{s} true; }} break :{s} false; ",
            .{ list_items, compare, label, label });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Generates optional unwrapping: if (opt) |val| expr else default
///
/// Example usage:
///   const genGetEnv = unwrapOptional("genv", "__v", "\"\"");  // Returns env var or empty string
///
/// @param name: block name identifier
/// @param expr: expression to evaluate using __v (the unwrapped value)
/// @param d: default value if optional is null
pub fn unwrapOptional(comptime name: []const u8, comptime expr: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(d); return; }
        const label = try self.emitInlineBlockStart(name);
        try self.emit("const __opt = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} if (__opt) |__v| {s} else {s}; ",
            .{ label, expr, d });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Generates try-with-default pattern: (expr) catch default
///
/// Example usage:
///   const genParseInt = tryOrDefault("pint", "std.fmt.parseInt(i64, __v, 10)", "0");
///
/// @param name: block name identifier
/// @param expr: expression that may fail, using __v (the captured arg)
/// @param d: default value on error
pub fn tryOrDefault(comptime name: []const u8, comptime expr: []const u8, comptime d: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(d); return; }
        const label = try self.emitInlineBlockStart(name);
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} ({s}) catch {s}; ",
            .{ label, expr, d });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Generates allocPrint call: try std.fmt.allocPrint(__global_allocator, fmt, .{arg})
///
/// Example usage:
///   const genHexStr = allocPrint("hex", "{x:0>8}");  // Format arg as 8-digit hex
///
/// @param name: block name identifier
/// @param fmt: format string (use {{}} for format specifiers)
pub fn allocPrint(comptime name: []const u8, comptime fmt: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit("\"\""); return; }
        const label = try self.emitInlineBlockStart(name);
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} try std.fmt.allocPrint(__global_allocator, \"{s}\", .{{__v}}); ",
            .{ label, fmt });
        try self.emitInlineBlockEnd();
    } }.f;
}

/// Generates conditional expression: if (condition) then_expr else else_expr
///
/// Example usage:
///   const genIsPositive = conditional("ispos", "__v > 0", "\"positive\"", "\"non-positive\"");
///
/// @param name: block name identifier
/// @param condition: boolean expression using __v
/// @param then_expr: expression if true (can use __v)
/// @param else_expr: expression if false (can use __v)
pub fn conditional(comptime name: []const u8, comptime condition: []const u8, comptime then_expr: []const u8, comptime else_expr: []const u8) H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(else_expr); return; }
        const label = try self.emitInlineBlockStart(name);
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} if ({s}) {s} else {s}; ",
            .{ label, condition, then_expr, else_expr });
        try self.emitInlineBlockEnd();
    } }.f;
}
