/// Python sre_compile module - Internal support module for sre
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate sre_compile.compile(p, flags=0)
pub fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const pattern = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = pattern; break :blk .{ .pattern = \"\", .flags = 0, .code = &[_]u32{}, .groups = 0 }; }");
    } else {
        try self.emit(".{ .pattern = \"\", .flags = 0, .code = &[_]u32{}, .groups = 0 }");
    }
}

/// Generate sre_compile.isstring(obj)
pub fn genIsstring(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate sre_compile.MAXCODE constant
pub fn genMaxcode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 65535)");
}

/// Generate sre_compile.MAXGROUPS constant
pub fn genMaxgroups(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 100)");
}

/// Generate sre_compile._code(p, flags)
pub fn genCode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u32{}");
}

/// Generate sre_compile._compile(code, pattern, flags)
pub fn genInternalCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate sre_compile._compile_charset(charset, flags, code)
pub fn genCompileCharset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate sre_compile._optimize_charset(charset, iscased, fixup, fixes)
pub fn genOptimizeCharset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate sre_compile._generate_overlap_table(prefix)
pub fn genGenerateOverlapTable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]i32{}");
}

/// Generate sre_compile._compile_info(code, pattern, flags)
pub fn genCompileInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate sre_compile.SRE_FLAG_TEMPLATE constant
pub fn genSreFlagTemplate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 1)");
}

/// Generate sre_compile.SRE_FLAG_IGNORECASE constant
pub fn genSreFlagIgnorecase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 2)");
}

/// Generate sre_compile.SRE_FLAG_LOCALE constant
pub fn genSreFlagLocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 4)");
}

/// Generate sre_compile.SRE_FLAG_MULTILINE constant
pub fn genSreFlagMultiline(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 8)");
}

/// Generate sre_compile.SRE_FLAG_DOTALL constant
pub fn genSreFlagDotall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 16)");
}

/// Generate sre_compile.SRE_FLAG_UNICODE constant
pub fn genSreFlagUnicode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 32)");
}

/// Generate sre_compile.SRE_FLAG_VERBOSE constant
pub fn genSreFlagVerbose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 64)");
}

/// Generate sre_compile.SRE_FLAG_DEBUG constant
pub fn genSreFlagDebug(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 128)");
}

/// Generate sre_compile.SRE_FLAG_ASCII constant
pub fn genSreFlagAscii(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 256)");
}
