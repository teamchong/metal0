/// Python sys module - system-specific parameters and functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "argv", genArgv },
    .{ "exit", genExit },
    .{ "path", genPath },
    .{ "platform", genPlatform },
    .{ "version", genVersion },
    .{ "version_info", genVersionInfo },
    .{ "executable", genExecutable },
    .{ "stdin", genStdin },
    .{ "stdout", genStdout },
    .{ "stderr", genStderr },
    .{ "maxsize", genMaxsize },
    .{ "byteorder", genByteorder },
    .{ "getsizeof", genGetsizeof },
    .{ "getrecursionlimit", genGetrecursionlimit },
    .{ "setrecursionlimit", genSetrecursionlimit },
    .{ "getdefaultencoding", genGetdefaultencoding },
    .{ "getfilesystemencoding", genGetfilesystemencoding },
    .{ "intern", genIntern },
    .{ "modules", genModules },
    .{ "getrefcount", genGetrefcount },
    .{ "exc_info", genExcInfo },
    .{ "get_coroutine_origin_tracking_depth", genGetCoroutineOriginTrackingDepth },
    .{ "set_coroutine_origin_tracking_depth", genSetCoroutineOriginTrackingDepth },
    .{ "flags", genFlags },
    .{ "float_info", genFloatInfo },
    .{ "int_info", genIntInfo },
    .{ "hash_info", genHashInfo },
    .{ "prefix", genPrefix },
    .{ "exec_prefix", genExecPrefix },
    .{ "base_prefix", genBasePrefix },
    .{ "base_exec_prefix", genBaseExecPrefix },
    .{ "implementation", genImplementation },
    .{ "hexversion", genHexversion },
    .{ "api_version", genApiVersion },
    .{ "copyright", genCopyright },
    .{ "builtin_module_names", genBuiltinModuleNames },
    .{ "displayhook", genDisplayhook },
    .{ "excepthook", genExcepthook },
    .{ "settrace", genSettrace },
    .{ "gettrace", genGettrace },
    .{ "setprofile", genSetprofile },
    .{ "getprofile", genGetprofile },
    .{ "get_int_max_str_digits", genGetIntMaxStrDigits },
    .{ "set_int_max_str_digits", genSetIntMaxStrDigits },
});

/// Generate sys.argv -> list of command line arguments
pub fn genArgv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("(sys_argv_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _os_args = std.os.argv;\n");
    try self.emitIndent();
    try self.emit("var _argv: std.ArrayList([]const u8) = .{};\n");
    try self.emitIndent();
    try self.emit("for (_os_args) |arg| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_argv.append(__global_allocator, std.mem.span(arg)) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :sys_argv_blk _argv.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("})");
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
/// Uses i128 to allow arithmetic like sys.maxsize + 1 without overflow
pub fn genMaxsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i128, std.math.maxInt(i64))");
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
    try self.emit("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)");
}

/// Generate sys.getrefcount(obj) -> int
pub fn genGetrefcount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // In AOT compilation, reference counting is not used
    try self.emit("@as(i64, 1)");
}

/// Generate sys.exc_info() -> (type, value, traceback)
pub fn genExcInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ null, null, null }");
}

/// Generate sys.get_coroutine_origin_tracking_depth() -> int
pub fn genGetCoroutineOriginTrackingDepth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate sys.set_coroutine_origin_tracking_depth(depth) -> None
pub fn genSetCoroutineOriginTrackingDepth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate sys.flags -> struct with interpreter flags
pub fn genFlags(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Wrap in parentheses to allow field access: (struct{...}{}).field
    try self.emit("(struct { debug: i64 = 0, optimize: i64 = 0, inspect: i64 = 0, interactive: i64 = 0, verbose: i64 = 0, quiet: i64 = 0, dont_write_bytecode: i64 = 0, no_user_site: i64 = 0, no_site: i64 = 0, ignore_environment: i64 = 0, hash_randomization: i64 = 1, isolated: i64 = 0, bytes_warning: i64 = 0, warn_default_encoding: i64 = 0, safe_path: i64 = 0, int_max_str_digits: i64 = 4300 }{})");
}

