/// Python select module - I/O multiplexing
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

const poll_struct = "struct { fds: std.ArrayList(struct { fd: i64, events: i16, revents: i16 }) = .{}, pub fn register(s: *@This(), fd: i64, mask: ?i16) void { s.fds.append(__global_allocator, .{ .fd = fd, .events = mask orelse 3, .revents = 0 }) catch unreachable; } pub fn modify(s: *@This(), fd: i64, mask: i16) void { for (s.fds.items) |*i| if (i.fd == fd) { i.events = mask; break; } } pub fn unregister(s: *@This(), fd: i64) void { for (s.fds.items, 0..) |i, x| if (i.fd == fd) { _ = s.fds.orderedRemove(x); break; } } pub fn poll(s: *@This(), t: ?i64) []struct { i64, i16 } { _ = t; var r: std.ArrayList(struct { i64, i16 }) = .{}; for (s.fds.items) |i| if (i.revents != 0) r.append(__global_allocator, .{ i.fd, i.revents }) catch unreachable; return r.items; } }{}";
const epoll_struct = "struct { _epfd: i32 = -1, _closed: bool = false, pub fn close(s: *@This()) void { s._closed = true; } pub fn closed(s: *@This()) bool { return s._closed; } pub fn fileno(s: *@This()) i32 { return s._epfd; } pub fn fromfd(s: *@This(), fd: i32) void { s._epfd = fd; } pub fn register(s: *@This(), fd: i64, mask: ?u32) void { _ = s; _ = fd; _ = mask; } pub fn modify(s: *@This(), fd: i64, mask: u32) void { _ = s; _ = fd; _ = mask; } pub fn unregister(s: *@This(), fd: i64) void { _ = s; _ = fd; } pub fn poll(s: *@This(), t: ?f64, m: ?i32) []struct { i64, u32 } { _ = s; _ = t; _ = m; return &.{}; } }{}";
const devpoll_struct = "struct { pub fn close(s: *@This()) void { _ = s; } pub fn register(s: *@This(), fd: i64, mask: ?i16) void { _ = s; _ = fd; _ = mask; } pub fn modify(s: *@This(), fd: i64, mask: i16) void { _ = s; _ = fd; _ = mask; } pub fn unregister(s: *@This(), fd: i64) void { _ = s; _ = fd; } pub fn poll(s: *@This(), t: ?f64) []struct { i64, i16 } { _ = s; _ = t; return &.{}; } }{}";
const kqueue_struct = "struct { _kq: i32 = -1, _closed: bool = false, pub fn close(s: *@This()) void { s._closed = true; } pub fn closed(s: *@This()) bool { return s._closed; } pub fn fileno(s: *@This()) i32 { return s._kq; } pub fn fromfd(s: *@This(), fd: i32) void { s._kq = fd; } pub fn control(s: *@This(), cl: anytype, m: usize, t: ?f64) []Kevent { _ = s; _ = cl; _ = m; _ = t; return &.{}; } }{}";
const kevent_struct = "struct { ident: usize = 0, filter: i16 = -1, flags: u16 = 1, fflags: u32 = 0, data: isize = 0, udata: ?*anyopaque = null }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "select", genSelect },
    .{ "poll", genPoll },
    .{ "epoll", genEpoll },
    .{ "devpoll", genDevpoll },
    .{ "kqueue", genKqueue },
    .{ "kevent", genKevent },
    .{ "POLLIN", genPollin },
    .{ "POLLPRI", genPollpri },
    .{ "POLLOUT", genPollout },
    .{ "POLLERR", genPollerr },
    .{ "POLLHUP", genPollhup },
    .{ "POLLNVAL", genPollnval },
    .{ "EPOLLIN", genEpollin },
    .{ "EPOLLOUT", genEpollout },
    .{ "EPOLLPRI", genEpollpri },
    .{ "EPOLLERR", genEpollerr },
    .{ "EPOLLHUP", genEpollhup },
    .{ "EPOLLET", genEpollet },
    .{ "EPOLLONESHOT", genEpolloneshot },
    .{ "EPOLLEXCLUSIVE", genEpollexclusive },
    .{ "EPOLLRDHUP", genEpollrdhup },
    .{ "EPOLLRDNORM", genEpollrdnorm },
    .{ "EPOLLRDBAND", genEpollrdband },
    .{ "EPOLLWRNORM", genEpollwrnorm },
    .{ "EPOLLWRBAND", genEpollwrband },
    .{ "EPOLLMSG", genEpollmsg },
    .{ "KQ_FILTER_READ", genKqFilterRead },
    .{ "KQ_FILTER_WRITE", genKqFilterWrite },
    .{ "KQ_FILTER_AIO", genKqFilterAio },
    .{ "KQ_FILTER_VNODE", genKqFilterVnode },
    .{ "KQ_FILTER_PROC", genKqFilterProc },
    .{ "KQ_FILTER_SIGNAL", genKqFilterSignal },
    .{ "KQ_FILTER_TIMER", genKqFilterTimer },
    .{ "KQ_EV_ADD", genKqEvAdd },
    .{ "KQ_EV_DELETE", genKqEvDelete },
    .{ "KQ_EV_ENABLE", genKqEvEnable },
    .{ "KQ_EV_DISABLE", genKqEvDisable },
    .{ "KQ_EV_ONESHOT", genKqEvOneshot },
    .{ "KQ_EV_CLEAR", genKqEvClear },
    .{ "KQ_EV_EOF", genKqEvEof },
    .{ "KQ_EV_ERROR", genKqEvError },
});

