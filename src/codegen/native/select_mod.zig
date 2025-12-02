/// Python select module - I/O multiplexing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "select", genSelect }, .{ "poll", genPoll }, .{ "epoll", genEpoll },
    .{ "devpoll", genDevpoll }, .{ "kqueue", genKqueue }, .{ "kevent", genKevent },
    .{ "POLLIN", genI16_1 }, .{ "POLLPRI", genI16_2 }, .{ "POLLOUT", genI16_4 },
    .{ "POLLERR", genI16_8 }, .{ "POLLHUP", genI16_16 }, .{ "POLLNVAL", genI16_32 },
    .{ "EPOLLIN", genU32_1 }, .{ "EPOLLOUT", genU32_4 }, .{ "EPOLLPRI", genU32_2 },
    .{ "EPOLLERR", genU32_8 }, .{ "EPOLLHUP", genU32_16 }, .{ "EPOLLET", genEPOLLET },
    .{ "EPOLLONESHOT", genEPOLLONESHOT }, .{ "EPOLLEXCLUSIVE", genEPOLLEXCLUSIVE },
    .{ "EPOLLRDHUP", genEPOLLRDHUP }, .{ "EPOLLRDNORM", genU32_64 }, .{ "EPOLLRDBAND", genU32_128 },
    .{ "EPOLLWRNORM", genU32_256 }, .{ "EPOLLWRBAND", genU32_512 }, .{ "EPOLLMSG", genU32_1024 },
    .{ "KQ_FILTER_READ", genI16_n1 }, .{ "KQ_FILTER_WRITE", genI16_n2 }, .{ "KQ_FILTER_AIO", genI16_n3 },
    .{ "KQ_FILTER_VNODE", genI16_n4 }, .{ "KQ_FILTER_PROC", genI16_n5 }, .{ "KQ_FILTER_SIGNAL", genI16_n6 },
    .{ "KQ_FILTER_TIMER", genI16_n7 },
    .{ "KQ_EV_ADD", genU16_1 }, .{ "KQ_EV_DELETE", genU16_2 }, .{ "KQ_EV_ENABLE", genU16_4 },
    .{ "KQ_EV_DISABLE", genU16_8 }, .{ "KQ_EV_ONESHOT", genU16_16 }, .{ "KQ_EV_CLEAR", genU16_32 },
    .{ "KQ_EV_EOF", genU16_32768 }, .{ "KQ_EV_ERROR", genU16_16384 },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genI16_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, 0x0001)"); }
fn genI16_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, 0x0002)"); }
fn genI16_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, 0x0004)"); }
fn genI16_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, 0x0008)"); }
fn genI16_16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, 0x0010)"); }
fn genI16_32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, 0x0020)"); }
fn genI16_n1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, -1)"); }
fn genI16_n2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, -2)"); }
fn genI16_n3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, -3)"); }
fn genI16_n4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, -4)"); }
fn genI16_n5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, -5)"); }
fn genI16_n6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, -6)"); }
fn genI16_n7(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, -7)"); }
fn genU16_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u16, 0x0001)"); }
fn genU16_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u16, 0x0002)"); }
fn genU16_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u16, 0x0004)"); }
fn genU16_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u16, 0x0008)"); }
fn genU16_16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u16, 0x0010)"); }
fn genU16_32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u16, 0x0020)"); }
fn genU16_16384(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u16, 0x4000)"); }
fn genU16_32768(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u16, 0x8000)"); }
fn genU32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x001)"); }
fn genU32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x002)"); }
fn genU32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x004)"); }
fn genU32_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x008)"); }
fn genU32_16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x010)"); }
fn genU32_64(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x040)"); }
fn genU32_128(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x080)"); }
fn genU32_256(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x100)"); }
fn genU32_512(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x200)"); }
fn genU32_1024(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x400)"); }
fn genEPOLLET(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x80000000)"); }
fn genEPOLLONESHOT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x40000000)"); }
fn genEPOLLEXCLUSIVE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x10000000)"); }
fn genEPOLLRDHUP(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x2000)"); }

// Core functions
fn genSelect(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ &[_]i64{}, &[_]i64{}, &[_]i64{} }"); }

fn genPoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { fds: std.ArrayList(struct { fd: i64, events: i16, revents: i16 }) = .{}, pub fn register(s: *@This(), fd: i64, mask: ?i16) void { s.fds.append(__global_allocator, .{ .fd = fd, .events = mask orelse 3, .revents = 0 }) catch {}; } pub fn modify(s: *@This(), fd: i64, mask: i16) void { for (s.fds.items) |*i| if (i.fd == fd) { i.events = mask; break; } } pub fn unregister(s: *@This(), fd: i64) void { for (s.fds.items, 0..) |i, x| if (i.fd == fd) { _ = s.fds.orderedRemove(x); break; } } pub fn poll(s: *@This(), t: ?i64) []struct { i64, i16 } { _ = t; var r: std.ArrayList(struct { i64, i16 }) = .{}; for (s.fds.items) |i| if (i.revents != 0) r.append(__global_allocator, .{ i.fd, i.revents }) catch {}; return r.items; } }{}");
}

fn genEpoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { _epfd: i32 = -1, _closed: bool = false, pub fn close(s: *@This()) void { s._closed = true; } pub fn closed(s: *@This()) bool { return s._closed; } pub fn fileno(s: *@This()) i32 { return s._epfd; } pub fn fromfd(s: *@This(), fd: i32) void { s._epfd = fd; } pub fn register(s: *@This(), fd: i64, mask: ?u32) void { _ = s; _ = fd; _ = mask; } pub fn modify(s: *@This(), fd: i64, mask: u32) void { _ = s; _ = fd; _ = mask; } pub fn unregister(s: *@This(), fd: i64) void { _ = s; _ = fd; } pub fn poll(s: *@This(), t: ?f64, m: ?i32) []struct { i64, u32 } { _ = s; _ = t; _ = m; return &.{}; } }{}");
}

fn genDevpoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { pub fn close(s: *@This()) void { _ = s; } pub fn register(s: *@This(), fd: i64, mask: ?i16) void { _ = s; _ = fd; _ = mask; } pub fn modify(s: *@This(), fd: i64, mask: i16) void { _ = s; _ = fd; _ = mask; } pub fn unregister(s: *@This(), fd: i64) void { _ = s; _ = fd; } pub fn poll(s: *@This(), t: ?f64) []struct { i64, i16 } { _ = s; _ = t; return &.{}; } }{}");
}

fn genKqueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { _kq: i32 = -1, _closed: bool = false, pub fn close(s: *@This()) void { s._closed = true; } pub fn closed(s: *@This()) bool { return s._closed; } pub fn fileno(s: *@This()) i32 { return s._kq; } pub fn fromfd(s: *@This(), fd: i32) void { s._kq = fd; } pub fn control(s: *@This(), cl: anytype, m: usize, t: ?f64) []Kevent { _ = s; _ = cl; _ = m; _ = t; return &.{}; } }{}");
}

fn genKevent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { ident: usize = 0, filter: i16 = -1, flags: u16 = 1, fflags: u32 = 0, data: isize = 0, udata: ?*anyopaque = null }{}");
}
