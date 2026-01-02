/// Python ctypes module - Foreign function library
/// MIGRATED TO ZIGBUILDER
/// Generates code that uses runtime.ctypes for actual FFI
const std = @import("std");
const ast = @import("analysis.ast");
const m = @import("mod_helper.zig");
const H = m.H;

// === Comptime generators for C type conversions ===

/// Generate ctypes integer type: @as(runtime.ctypes.@"type_name", @intCast(arg))
fn cInt(comptime name: []const u8) H {
    return m.wrap("@as(runtime.ctypes.@\"" ++ name ++ "\", @intCast(", "))", "@as(runtime.ctypes.@\"" ++ name ++ "\", 0)");
}

/// Generate ctypes float type: @as(runtime.ctypes.@"type_name", @floatCast(arg))
fn cFloat(comptime name: []const u8, comptime def: []const u8) H {
    return m.wrap("@as(runtime.ctypes.@\"" ++ name ++ "\", @floatCast(", "))", "@as(runtime.ctypes.@\"" ++ name ++ "\", " ++ def ++ ")");
}

/// Generate ctypes direct cast: @as(runtime.ctypes.@"type_name", arg)
fn cDirect(comptime name: []const u8, comptime def: []const u8) H {
    return m.wrap("@as(runtime.ctypes.@\"" ++ name ++ "\", ", ")", "@as(runtime.ctypes.@\"" ++ name ++ "\", " ++ def ++ ")");
}

/// Generate truncated int: @as(T, @truncate(@as(i64/u64, arg)))
fn cTrunc(comptime name: []const u8, comptime cast: []const u8) H {
    return m.wrap("@as(runtime.ctypes.@\"" ++ name ++ "\", @truncate(@as(" ++ cast ++ ", ", ")))", "@as(runtime.ctypes.@\"" ++ name ++ "\", 0)");
}

pub const Funcs = std.StaticStringMap(H).initComptime(.{
    // pythonapi - access to Python C API symbols
    .{ "pythonapi", m.c("runtime.ctypes.PythonAPI{}") },
    // DLLs - actual dynamic library loading
    .{ "CDLL", genCDLL }, .{ "WinDLL", genCDLL }, .{ "OleDLL", genCDLL }, .{ "PyDLL", genCDLL },
    // C types - use runtime.ctypes type aliases
    .{ "c_bool", genCBool },
    .{ "c_char", genCChar },
    .{ "c_wchar", cInt("c_wchar") },
    .{ "c_byte", cTrunc("c_byte", "i64") },
    .{ "c_ubyte", cTrunc("c_ubyte", "u64, @intCast(") },
    .{ "c_short", cTrunc("c_short", "i64") },
    .{ "c_ushort", cTrunc("c_ushort", "u64, @intCast(") },
    .{ "c_int", cTrunc("c_int", "i64") },
    .{ "c_uint", cTrunc("c_uint", "u64, @intCast(") },
    .{ "c_long", cInt("c_long") },
    .{ "c_ulong", cInt("c_ulong") },
    .{ "c_longlong", cInt("c_longlong") },
    .{ "c_ulonglong", cInt("c_ulonglong") },
    .{ "c_size_t", cInt("c_size_t") },
    .{ "c_ssize_t", cInt("c_ssize_t") },
    .{ "c_float", cFloat("c_float", "0.0") },
    .{ "c_double", cDirect("c_double", "0.0") },
    .{ "c_longdouble", cDirect("c_longdouble", "0.0") },
    // Pointer types
    .{ "c_char_p", cDirect("c_char_p", "null") },
    .{ "c_wchar_p", cDirect("c_wchar_p", "null") },
    .{ "c_void_p", genCVoidP },
    // Structures
    .{ "Structure", m.c("struct {}{}") },
    .{ "Union", m.c("union {}{}") },
    .{ "BigEndianStructure", m.c("struct {}{}") },
    .{ "LittleEndianStructure", m.c("struct {}{}") },
    // Arrays/pointers
    .{ "Array", m.c("[]anyopaque") },
    .{ "POINTER", m.c("*anyopaque") },
    .{ "pointer", m.wrap("@as(*anyopaque, @ptrCast(&", "))", "@as(?*anyopaque, null)") },
    // Utility
    .{ "sizeof", m.wrap("@sizeOf(@TypeOf(", "))", "0") },
    .{ "alignment", m.wrap("@alignOf(@TypeOf(", "))", "1") },
    .{ "addressof", m.wrap("@intFromPtr(&", ")", "0") },
    .{ "byref", m.wrap("&", "", "null") },
    .{ "cast", m.wrap("@as(*anyopaque, @ptrCast(", "))", "null") },
    .{ "create_string_buffer", genCreateStringBuffer },
    .{ "create_unicode_buffer", genCreateUnicodeBuffer },
    .{ "get_errno", m.c("runtime.ctypes.get_errno()") },
    .{ "set_errno", m.wrap("runtime.ctypes.set_errno(", ")", "runtime.ctypes.set_errno(0)") },
    .{ "get_last_error", m.c("runtime.ctypes.get_errno()") },
    .{ "set_last_error", m.wrap("runtime.ctypes.set_errno(", ")", "runtime.ctypes.set_errno(0)") },
    .{ "memmove", genMemmove },
    .{ "memset", genMemset },
    .{ "string_at", m.wrap2("runtime.ctypes.string_at(", ", ", ")", "\"\"") },
    .{ "wstring_at", m.wrap2("runtime.ctypes.string_at(", ", ", ")", "\"\"") },
    // Function types (stubs - actual implementation needs type analysis)
    .{ "CFUNCTYPE", m.c("*const fn() callconv(.c) void") },
    .{ "WINFUNCTYPE", m.c("*const fn() callconv(.c) void") },
    .{ "PYFUNCTYPE", m.c("*const fn() callconv(.c) void") },
});