fn genSelect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ &[_]i64{}, &[_]i64{}, &[_]i64{} }"), builder_mod.EmitConfig.forExpression());
}

fn genPoll(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(poll_struct), builder_mod.EmitConfig.forExpression());
}

fn genEpoll(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(epoll_struct), builder_mod.EmitConfig.forExpression());
}

fn genDevpoll(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(devpoll_struct), builder_mod.EmitConfig.forExpression());
}

fn genKqueue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(kqueue_struct), builder_mod.EmitConfig.forExpression());
}

fn genKevent(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(kevent_struct), builder_mod.EmitConfig.forExpression());
}

fn genPollin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, 0x0001)"), builder_mod.EmitConfig.forExpression());
}

fn genPollpri(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, 0x0002)"), builder_mod.EmitConfig.forExpression());
}

fn genPollout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, 0x0004)"), builder_mod.EmitConfig.forExpression());
}

fn genPollerr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, 0x0008)"), builder_mod.EmitConfig.forExpression());
}

fn genPollhup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, 0x0010)"), builder_mod.EmitConfig.forExpression());
}

fn genPollnval(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, 0x0020)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x001)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x004)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollpri(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x002)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollerr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x008)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollhup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x010)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollet(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x80000000)"), builder_mod.EmitConfig.forExpression());
}

fn genEpolloneshot(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x40000000)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollexclusive(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x10000000)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollrdhup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x2000)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollrdnorm(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x040)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollrdband(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x080)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollwrnorm(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x100)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollwrband(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x200)"), builder_mod.EmitConfig.forExpression());
}

fn genEpollmsg(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x400)"), builder_mod.EmitConfig.forExpression());
}

fn genKqFilterRead(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, -1)"), builder_mod.EmitConfig.forExpression());
}

fn genKqFilterWrite(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, -2)"), builder_mod.EmitConfig.forExpression());
}

fn genKqFilterAio(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, -3)"), builder_mod.EmitConfig.forExpression());
}

fn genKqFilterVnode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, -4)"), builder_mod.EmitConfig.forExpression());
}

fn genKqFilterProc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, -5)"), builder_mod.EmitConfig.forExpression());
}

fn genKqFilterSignal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, -6)"), builder_mod.EmitConfig.forExpression());
}

fn genKqFilterTimer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, -7)"), builder_mod.EmitConfig.forExpression());
}

fn genKqEvAdd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0x0001)"), builder_mod.EmitConfig.forExpression());
}

fn genKqEvDelete(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0x0002)"), builder_mod.EmitConfig.forExpression());
}

fn genKqEvEnable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0x0004)"), builder_mod.EmitConfig.forExpression());
}

fn genKqEvDisable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0x0008)"), builder_mod.EmitConfig.forExpression());
}

fn genKqEvOneshot(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0x0010)"), builder_mod.EmitConfig.forExpression());
}

fn genKqEvClear(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0x0020)"), builder_mod.EmitConfig.forExpression());
}

fn genKqEvEof(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0x8000)"), builder_mod.EmitConfig.forExpression());
}

fn genKqEvError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0x4000)"), builder_mod.EmitConfig.forExpression());
}
