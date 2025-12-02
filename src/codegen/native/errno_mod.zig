/// Python errno module - Standard errno system symbols
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "errorcode", genErrorcode },
    .{ "EPERM", genI32_1 }, .{ "ENOENT", genI32_2 }, .{ "ESRCH", genI32_3 }, .{ "EINTR", genI32_4 },
    .{ "EIO", genI32_5 }, .{ "ENXIO", genI32_6 }, .{ "E2BIG", genI32_7 }, .{ "ENOEXEC", genI32_8 },
    .{ "EBADF", genI32_9 }, .{ "ECHILD", genI32_10 }, .{ "EAGAIN", genI32_11 }, .{ "EWOULDBLOCK", genI32_11 },
    .{ "ENOMEM", genI32_12 }, .{ "EACCES", genI32_13 }, .{ "EFAULT", genI32_14 }, .{ "ENOTBLK", genI32_15 },
    .{ "EBUSY", genI32_16 }, .{ "EEXIST", genI32_17 }, .{ "EXDEV", genI32_18 }, .{ "ENODEV", genI32_19 },
    .{ "ENOTDIR", genI32_20 }, .{ "EISDIR", genI32_21 }, .{ "EINVAL", genI32_22 }, .{ "ENFILE", genI32_23 },
    .{ "EMFILE", genI32_24 }, .{ "ENOTTY", genI32_25 }, .{ "ETXTBSY", genI32_26 }, .{ "EFBIG", genI32_27 },
    .{ "ENOSPC", genI32_28 }, .{ "ESPIPE", genI32_29 }, .{ "EROFS", genI32_30 }, .{ "EMLINK", genI32_31 },
    .{ "EPIPE", genI32_32 }, .{ "EDOM", genI32_33 }, .{ "ERANGE", genI32_34 }, .{ "EDEADLK", genI32_35 },
    .{ "ENAMETOOLONG", genI32_36 }, .{ "ENOLCK", genI32_37 }, .{ "ENOSYS", genI32_38 }, .{ "ENOTEMPTY", genI32_39 },
    .{ "ELOOP", genI32_40 }, .{ "ENOMSG", genI32_42 }, .{ "EIDRM", genI32_43 }, .{ "ECHRNG", genI32_44 },
    .{ "ENOSTR", genI32_60 }, .{ "ENODATA", genI32_61 }, .{ "ETIME", genI32_62 }, .{ "ENOSR", genI32_63 },
    .{ "EOVERFLOW", genI32_75 }, .{ "ENOTSOCK", genI32_88 }, .{ "EDESTADDRREQ", genI32_89 },
    .{ "EMSGSIZE", genI32_90 }, .{ "EPROTOTYPE", genI32_91 }, .{ "ENOPROTOOPT", genI32_92 },
    .{ "EPROTONOSUPPORT", genI32_93 }, .{ "ESOCKTNOSUPPORT", genI32_94 }, .{ "EOPNOTSUPP", genI32_95 },
    .{ "EPFNOSUPPORT", genI32_96 }, .{ "EAFNOSUPPORT", genI32_97 }, .{ "EADDRINUSE", genI32_98 },
    .{ "EADDRNOTAVAIL", genI32_99 }, .{ "ENETDOWN", genI32_100 }, .{ "ENETUNREACH", genI32_101 },
    .{ "ENETRESET", genI32_102 }, .{ "ECONNABORTED", genI32_103 }, .{ "ECONNRESET", genI32_104 },
    .{ "ENOBUFS", genI32_105 }, .{ "EISCONN", genI32_106 }, .{ "ENOTCONN", genI32_107 },
    .{ "ESHUTDOWN", genI32_108 }, .{ "ETOOMANYREFS", genI32_109 }, .{ "ETIMEDOUT", genI32_110 },
    .{ "ECONNREFUSED", genI32_111 }, .{ "EHOSTDOWN", genI32_112 }, .{ "EHOSTUNREACH", genI32_113 },
    .{ "EALREADY", genI32_114 }, .{ "EINPROGRESS", genI32_115 }, .{ "ESTALE", genI32_116 },
    .{ "ECANCELED", genI32_125 }, .{ "ENOKEY", genI32_126 }, .{ "EKEYEXPIRED", genI32_127 },
    .{ "EKEYREVOKED", genI32_128 }, .{ "EKEYREJECTED", genI32_129 },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genErrorcode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "hashmap_helper.StringHashMap([]const u8).init(__global_allocator)"); }
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
fn genI32_16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 16)"); }
fn genI32_17(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 17)"); }
fn genI32_18(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 18)"); }
fn genI32_19(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 19)"); }
fn genI32_20(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 20)"); }
fn genI32_21(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 21)"); }
fn genI32_22(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 22)"); }
fn genI32_23(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 23)"); }
fn genI32_24(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 24)"); }
fn genI32_25(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 25)"); }
fn genI32_26(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 26)"); }
fn genI32_27(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 27)"); }
fn genI32_28(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 28)"); }
fn genI32_29(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 29)"); }
fn genI32_30(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 30)"); }
fn genI32_31(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 31)"); }
fn genI32_32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 32)"); }
fn genI32_33(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 33)"); }
fn genI32_34(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 34)"); }
fn genI32_35(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 35)"); }
fn genI32_36(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 36)"); }
fn genI32_37(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 37)"); }
fn genI32_38(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 38)"); }
fn genI32_39(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 39)"); }
fn genI32_40(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 40)"); }
fn genI32_42(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 42)"); }
fn genI32_43(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 43)"); }
fn genI32_44(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 44)"); }
fn genI32_60(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 60)"); }
fn genI32_61(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 61)"); }
fn genI32_62(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 62)"); }
fn genI32_63(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 63)"); }
fn genI32_75(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 75)"); }
fn genI32_88(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 88)"); }
fn genI32_89(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 89)"); }
fn genI32_90(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 90)"); }
fn genI32_91(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 91)"); }
fn genI32_92(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 92)"); }
fn genI32_93(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 93)"); }
fn genI32_94(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 94)"); }
fn genI32_95(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 95)"); }
fn genI32_96(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 96)"); }
fn genI32_97(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 97)"); }
fn genI32_98(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 98)"); }
fn genI32_99(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 99)"); }
fn genI32_100(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 100)"); }
fn genI32_101(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 101)"); }
fn genI32_102(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 102)"); }
fn genI32_103(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 103)"); }
fn genI32_104(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 104)"); }
fn genI32_105(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 105)"); }
fn genI32_106(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 106)"); }
fn genI32_107(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 107)"); }
fn genI32_108(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 108)"); }
fn genI32_109(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 109)"); }
fn genI32_110(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 110)"); }
fn genI32_111(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 111)"); }
fn genI32_112(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 112)"); }
fn genI32_113(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 113)"); }
fn genI32_114(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 114)"); }
fn genI32_115(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 115)"); }
fn genI32_116(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 116)"); }
fn genI32_125(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 125)"); }
fn genI32_126(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 126)"); }
fn genI32_127(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 127)"); }
fn genI32_128(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 128)"); }
fn genI32_129(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 129)"); }