/// Generate sys.float_info -> float info struct
pub fn genFloatInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Wrap in parentheses to allow field access: (struct{...}{}).field
    try self.emit("(struct { max: f64 = 1.7976931348623157e+308, max_exp: i64 = 1024, max_10_exp: i64 = 308, min: f64 = 2.2250738585072014e-308, min_exp: i64 = -1021, min_10_exp: i64 = -307, dig: i64 = 15, mant_dig: i64 = 53, epsilon: f64 = 2.220446049250313e-16, radix: i64 = 2, rounds: i64 = 1 }{})");
}

/// Generate sys.int_info -> int info struct
pub fn genIntInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Wrap in parentheses to allow field access: (struct{...}{}).field
    try self.emit("(struct { bits_per_digit: i64 = 30, sizeof_digit: i64 = 4, default_max_str_digits: i64 = 4300, str_digits_check_threshold: i64 = 640 }{})");
}

/// Generate sys.hash_info -> hash info struct
pub fn genHashInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Wrap in parentheses to allow field access: (struct{...}{}).field
    try self.emit("(struct { width: i64 = 64, modulus: i64 = 2305843009213693951, inf: i64 = 314159, nan: i64 = 0, imag: i64 = 1000003, algorithm: []const u8 = \"siphash24\", hash_bits: i64 = 64, seed_bits: i64 = 128, cutoff: i64 = 0 }{})");
}

/// Generate sys.prefix -> Python install prefix
pub fn genPrefix(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"/usr\"");
}

/// Generate sys.exec_prefix -> Python exec install prefix
pub fn genExecPrefix(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"/usr\"");
}

/// Generate sys.base_prefix -> base Python install prefix
pub fn genBasePrefix(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"/usr\"");
}

/// Generate sys.base_exec_prefix -> base exec install prefix
pub fn genBaseExecPrefix(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"/usr\"");
}

/// Generate sys.implementation -> implementation info
pub fn genImplementation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Wrap in parentheses to allow field access: (struct{...}{}).field
    try self.emit("(struct { name: []const u8 = \"metal0\", version: struct { major: i64 = 3, minor: i64 = 12, micro: i64 = 0, releaselevel: []const u8 = \"final\", serial: i64 = 0 } = .{}, cache_tag: ?[]const u8 = null }{})");
}

/// Generate sys.hexversion -> version as single integer
pub fn genHexversion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // 3.12.0 final = 0x030c00f0
    try self.emit("@as(i64, 0x030c00f0)");
}

/// Generate sys.api_version -> API version number
pub fn genApiVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 1013)");
}

/// Generate sys.copyright -> copyright string
pub fn genCopyright(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Copyright (c) 2024 metal0 project\"");
}

/// Generate sys.builtin_module_names -> tuple of built-in module names
pub fn genBuiltinModuleNames(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{\"sys\", \"builtins\", \"io\", \"os\", \"json\", \"re\", \"math\", \"random\", \"time\", \"datetime\"}");
}

/// Generate sys.displayhook(value) -> None
pub fn genDisplayhook(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.debug.print(\"{any}\\n\", .{");
        try self.genExpr(args[0]);
        try self.emit("})");
    } else {
        try self.emit("{}");
    }
}

/// Generate sys.excepthook(type, value, traceback) -> None
pub fn genExcepthook(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate sys.settrace(func) -> None
pub fn genSettrace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate sys.gettrace() -> trace function
pub fn genGettrace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate sys.setprofile(func) -> None
pub fn genSetprofile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate sys.getprofile() -> profile function
pub fn genGetprofile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate sys.get_int_max_str_digits() -> int
/// Returns the current limit for integer string conversion
pub fn genGetIntMaxStrDigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("(try sys.get_int_max_str_digits(__global_allocator))");
}

/// Generate sys.set_int_max_str_digits(n) -> None
/// Sets the limit for integer string conversion (0 to disable)
pub fn genSetIntMaxStrDigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("(try sys.set_int_max_str_digits(__global_allocator, ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("0");
    }
    try self.emit("))");
}