// === Complex handlers ===

const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;
const ZigValue = builder_mod.ZigValue;

fn genCDLL(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const path_val = try self.captureExpr(args[0]);
        try b.withLabeledBlock("__cdll", struct {
            fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: ZigValue) !void {
                try bld.emitConstWithValue("__path", "", ctx, "");
                try scope.breakWithRaw("(runtime.ctypes.CDLL.init(__global_allocator, __path) catch unreachable)");
            }
        }.emit, path_val);
    } else {
        try b.emitRaw("(runtime.ctypes.CDLL.init(__global_allocator, \"\") catch unreachable)");
    }
    try self.flushBuilder();
}

fn genCBool(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_bool\", ");
        try self.genExpr(args[0]);
        try self.emit(" != 0)");
    } else try self.emit("@as(runtime.ctypes.@\"c_bool\", false)");
}

fn genCChar(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_char\", @truncate(@as(usize, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else try self.emit("@as(runtime.ctypes.@\"c_char\", 0)");
}

fn genCVoidP(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_void_p\", @ptrFromInt(@as(usize, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else try self.emit("@as(runtime.ctypes.@\"c_void_p\", null)");
}

fn genMemmove(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len >= 3) {
        const Ctx = struct { a0: ast.Node, a1: ast.Node, a2: ast.Node };
        try self.emitCallCtx("runtime.ctypes.memmove", Ctx{ .a0 = args[0], .a1 = args[1], .a2 = args[2] }, struct {
            pub fn f(s: *m.NativeCodegen, ctx: Ctx) m.CodegenError!void {
                try s.emitCallCtx("@ptrCast", ctx.a0, struct {
                    pub fn g(s2: *m.NativeCodegen, e: ast.Node) m.CodegenError!void {
                        try s2.genExpr(e);
                    }
                }.g);
                try s.emit(", ");
                try s.emitCallCtx("@ptrCast", ctx.a1, struct {
                    pub fn g(s2: *m.NativeCodegen, e: ast.Node) m.CodegenError!void {
                        try s2.genExpr(e);
                    }
                }.g);
                try s.emit(", ");
                try s.genExpr(ctx.a2);
            }
        }.f);
    } else try self.emit("{}");
}

fn genMemset(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len >= 3) {
        const Ctx = struct { a0: ast.Node, a1: ast.Node, a2: ast.Node };
        try self.emitCallCtx("runtime.ctypes.memset", Ctx{ .a0 = args[0], .a1 = args[1], .a2 = args[2] }, struct {
            pub fn f(s: *m.NativeCodegen, ctx: Ctx) m.CodegenError!void {
                try s.emitCallCtx("@ptrCast", ctx.a0, struct {
                    pub fn g(s2: *m.NativeCodegen, e: ast.Node) m.CodegenError!void {
                        try s2.genExpr(e);
                    }
                }.g);
                try s.emit(", ");
                try s.genExpr(ctx.a1);
                try s.emit(", ");
                try s.genExpr(ctx.a2);
            }
        }.f);
    } else try self.emit("{}");
}

/// Generate create_string_buffer call
/// Python: create_string_buffer("abc") -> buffer of len("abc")
/// Python: create_string_buffer(10) -> buffer of size 10
fn genCreateStringBuffer(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len > 0) {
        const arg = args[0];
        // Check if argument is a string literal - use its length
        if (arg == .constant and arg.constant.value == .string) {
            var buf: [32]u8 = undefined;
            const len_str = std.fmt.bufPrint(&buf, "{}", .{arg.constant.value.string.len}) catch "256";
            try self.emit("(runtime.ctypes.create_string_buffer(__global_allocator, ");
            try self.emit(len_str);
            try self.emit(") catch &[_]u8{})");
        } else {
            // Assume it's a size - generate code that extracts length if string, else use directly
            try self.emit("(runtime.ctypes.create_string_buffer(__global_allocator, @as(usize, @intCast(");
            try self.genExpr(arg);
            try self.emit("))) catch &[_]u8{})");
        }
    } else {
        try self.emit("(runtime.ctypes.create_string_buffer(__global_allocator, 256) catch &[_]u8{})");
    }
}

/// Generate create_unicode_buffer call
/// Python: create_unicode_buffer("abc") -> buffer of len("abc")
/// Python: create_unicode_buffer(10) -> buffer of size 10
fn genCreateUnicodeBuffer(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len > 0) {
        const arg = args[0];
        // Check if argument is a string literal - use its length
        if (arg == .constant and arg.constant.value == .string) {
            var buf: [32]u8 = undefined;
            const len_str = std.fmt.bufPrint(&buf, "{}", .{arg.constant.value.string.len}) catch "256";
            try self.emit("(runtime.ctypes.create_unicode_buffer(__global_allocator, ");
            try self.emit(len_str);
            try self.emit(") catch &[_]u32{})");
        } else {
            // Assume it's a size - generate code that extracts length if string, else use directly
            try self.emit("(runtime.ctypes.create_unicode_buffer(__global_allocator, @as(usize, @intCast(");
            try self.genExpr(arg);
            try self.emit("))) catch &[_]u32{})");
        }
    } else {
        try self.emit("(runtime.ctypes.create_unicode_buffer(__global_allocator, 256) catch &[_]u32{})");
    }
}
