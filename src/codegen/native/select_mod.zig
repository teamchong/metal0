/// Python select module - I/O multiplexing
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "select", h.c(".{ &[_]i64{}, &[_]i64{}, &[_]i64{} }") },
    .{ "poll", h.c("struct { fds: std.ArrayList(struct { fd: i64, events: i16, revents: i16 }) = .{}, pub fn register(s: *@This(), fd: i64, mask: ?i16) void { s.fds.append(__global_allocator, .{ .fd = fd, .events = mask orelse 3, .revents = 0 }) catch {}; } pub fn modify(s: *@This(), fd: i64, mask: i16) void { for (s.fds.items) |*i| if (i.fd == fd) { i.events = mask; break; } } pub fn unregister(s: *@This(), fd: i64) void { for (s.fds.items, 0..) |i, x| if (i.fd == fd) { _ = s.fds.orderedRemove(x); break; } } pub fn poll(s: *@This(), t: ?i64) []struct { i64, i16 } { _ = t; var r: std.ArrayList(struct { i64, i16 }) = .{}; for (s.fds.items) |i| if (i.revents != 0) r.append(__global_allocator, .{ i.fd, i.revents }) catch {}; return r.items; } }{}") },
    .{ "epoll", h.c("struct { _epfd: i32 = -1, _closed: bool = false, pub fn close(s: *@This()) void { s._closed = true; } pub fn closed(s: *@This()) bool { return s._closed; } pub fn fileno(s: *@This()) i32 { return s._epfd; } pub fn fromfd(s: *@This(), fd: i32) void { s._epfd = fd; } pub fn register(s: *@This(), fd: i64, mask: ?u32) void { _ = s; _ = fd; _ = mask; } pub fn modify(s: *@This(), fd: i64, mask: u32) void { _ = s; _ = fd; _ = mask; } pub fn unregister(s: *@This(), fd: i64) void { _ = s; _ = fd; } pub fn poll(s: *@This(), t: ?f64, m: ?i32) []struct { i64, u32 } { _ = s; _ = t; _ = m; return &.{}; } }{}") },
    .{ "devpoll", h.c("struct { pub fn close(s: *@This()) void { _ = s; } pub fn register(s: *@This(), fd: i64, mask: ?i16) void { _ = s; _ = fd; _ = mask; } pub fn modify(s: *@This(), fd: i64, mask: i16) void { _ = s; _ = fd; _ = mask; } pub fn unregister(s: *@This(), fd: i64) void { _ = s; _ = fd; } pub fn poll(s: *@This(), t: ?f64) []struct { i64, i16 } { _ = s; _ = t; return &.{}; } }{}") },
    .{ "kqueue", h.c("struct { _kq: i32 = -1, _closed: bool = false, pub fn close(s: *@This()) void { s._closed = true; } pub fn closed(s: *@This()) bool { return s._closed; } pub fn fileno(s: *@This()) i32 { return s._kq; } pub fn fromfd(s: *@This(), fd: i32) void { s._kq = fd; } pub fn control(s: *@This(), cl: anytype, m: usize, t: ?f64) []Kevent { _ = s; _ = cl; _ = m; _ = t; return &.{}; } }{}") },
    .{ "kevent", h.c("struct { ident: usize = 0, filter: i16 = -1, flags: u16 = 1, fflags: u32 = 0, data: isize = 0, udata: ?*anyopaque = null }{}") },
    .{ "POLLIN", h.I16(0x0001) }, .{ "POLLPRI", h.I16(0x0002) }, .{ "POLLOUT", h.I16(0x0004) },
    .{ "POLLERR", h.I16(0x0008) }, .{ "POLLHUP", h.I16(0x0010) }, .{ "POLLNVAL", h.I16(0x0020) },
    .{ "EPOLLIN", h.hex32(0x001) }, .{ "EPOLLOUT", h.hex32(0x004) }, .{ "EPOLLPRI", h.hex32(0x002) },
    .{ "EPOLLERR", h.hex32(0x008) }, .{ "EPOLLHUP", h.hex32(0x010) }, .{ "EPOLLET", h.hex32(0x80000000) },
    .{ "EPOLLONESHOT", h.hex32(0x40000000) }, .{ "EPOLLEXCLUSIVE", h.hex32(0x10000000) },
    .{ "EPOLLRDHUP", h.hex32(0x2000) }, .{ "EPOLLRDNORM", h.hex32(0x040) }, .{ "EPOLLRDBAND", h.hex32(0x080) },
    .{ "EPOLLWRNORM", h.hex32(0x100) }, .{ "EPOLLWRBAND", h.hex32(0x200) }, .{ "EPOLLMSG", h.hex32(0x400) },
    .{ "KQ_FILTER_READ", h.I16(-1) }, .{ "KQ_FILTER_WRITE", h.I16(-2) }, .{ "KQ_FILTER_AIO", h.I16(-3) },
    .{ "KQ_FILTER_VNODE", h.I16(-4) }, .{ "KQ_FILTER_PROC", h.I16(-5) }, .{ "KQ_FILTER_SIGNAL", h.I16(-6) },
    .{ "KQ_FILTER_TIMER", h.I16(-7) },
    .{ "KQ_EV_ADD", h.U16(0x0001) }, .{ "KQ_EV_DELETE", h.U16(0x0002) }, .{ "KQ_EV_ENABLE", h.U16(0x0004) },
    .{ "KQ_EV_DISABLE", h.U16(0x0008) }, .{ "KQ_EV_ONESHOT", h.U16(0x0010) }, .{ "KQ_EV_CLEAR", h.U16(0x0020) },
    .{ "KQ_EV_EOF", h.U16(0x8000) }, .{ "KQ_EV_ERROR", h.U16(0x4000) },
});
