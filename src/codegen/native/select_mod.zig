/// Python select module - I/O multiplexing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genI16(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(i16, {})", .{n})); }
fn genU16(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(u16, 0x{x:0>4})", .{n})); }
fn genU32(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(u32, 0x{x})", .{n})); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "select", genConst(".{ &[_]i64{}, &[_]i64{}, &[_]i64{} }") },
    .{ "poll", genConst("struct { fds: std.ArrayList(struct { fd: i64, events: i16, revents: i16 }) = .{}, pub fn register(s: *@This(), fd: i64, mask: ?i16) void { s.fds.append(__global_allocator, .{ .fd = fd, .events = mask orelse 3, .revents = 0 }) catch {}; } pub fn modify(s: *@This(), fd: i64, mask: i16) void { for (s.fds.items) |*i| if (i.fd == fd) { i.events = mask; break; } } pub fn unregister(s: *@This(), fd: i64) void { for (s.fds.items, 0..) |i, x| if (i.fd == fd) { _ = s.fds.orderedRemove(x); break; } } pub fn poll(s: *@This(), t: ?i64) []struct { i64, i16 } { _ = t; var r: std.ArrayList(struct { i64, i16 }) = .{}; for (s.fds.items) |i| if (i.revents != 0) r.append(__global_allocator, .{ i.fd, i.revents }) catch {}; return r.items; } }{}") },
    .{ "epoll", genConst("struct { _epfd: i32 = -1, _closed: bool = false, pub fn close(s: *@This()) void { s._closed = true; } pub fn closed(s: *@This()) bool { return s._closed; } pub fn fileno(s: *@This()) i32 { return s._epfd; } pub fn fromfd(s: *@This(), fd: i32) void { s._epfd = fd; } pub fn register(s: *@This(), fd: i64, mask: ?u32) void { _ = s; _ = fd; _ = mask; } pub fn modify(s: *@This(), fd: i64, mask: u32) void { _ = s; _ = fd; _ = mask; } pub fn unregister(s: *@This(), fd: i64) void { _ = s; _ = fd; } pub fn poll(s: *@This(), t: ?f64, m: ?i32) []struct { i64, u32 } { _ = s; _ = t; _ = m; return &.{}; } }{}") },
    .{ "devpoll", genConst("struct { pub fn close(s: *@This()) void { _ = s; } pub fn register(s: *@This(), fd: i64, mask: ?i16) void { _ = s; _ = fd; _ = mask; } pub fn modify(s: *@This(), fd: i64, mask: i16) void { _ = s; _ = fd; _ = mask; } pub fn unregister(s: *@This(), fd: i64) void { _ = s; _ = fd; } pub fn poll(s: *@This(), t: ?f64) []struct { i64, i16 } { _ = s; _ = t; return &.{}; } }{}") },
    .{ "kqueue", genConst("struct { _kq: i32 = -1, _closed: bool = false, pub fn close(s: *@This()) void { s._closed = true; } pub fn closed(s: *@This()) bool { return s._closed; } pub fn fileno(s: *@This()) i32 { return s._kq; } pub fn fromfd(s: *@This(), fd: i32) void { s._kq = fd; } pub fn control(s: *@This(), cl: anytype, m: usize, t: ?f64) []Kevent { _ = s; _ = cl; _ = m; _ = t; return &.{}; } }{}") },
    .{ "kevent", genConst("struct { ident: usize = 0, filter: i16 = -1, flags: u16 = 1, fflags: u32 = 0, data: isize = 0, udata: ?*anyopaque = null }{}") },
    .{ "POLLIN", genI16(0x0001) }, .{ "POLLPRI", genI16(0x0002) }, .{ "POLLOUT", genI16(0x0004) },
    .{ "POLLERR", genI16(0x0008) }, .{ "POLLHUP", genI16(0x0010) }, .{ "POLLNVAL", genI16(0x0020) },
    .{ "EPOLLIN", genU32(0x001) }, .{ "EPOLLOUT", genU32(0x004) }, .{ "EPOLLPRI", genU32(0x002) },
    .{ "EPOLLERR", genU32(0x008) }, .{ "EPOLLHUP", genU32(0x010) }, .{ "EPOLLET", genU32(0x80000000) },
    .{ "EPOLLONESHOT", genU32(0x40000000) }, .{ "EPOLLEXCLUSIVE", genU32(0x10000000) },
    .{ "EPOLLRDHUP", genU32(0x2000) }, .{ "EPOLLRDNORM", genU32(0x040) }, .{ "EPOLLRDBAND", genU32(0x080) },
    .{ "EPOLLWRNORM", genU32(0x100) }, .{ "EPOLLWRBAND", genU32(0x200) }, .{ "EPOLLMSG", genU32(0x400) },
    .{ "KQ_FILTER_READ", genI16(-1) }, .{ "KQ_FILTER_WRITE", genI16(-2) }, .{ "KQ_FILTER_AIO", genI16(-3) },
    .{ "KQ_FILTER_VNODE", genI16(-4) }, .{ "KQ_FILTER_PROC", genI16(-5) }, .{ "KQ_FILTER_SIGNAL", genI16(-6) },
    .{ "KQ_FILTER_TIMER", genI16(-7) },
    .{ "KQ_EV_ADD", genU16(0x0001) }, .{ "KQ_EV_DELETE", genU16(0x0002) }, .{ "KQ_EV_ENABLE", genU16(0x0004) },
    .{ "KQ_EV_DISABLE", genU16(0x0008) }, .{ "KQ_EV_ONESHOT", genU16(0x0010) }, .{ "KQ_EV_CLEAR", genU16(0x0020) },
    .{ "KQ_EV_EOF", genU16(0x8000) }, .{ "KQ_EV_ERROR", genU16(0x4000) },
});
