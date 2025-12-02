/// Python errno module - Standard errno system symbols
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "errorcode", genConst("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)") },
    .{ "EPERM", genConst("@as(i32, 1)") }, .{ "ENOENT", genConst("@as(i32, 2)") },
    .{ "ESRCH", genConst("@as(i32, 3)") }, .{ "EINTR", genConst("@as(i32, 4)") },
    .{ "EIO", genConst("@as(i32, 5)") }, .{ "ENXIO", genConst("@as(i32, 6)") },
    .{ "E2BIG", genConst("@as(i32, 7)") }, .{ "ENOEXEC", genConst("@as(i32, 8)") },
    .{ "EBADF", genConst("@as(i32, 9)") }, .{ "ECHILD", genConst("@as(i32, 10)") },
    .{ "EAGAIN", genConst("@as(i32, 11)") }, .{ "EWOULDBLOCK", genConst("@as(i32, 11)") },
    .{ "ENOMEM", genConst("@as(i32, 12)") }, .{ "EACCES", genConst("@as(i32, 13)") },
    .{ "EFAULT", genConst("@as(i32, 14)") }, .{ "ENOTBLK", genConst("@as(i32, 15)") },
    .{ "EBUSY", genConst("@as(i32, 16)") }, .{ "EEXIST", genConst("@as(i32, 17)") },
    .{ "EXDEV", genConst("@as(i32, 18)") }, .{ "ENODEV", genConst("@as(i32, 19)") },
    .{ "ENOTDIR", genConst("@as(i32, 20)") }, .{ "EISDIR", genConst("@as(i32, 21)") },
    .{ "EINVAL", genConst("@as(i32, 22)") }, .{ "ENFILE", genConst("@as(i32, 23)") },
    .{ "EMFILE", genConst("@as(i32, 24)") }, .{ "ENOTTY", genConst("@as(i32, 25)") },
    .{ "ETXTBSY", genConst("@as(i32, 26)") }, .{ "EFBIG", genConst("@as(i32, 27)") },
    .{ "ENOSPC", genConst("@as(i32, 28)") }, .{ "ESPIPE", genConst("@as(i32, 29)") },
    .{ "EROFS", genConst("@as(i32, 30)") }, .{ "EMLINK", genConst("@as(i32, 31)") },
    .{ "EPIPE", genConst("@as(i32, 32)") }, .{ "EDOM", genConst("@as(i32, 33)") },
    .{ "ERANGE", genConst("@as(i32, 34)") }, .{ "EDEADLK", genConst("@as(i32, 35)") },
    .{ "ENAMETOOLONG", genConst("@as(i32, 36)") }, .{ "ENOLCK", genConst("@as(i32, 37)") },
    .{ "ENOSYS", genConst("@as(i32, 38)") }, .{ "ENOTEMPTY", genConst("@as(i32, 39)") },
    .{ "ELOOP", genConst("@as(i32, 40)") }, .{ "ENOMSG", genConst("@as(i32, 42)") },
    .{ "EIDRM", genConst("@as(i32, 43)") }, .{ "ECHRNG", genConst("@as(i32, 44)") },
    .{ "ENOSTR", genConst("@as(i32, 60)") }, .{ "ENODATA", genConst("@as(i32, 61)") },
    .{ "ETIME", genConst("@as(i32, 62)") }, .{ "ENOSR", genConst("@as(i32, 63)") },
    .{ "EOVERFLOW", genConst("@as(i32, 75)") }, .{ "ENOTSOCK", genConst("@as(i32, 88)") },
    .{ "EDESTADDRREQ", genConst("@as(i32, 89)") }, .{ "EMSGSIZE", genConst("@as(i32, 90)") },
    .{ "EPROTOTYPE", genConst("@as(i32, 91)") }, .{ "ENOPROTOOPT", genConst("@as(i32, 92)") },
    .{ "EPROTONOSUPPORT", genConst("@as(i32, 93)") }, .{ "ESOCKTNOSUPPORT", genConst("@as(i32, 94)") },
    .{ "EOPNOTSUPP", genConst("@as(i32, 95)") }, .{ "EPFNOSUPPORT", genConst("@as(i32, 96)") },
    .{ "EAFNOSUPPORT", genConst("@as(i32, 97)") }, .{ "EADDRINUSE", genConst("@as(i32, 98)") },
    .{ "EADDRNOTAVAIL", genConst("@as(i32, 99)") }, .{ "ENETDOWN", genConst("@as(i32, 100)") },
    .{ "ENETUNREACH", genConst("@as(i32, 101)") }, .{ "ENETRESET", genConst("@as(i32, 102)") },
    .{ "ECONNABORTED", genConst("@as(i32, 103)") }, .{ "ECONNRESET", genConst("@as(i32, 104)") },
    .{ "ENOBUFS", genConst("@as(i32, 105)") }, .{ "EISCONN", genConst("@as(i32, 106)") },
    .{ "ENOTCONN", genConst("@as(i32, 107)") }, .{ "ESHUTDOWN", genConst("@as(i32, 108)") },
    .{ "ETOOMANYREFS", genConst("@as(i32, 109)") }, .{ "ETIMEDOUT", genConst("@as(i32, 110)") },
    .{ "ECONNREFUSED", genConst("@as(i32, 111)") }, .{ "EHOSTDOWN", genConst("@as(i32, 112)") },
    .{ "EHOSTUNREACH", genConst("@as(i32, 113)") }, .{ "EALREADY", genConst("@as(i32, 114)") },
    .{ "EINPROGRESS", genConst("@as(i32, 115)") }, .{ "ESTALE", genConst("@as(i32, 116)") },
    .{ "ECANCELED", genConst("@as(i32, 125)") }, .{ "ENOKEY", genConst("@as(i32, 126)") },
    .{ "EKEYEXPIRED", genConst("@as(i32, 127)") }, .{ "EKEYREVOKED", genConst("@as(i32, 128)") },
    .{ "EKEYREJECTED", genConst("@as(i32, 129)") },
});
