/// Python select module - I/O multiplexing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "select", genSelect },
    .{ "poll", genPoll },
    .{ "epoll", genEpoll },
    .{ "devpoll", genDevpoll },
    .{ "kqueue", genKqueue },
    .{ "kevent", genKevent },
    .{ "POLLIN", genPOLLIN },
    .{ "POLLPRI", genPOLLPRI },
    .{ "POLLOUT", genPOLLOUT },
    .{ "POLLERR", genPOLLERR },
    .{ "POLLHUP", genPOLLHUP },
    .{ "POLLNVAL", genPOLLNVAL },
    .{ "EPOLLIN", genEPOLLIN },
    .{ "EPOLLOUT", genEPOLLOUT },
    .{ "EPOLLPRI", genEPOLLPRI },
    .{ "EPOLLERR", genEPOLLERR },
    .{ "EPOLLHUP", genEPOLLHUP },
    .{ "EPOLLET", genEPOLLET },
    .{ "EPOLLONESHOT", genEPOLLONESHOT },
    .{ "EPOLLEXCLUSIVE", genEPOLLEXCLUSIVE },
    .{ "EPOLLRDHUP", genEPOLLRDHUP },
    .{ "EPOLLRDNORM", genEPOLLRDNORM },
    .{ "EPOLLRDBAND", genEPOLLRDBAND },
    .{ "EPOLLWRNORM", genEPOLLWRNORM },
    .{ "EPOLLWRBAND", genEPOLLWRBAND },
    .{ "EPOLLMSG", genEPOLLMSG },
    .{ "KQ_FILTER_READ", genKQ_FILTER_READ },
    .{ "KQ_FILTER_WRITE", genKQ_FILTER_WRITE },
    .{ "KQ_FILTER_AIO", genKQ_FILTER_AIO },
    .{ "KQ_FILTER_VNODE", genKQ_FILTER_VNODE },
    .{ "KQ_FILTER_PROC", genKQ_FILTER_PROC },
    .{ "KQ_FILTER_SIGNAL", genKQ_FILTER_SIGNAL },
    .{ "KQ_FILTER_TIMER", genKQ_FILTER_TIMER },
    .{ "KQ_EV_ADD", genKQ_EV_ADD },
    .{ "KQ_EV_DELETE", genKQ_EV_DELETE },
    .{ "KQ_EV_ENABLE", genKQ_EV_ENABLE },
    .{ "KQ_EV_DISABLE", genKQ_EV_DISABLE },
    .{ "KQ_EV_ONESHOT", genKQ_EV_ONESHOT },
    .{ "KQ_EV_CLEAR", genKQ_EV_CLEAR },
    .{ "KQ_EV_EOF", genKQ_EV_EOF },
    .{ "KQ_EV_ERROR", genKQ_EV_ERROR },
});

/// Generate select.select(rlist, wlist, xlist, timeout=None)
pub fn genSelect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ &[_]i64{}, &[_]i64{}, &[_]i64{} }");
}

/// Generate select.poll()
pub fn genPoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("fds: std.ArrayList(struct { fd: i64, events: i16, revents: i16 }) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn register(__self: *@This(), fd: i64, eventmask: ?i16) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("__self.fds.append(__global_allocator, .{ .fd = fd, .events = eventmask orelse (POLLIN | POLLPRI), .revents = 0 }) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn modify(__self: *@This(), fd: i64, eventmask: i16) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("for (__self.fds.items) |*item| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (item.fd == fd) { item.events = eventmask; break; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn unregister(__self: *@This(), fd: i64) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("for (__self.fds.items, 0..) |item, i| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (item.fd == fd) { _ = __self.fds.orderedRemove(i); break; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn poll(__self: *@This(), timeout: ?i64) []struct { i64, i16 } {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = timeout;\n");
    try self.emitIndent();
    try self.emit("var result: std.ArrayList(struct { i64, i16 }) = .{};\n");
    try self.emitIndent();
    try self.emit("for (__self.fds.items) |item| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (item.revents != 0) result.append(__global_allocator, .{ item.fd, item.revents }) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("return result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate select.epoll(sizehint=-1, flags=0)
pub fn genEpoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_epfd: i32 = -1,\n");
    try self.emitIndent();
    try self.emit("_closed: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { __self._closed = true; }\n");
    try self.emitIndent();
    try self.emit("pub fn closed(__self: *@This()) bool { return __self._closed; }\n");
    try self.emitIndent();
    try self.emit("pub fn fileno(__self: *@This()) i32 { return __self._epfd; }\n");
    try self.emitIndent();
    try self.emit("pub fn fromfd(__self: *@This(), fd: i32) void { __self._epfd = fd; }\n");
    try self.emitIndent();
    try self.emit("pub fn register(__self: *@This(), fd: i64, eventmask: ?u32) void { _ = fd; _ = eventmask; }\n");
    try self.emitIndent();
    try self.emit("pub fn modify(__self: *@This(), fd: i64, eventmask: u32) void { _ = fd; _ = eventmask; }\n");
    try self.emitIndent();
    try self.emit("pub fn unregister(__self: *@This(), fd: i64) void { _ = fd; }\n");
    try self.emitIndent();
    try self.emit("pub fn poll(__self: *@This(), timeout: ?f64, maxevents: ?i32) []struct { i64, u32 } {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = timeout; _ = maxevents;\n");
    try self.emitIndent();
    try self.emit("return &.{};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate select.devpoll() (Solaris)
pub fn genDevpoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn register(__self: *@This(), fd: i64, eventmask: ?i16) void { _ = fd; _ = eventmask; }\n");
    try self.emitIndent();
    try self.emit("pub fn modify(__self: *@This(), fd: i64, eventmask: i16) void { _ = fd; _ = eventmask; }\n");
    try self.emitIndent();
    try self.emit("pub fn unregister(__self: *@This(), fd: i64) void { _ = fd; }\n");
    try self.emitIndent();
    try self.emit("pub fn poll(__self: *@This(), timeout: ?f64) []struct { i64, i16 } { _ = timeout; return &.{}; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate select.kqueue() (BSD/macOS)
pub fn genKqueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_kq: i32 = -1,\n");
    try self.emitIndent();
    try self.emit("_closed: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { __self._closed = true; }\n");
    try self.emitIndent();
    try self.emit("pub fn closed(__self: *@This()) bool { return __self._closed; }\n");
    try self.emitIndent();
    try self.emit("pub fn fileno(__self: *@This()) i32 { return __self._kq; }\n");
    try self.emitIndent();
    try self.emit("pub fn fromfd(__self: *@This(), fd: i32) void { __self._kq = fd; }\n");
    try self.emitIndent();
    try self.emit("pub fn control(__self: *@This(), changelist: anytype, max_events: usize, timeout: ?f64) []Kevent {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = changelist; _ = max_events; _ = timeout;\n");
    try self.emitIndent();
    try self.emit("return &.{};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate select.kevent(ident, filter=KQ_FILTER_READ, flags=KQ_EV_ADD, fflags=0, data=0, udata=0)
pub fn genKevent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("ident: usize = 0,\n");
    try self.emitIndent();
    try self.emit("filter: i16 = -1,\n");
    try self.emitIndent();
    try self.emit("flags: u16 = 1,\n");
    try self.emitIndent();
    try self.emit("fflags: u32 = 0,\n");
    try self.emitIndent();
    try self.emit("data: isize = 0,\n");
    try self.emitIndent();
    try self.emit("udata: ?*anyopaque = null,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

// ============================================================================
// Constants
// ============================================================================

/// Generate select.POLLIN
pub fn genPOLLIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, 0x0001)");
}

/// Generate select.POLLPRI
pub fn genPOLLPRI(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, 0x0002)");
}

/// Generate select.POLLOUT
pub fn genPOLLOUT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, 0x0004)");
}

/// Generate select.POLLERR
pub fn genPOLLERR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, 0x0008)");
}

/// Generate select.POLLHUP
pub fn genPOLLHUP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, 0x0010)");
}

