/// Python sys module - system-specific parameters and functions
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // sys.argv references mutable global __sys_argv (initialized in main, can be assigned)
    .{ "argv", h.c("__sys_argv") },
    .{ "exit", h.wrap("blk: { const _code: u8 = @intCast(", "); std.process.exit(_code); break :blk; }", "blk: { std.process.exit(0); break :blk; }") },
    .{ "path", h.c("&[_][]const u8{\".\" }") },
    .{ "platform", h.c("blk: { const _b = @import(\"builtin\"); break :blk switch (_b.os.tag) { .linux => \"linux\", .macos => \"darwin\", .windows => \"win32\", .freebsd => \"freebsd\", else => \"unknown\" }; }") },
    .{ "version", h.c("\"3.12.0 (metal0 compiled)\"") },
    .{ "version_info", h.c(".{ .major = 3, .minor = 12, .micro = 0, .releaselevel = \"final\", .serial = 0 }") },
    .{ "executable", h.c("blk: { const _b = @import(\"builtin\"); const _is_wasm = _b.os.tag == .wasi or _b.os.tag == .freestanding; if (comptime _is_wasm) break :blk \"\"; const _args = std.os.argv; if (_args.len > 0) break :blk std.mem.span(_args[0]); break :blk \"\"; }") },
    .{ "stdin", h.c("(try runtime.PyFile.create(__global_allocator, std.fs.File{ .handle = std.posix.STDIN_FILENO }, \"r\"))") }, .{ "stdout", h.c("(try runtime.PyFile.create(__global_allocator, std.fs.File{ .handle = std.posix.STDOUT_FILENO }, \"w\"))") }, .{ "stderr", h.c("(try runtime.PyFile.create(__global_allocator, std.fs.File{ .handle = std.posix.STDERR_FILENO }, \"w\"))") },
    .{ "maxsize", h.c("@as(i128, std.math.maxInt(i64))") },
    .{ "byteorder", h.c("blk: { const _native = @import(\"builtin\").cpu.arch.endian(); break :blk if (_native == .little) \"little\" else \"big\"; }") },
    .{ "getsizeof", h.wrap("@as(i64, @intCast(@sizeOf(@TypeOf(", "))))", "@as(i64, 0)") }, .{ "getrecursionlimit", h.I64(1000) }, .{ "setrecursionlimit", h.c("{}") },
    .{ "getdefaultencoding", h.c("\"utf-8\"") }, .{ "getfilesystemencoding", h.c("\"utf-8\"") },
    .{ "intern", h.pass("\"\"") }, .{ "modules", h.c("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)") },
    .{ "getrefcount", h.I64(1) }, .{ "exc_info", h.c(".{ null, null, null }") },
    .{ "get_coroutine_origin_tracking_depth", h.I64(0) }, .{ "set_coroutine_origin_tracking_depth", h.c("{}") },
    .{ "flags", h.c("(struct { debug: i64 = 0, optimize: i64 = 0, inspect: i64 = 0, interactive: i64 = 0, verbose: i64 = 0, quiet: i64 = 0, dont_write_bytecode: i64 = 0, no_user_site: i64 = 0, no_site: i64 = 0, ignore_environment: i64 = 0, hash_randomization: i64 = 1, isolated: i64 = 0, bytes_warning: i64 = 0, warn_default_encoding: i64 = 0, safe_path: i64 = 0, int_max_str_digits: i64 = 4300 }{})") },
    .{ "float_info", h.c("(struct { max: f64 = 1.7976931348623157e+308, max_exp: i64 = 1024, max_10_exp: i64 = 308, min: f64 = 2.2250738585072014e-308, min_exp: i64 = -1021, min_10_exp: i64 = -307, dig: i64 = 15, mant_dig: i64 = 53, epsilon: f64 = 2.220446049250313e-16, radix: i64 = 2, rounds: i64 = 1 }{})") },
    .{ "int_info", h.c("(struct { bits_per_digit: i64 = 30, sizeof_digit: i64 = 4, default_max_str_digits: i64 = 4300, str_digits_check_threshold: i64 = 640 }{})") },
    .{ "hash_info", h.c("(struct { width: i64 = 64, modulus: i64 = 2305843009213693951, inf: i64 = 314159, nan: i64 = 0, imag: i64 = 1000003, algorithm: []const u8 = \"siphash24\", hash_bits: i64 = 64, seed_bits: i64 = 128, cutoff: i64 = 0 }{})") },
    .{ "prefix", h.c("\"/usr\"") }, .{ "exec_prefix", h.c("\"/usr\"") }, .{ "base_prefix", h.c("\"/usr\"") }, .{ "base_exec_prefix", h.c("\"/usr\"") },
    .{ "implementation", h.c("(struct { name: []const u8 = \"metal0\", version: struct { major: i64 = 3, minor: i64 = 12, micro: i64 = 0, releaselevel: []const u8 = \"final\", serial: i64 = 0 } = .{}, cache_tag: ?[]const u8 = null }{})") },
    .{ "hexversion", h.I64(0x030c00f0) }, .{ "api_version", h.I64(1013) },
    .{ "copyright", h.c("\"Copyright (c) 2024 metal0 project\"") },
    .{ "builtin_module_names", h.c("&[_][]const u8{\"sys\", \"builtins\", \"io\", \"os\", \"json\", \"re\", \"math\", \"random\", \"time\", \"datetime\"}") },
    .{ "displayhook", h.debugPrint("", "{any}", "{}") }, .{ "excepthook", h.c("{}") }, .{ "settrace", h.c("{}") }, .{ "gettrace", h.c("null") },
    .{ "setprofile", h.c("{}") }, .{ "getprofile", h.c("null") },
    .{ "get_int_max_str_digits", h.c("(try sys.get_int_max_str_digits(__global_allocator))") },
    .{ "set_int_max_str_digits", h.wrap("(try sys.set_int_max_str_digits(__global_allocator, ", "))", "(try sys.set_int_max_str_digits(__global_allocator, 0))") },
});
