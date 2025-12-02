/// Python _multiprocessing module - Internal multiprocessing support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "sem_lock", genConst(".{ .kind = 0, .value = 1, .maxvalue = 1, .name = \"\" }") }, .{ "sem_unlink", genConst("{}") }, .{ "address_of_buffer", genConst(".{ @as(usize, 0), @as(usize, 0) }") },
    .{ "flags", genConst(".{ .HAVE_SEM_OPEN = true, .HAVE_SEM_TIMEDWAIT = true, .HAVE_FD_TRANSFER = true, .HAVE_BROKEN_SEM_GETVALUE = false }") },
    .{ "connection", genConst(".{ .handle = null, .readable = true, .writable = true }") }, .{ "send", genConst("{}") }, .{ "recv", genConst("null") },
    .{ "poll", genConst("false") }, .{ "send_bytes", genConst("{}") }, .{ "recv_bytes", genConst("\"\"") },
    .{ "recv_bytes_into", genConst("@as(usize, 0)") }, .{ "close", genConst("{}") }, .{ "fileno", genConst("@as(i32, -1)") },
    .{ "acquire", genConst("true") }, .{ "release", genConst("{}") }, .{ "count", genConst("@as(i32, 0)") }, .{ "is_mine", genConst("false") },
    .{ "get_value", genConst("@as(i32, 1)") }, .{ "is_zero", genConst("false") }, .{ "rebuild", genConst(".{ .kind = 0, .value = 1, .maxvalue = 1, .name = \"\" }") },
});
