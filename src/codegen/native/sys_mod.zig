/// Python sys module - system-specific parameters and functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate sys.argv -> list of command line arguments
pub fn genArgv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("sys_argv_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _os_args = std.os.argv;\n");
    try self.emitIndent();
    try self.emit("var _argv = std.ArrayList([]const u8).init(allocator);\n");
    try self.emitIndent();
    try self.emit("for (_os_args) |arg| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_argv.append(allocator, std.mem.span(arg)) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :sys_argv_blk _argv.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate sys.exit(code=0) -> noreturn
pub fn genExit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("sys_exit_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _code: u8 = ");
    if (args.len > 0) {
        try self.emit("@intCast(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.process.exit(_code);\n");
    try self.emitIndent();
    try self.emit("break :sys_exit_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate sys.path -> list of module search paths
pub fn genPath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{\".\" }");
}

/// Generate sys.platform -> string identifying the platform
pub fn genPlatform(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Detect platform at compile time
    try self.emit("sys_platform_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _builtin = @import(\"builtin\");\n");
    try self.emitIndent();
    try self.emit("break :sys_platform_blk switch (_builtin.os.tag) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".linux => \"linux\",\n");
    try self.emitIndent();
    try self.emit(".macos => \"darwin\",\n");
    try self.emitIndent();
    try self.emit(".windows => \"win32\",\n");
    try self.emitIndent();
    try self.emit(".freebsd => \"freebsd\",\n");
    try self.emitIndent();
    try self.emit("else => \"unknown\",\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate sys.version -> Python version string
pub fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"3.12.0 (metal0 compiled)\"");
}

/// Generate sys.version_info -> version info tuple
pub fn genVersionInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .major = 3, .minor = 12, .micro = 0, .releaselevel = \"final\", .serial = 0 }");
}

/// Generate sys.executable -> path to Python executable
pub fn genExecutable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("sys_exec_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _args = std.os.argv;\n");
    try self.emitIndent();
    try self.emit("if (_args.len > 0) break :sys_exec_blk std.mem.span(_args[0]);\n");
    try self.emitIndent();
    try self.emit("break :sys_exec_blk \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate sys.stdin -> file object
pub fn genStdin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("std.io.getStdIn()");
}

/// Generate sys.stdout -> file object
pub fn genStdout(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("std.io.getStdOut()");
}

/// Generate sys.stderr -> file object
pub fn genStderr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("std.io.getStdErr()");
}

/// Generate sys.maxsize -> largest positive integer
pub fn genMaxsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, std.math.maxInt(i64))");
}

/// Generate sys.byteorder -> byte order ("little" or "big")
pub fn genByteorder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("sys_byteorder_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _native = @import(\"builtin\").cpu.arch.endian();\n");
    try self.emitIndent();
    try self.emit("break :sys_byteorder_blk if (_native == .little) \"little\" else \"big\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate sys.getsizeof(obj) -> int
pub fn genGetsizeof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("@as(i64, @intCast(@sizeOf(@TypeOf(");
    try self.genExpr(args[0]);
    try self.emit("))))");
}

/// Generate sys.getrecursionlimit() -> int
pub fn genGetrecursionlimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 1000)");
}

/// Generate sys.setrecursionlimit(limit) -> None
pub fn genSetrecursionlimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // No-op in compiled code - stack size is determined at compile/link time
    try self.emit("{}");
}

/// Generate sys.getdefaultencoding() -> string
pub fn genGetdefaultencoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"utf-8\"");
}

/// Generate sys.getfilesystemencoding() -> string
pub fn genGetfilesystemencoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"utf-8\"");
}

/// Generate sys.intern(string) -> string (no-op in AOT)
pub fn genIntern(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    // In AOT compilation, string interning is a no-op
    try self.genExpr(args[0]);
}

/// Generate sys.modules -> dict of loaded modules
pub fn genModules(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hashmap_helper.StringHashMap(*runtime.PyObject).init(allocator)");
}
