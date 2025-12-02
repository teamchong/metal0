/// Python resource module - Unix resource usage and limits
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getrusage", genGetrusage }, .{ "getrlimit", genGetrlimit }, .{ "setrlimit", genUnit }, .{ "prlimit", genGetrlimit },
    .{ "getpagesize", genPagesize },
    .{ "RUSAGE_SELF", genI32_0 }, .{ "RUSAGE_CHILDREN", genI32_n1 }, .{ "RUSAGE_BOTH", genI32_n2 }, .{ "RUSAGE_THREAD", genI32_1 },
    .{ "RLIMIT_CPU", genI32_0 }, .{ "RLIMIT_FSIZE", genI32_1 }, .{ "RLIMIT_DATA", genI32_2 }, .{ "RLIMIT_STACK", genI32_3 },
    .{ "RLIMIT_CORE", genI32_4 }, .{ "RLIMIT_RSS", genI32_5 }, .{ "RLIMIT_NPROC", genI32_6 }, .{ "RLIMIT_NOFILE", genI32_7 },
    .{ "RLIMIT_MEMLOCK", genI32_8 }, .{ "RLIMIT_AS", genI32_9 }, .{ "RLIMIT_LOCKS", genI32_10 }, .{ "RLIMIT_SIGPENDING", genI32_11 },
    .{ "RLIMIT_MSGQUEUE", genI32_12 }, .{ "RLIMIT_NICE", genI32_13 }, .{ "RLIMIT_RTPRIO", genI32_14 }, .{ "RLIMIT_RTTIME", genI32_15 },
    .{ "RLIM_INFINITY", genI64_n1 },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genPagesize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 4096)"); }
fn genGetrlimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i64, -1), @as(i64, -1) }"); }
fn genGetrusage(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .ru_utime = 0.0, .ru_stime = 0.0, .ru_maxrss = 0, .ru_ixrss = 0, .ru_idrss = 0, .ru_isrss = 0, .ru_minflt = 0, .ru_majflt = 0, .ru_nswap = 0, .ru_inblock = 0, .ru_oublock = 0, .ru_msgsnd = 0, .ru_msgrcv = 0, .ru_nsignals = 0, .ru_nvcsw = 0, .ru_nivcsw = 0 }"); }
fn genI64_n1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, -1)"); }

// Integer constants
fn genI32_n2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, -2)"); }
fn genI32_n1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, -1)"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 5)"); }
fn genI32_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genI32_7(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 7)"); }
fn genI32_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 8)"); }
fn genI32_9(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 9)"); }
fn genI32_10(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 10)"); }
fn genI32_11(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 11)"); }
fn genI32_12(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 12)"); }
fn genI32_13(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 13)"); }
fn genI32_14(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 14)"); }
fn genI32_15(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 15)"); }