/// Generate select.POLLNVAL
pub fn genPOLLNVAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, 0x0020)");
}

/// Generate select.EPOLLIN
pub fn genEPOLLIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x001)");
}

/// Generate select.EPOLLOUT
pub fn genEPOLLOUT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x004)");
}

/// Generate select.EPOLLPRI
pub fn genEPOLLPRI(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x002)");
}

/// Generate select.EPOLLERR
pub fn genEPOLLERR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x008)");
}

/// Generate select.EPOLLHUP
pub fn genEPOLLHUP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x010)");
}

/// Generate select.EPOLLET
pub fn genEPOLLET(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x80000000)");
}

/// Generate select.EPOLLONESHOT
pub fn genEPOLLONESHOT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x40000000)");
}

/// Generate select.EPOLLEXCLUSIVE
pub fn genEPOLLEXCLUSIVE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x10000000)");
}

/// Generate select.EPOLLRDHUP
pub fn genEPOLLRDHUP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x2000)");
}

/// Generate select.EPOLLRDNORM
pub fn genEPOLLRDNORM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x040)");
}

/// Generate select.EPOLLRDBAND
pub fn genEPOLLRDBAND(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x080)");
}

/// Generate select.EPOLLWRNORM
pub fn genEPOLLWRNORM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x100)");
}

/// Generate select.EPOLLWRBAND
pub fn genEPOLLWRBAND(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x200)");
}

/// Generate select.EPOLLMSG
pub fn genEPOLLMSG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x400)");
}

/// Generate select.KQ_FILTER_READ
pub fn genKQ_FILTER_READ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, -1)");
}

/// Generate select.KQ_FILTER_WRITE
pub fn genKQ_FILTER_WRITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, -2)");
}

/// Generate select.KQ_FILTER_AIO
pub fn genKQ_FILTER_AIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, -3)");
}

/// Generate select.KQ_FILTER_VNODE
pub fn genKQ_FILTER_VNODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, -4)");
}

/// Generate select.KQ_FILTER_PROC
pub fn genKQ_FILTER_PROC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, -5)");
}

/// Generate select.KQ_FILTER_SIGNAL
pub fn genKQ_FILTER_SIGNAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, -6)");
}

/// Generate select.KQ_FILTER_TIMER
pub fn genKQ_FILTER_TIMER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, -7)");
}

/// Generate select.KQ_EV_ADD
pub fn genKQ_EV_ADD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u16, 0x0001)");
}

/// Generate select.KQ_EV_DELETE
pub fn genKQ_EV_DELETE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u16, 0x0002)");
}

/// Generate select.KQ_EV_ENABLE
pub fn genKQ_EV_ENABLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u16, 0x0004)");
}

/// Generate select.KQ_EV_DISABLE
pub fn genKQ_EV_DISABLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u16, 0x0008)");
}

/// Generate select.KQ_EV_ONESHOT
pub fn genKQ_EV_ONESHOT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u16, 0x0010)");
}

/// Generate select.KQ_EV_CLEAR
pub fn genKQ_EV_CLEAR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u16, 0x0020)");
}

/// Generate select.KQ_EV_EOF
pub fn genKQ_EV_EOF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u16, 0x8000)");
}

/// Generate select.KQ_EV_ERROR
pub fn genKQ_EV_ERROR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u16, 0x4000)");
}

/// Kevent type reference
pub fn genKeventType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("const Kevent = struct { ident: usize, filter: i16, flags: u16, fflags: u32, data: isize, udata: ?*anyopaque };");
}
