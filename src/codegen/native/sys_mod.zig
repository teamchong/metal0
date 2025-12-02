/// Python sys module - system-specific parameters and functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "argv", genConst("blk: { const _os_args = std.os.argv; var _argv: std.ArrayList([]const u8) = .{}; for (_os_args) |arg| { _argv.append(__global_allocator, std.mem.span(arg)) catch continue; } break :blk _argv.items; }") },
    .{ "exit", genExit }, .{ "path", genConst("&[_][]const u8{\".\" }") },
    .{ "platform", genConst("blk: { const _b = @import(\"builtin\"); break :blk switch (_b.os.tag) { .linux => \"linux\", .macos => \"darwin\", .windows => \"win32\", .freebsd => \"freebsd\", else => \"unknown\" }; }") },
    .{ "version", genConst("\"3.12.0 (metal0 compiled)\"") },
    .{ "version_info", genConst(".{ .major = 3, .minor = 12, .micro = 0, .releaselevel = \"final\", .serial = 0 }") },
    .{ "executable", genConst("blk: { const _args = std.os.argv; if (_args.len > 0) break :blk std.mem.span(_args[0]); break :blk \"\"; }") },
    .{ "stdin", genConst("std.io.getStdIn()") }, .{ "stdout", genConst("std.io.getStdOut()") }, .{ "stderr", genConst("std.io.getStdErr()") },
    .{ "maxsize", genConst("@as(i128, std.math.maxInt(i64))") },
    .{ "byteorder", genConst("blk: { const _native = @import(\"builtin\").cpu.arch.endian(); break :blk if (_native == .little) \"little\" else \"big\"; }") },
    .{ "getsizeof", genGetsizeof }, .{ "getrecursionlimit", genConst("@as(i64, 1000)") }, .{ "setrecursionlimit", genConst("{}") },
    .{ "getdefaultencoding", genConst("\"utf-8\"") }, .{ "getfilesystemencoding", genConst("\"utf-8\"") },
    .{ "intern", genIntern }, .{ "modules", genConst("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)") },
    .{ "getrefcount", genConst("@as(i64, 1)") }, .{ "exc_info", genConst(".{ null, null, null }") },
    .{ "get_coroutine_origin_tracking_depth", genConst("@as(i64, 0)") }, .{ "set_coroutine_origin_tracking_depth", genConst("{}") },
    .{ "flags", genConst("(struct { debug: i64 = 0, optimize: i64 = 0, inspect: i64 = 0, interactive: i64 = 0, verbose: i64 = 0, quiet: i64 = 0, dont_write_bytecode: i64 = 0, no_user_site: i64 = 0, no_site: i64 = 0, ignore_environment: i64 = 0, hash_randomization: i64 = 1, isolated: i64 = 0, bytes_warning: i64 = 0, warn_default_encoding: i64 = 0, safe_path: i64 = 0, int_max_str_digits: i64 = 4300 }{})") },
    .{ "float_info", genConst("(struct { max: f64 = 1.7976931348623157e+308, max_exp: i64 = 1024, max_10_exp: i64 = 308, min: f64 = 2.2250738585072014e-308, min_exp: i64 = -1021, min_10_exp: i64 = -307, dig: i64 = 15, mant_dig: i64 = 53, epsilon: f64 = 2.220446049250313e-16, radix: i64 = 2, rounds: i64 = 1 }{})") },
    .{ "int_info", genConst("(struct { bits_per_digit: i64 = 30, sizeof_digit: i64 = 4, default_max_str_digits: i64 = 4300, str_digits_check_threshold: i64 = 640 }{})") },
    .{ "hash_info", genConst("(struct { width: i64 = 64, modulus: i64 = 2305843009213693951, inf: i64 = 314159, nan: i64 = 0, imag: i64 = 1000003, algorithm: []const u8 = \"siphash24\", hash_bits: i64 = 64, seed_bits: i64 = 128, cutoff: i64 = 0 }{})") },
    .{ "prefix", genConst("\"/usr\"") }, .{ "exec_prefix", genConst("\"/usr\"") }, .{ "base_prefix", genConst("\"/usr\"") }, .{ "base_exec_prefix", genConst("\"/usr\"") },
    .{ "implementation", genConst("(struct { name: []const u8 = \"metal0\", version: struct { major: i64 = 3, minor: i64 = 12, micro: i64 = 0, releaselevel: []const u8 = \"final\", serial: i64 = 0 } = .{}, cache_tag: ?[]const u8 = null }{})") },
    .{ "hexversion", genConst("@as(i64, 0x030c00f0)") }, .{ "api_version", genConst("@as(i64, 1013)") },
    .{ "copyright", genConst("\"Copyright (c) 2024 metal0 project\"") },
    .{ "builtin_module_names", genConst("&[_][]const u8{\"sys\", \"builtins\", \"io\", \"os\", \"json\", \"re\", \"math\", \"random\", \"time\", \"datetime\"}") },
    .{ "displayhook", genDisplayhook }, .{ "excepthook", genConst("{}") }, .{ "settrace", genConst("{}") }, .{ "gettrace", genConst("null") },
    .{ "setprofile", genConst("{}") }, .{ "getprofile", genConst("null") },
    .{ "get_int_max_str_digits", genConst("(try sys.get_int_max_str_digits(__global_allocator))") },
    .{ "set_int_max_str_digits", genSetIntMaxStrDigits },
});

fn genExit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("blk: { const _code: u8 = ");
    if (args.len > 0) { try self.emit("@intCast("); try self.genExpr(args[0]); try self.emit(")"); } else try self.emit("0");
    try self.emit("; std.process.exit(_code); break :blk; }");
}
fn genGetsizeof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("@as(i64, @intCast(@sizeOf(@TypeOf("); try self.genExpr(args[0]); try self.emit("))))");
}
fn genIntern(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]); }
fn genDisplayhook(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("std.debug.print(\"{any}\\n\", .{"); try self.genExpr(args[0]); try self.emit("})"); } else try self.emit("{}");
}
fn genSetIntMaxStrDigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("(try sys.set_int_max_str_digits(__global_allocator, ");
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("0");
    try self.emit("))");
}
