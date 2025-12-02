/// Python bdb module - Debugger framework
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Bdb", genConst(".{ .skip = null, .breaks = .{}, .fncache = .{}, .frame_returning = null }") },
    .{ "Breakpoint", genBreakpoint }, .{ "effective", genConst(".{ null, false }") },
    .{ "checkfuncname", genConst("true") }, .{ "set_trace", genConst("{}") }, .{ "BdbQuit", genConst("error.BdbQuit") },
    .{ "reset", genConst("{}") }, .{ "trace_dispatch", genConst("null") }, .{ "dispatch_line", genConst("null") },
    .{ "dispatch_call", genConst("null") }, .{ "dispatch_return", genConst("null") }, .{ "dispatch_exception", genConst("null") },
    .{ "is_skipped_module", genConst("false") }, .{ "stop_here", genConst("false") }, .{ "break_here", genConst("false") },
    .{ "break_anywhere", genConst("false") }, .{ "set_step", genConst("{}") }, .{ "set_next", genConst("{}") },
    .{ "set_return", genConst("{}") }, .{ "set_until", genConst("{}") }, .{ "set_continue", genConst("{}") },
    .{ "set_quit", genConst("{}") }, .{ "set_break", genConst("null") }, .{ "clear_break", genConst("null") },
    .{ "clear_bpbynumber", genConst("null") }, .{ "clear_all_file_breaks", genConst("null") }, .{ "clear_all_breaks", genConst("null") },
    .{ "get_bpbynumber", genConst("null") }, .{ "get_break", genConst("false") }, .{ "get_breaks", genConst("&[_]@TypeOf(.{}){}") },
    .{ "get_file_breaks", genConst("&[_]i64{}") }, .{ "get_all_breaks", genConst(".{}") },
    .{ "get_stack", genConst(".{ &[_]@TypeOf(.{}){}, 0 }") }, .{ "format_stack_entry", genConst("\"\"") },
    .{ "run", genConst("{}") }, .{ "runeval", genConst("null") }, .{ "runctx", genConst("{}") }, .{ "runcall", genConst("null") },
    .{ "canonic", genCanonic },
});

fn genBreakpoint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit(".{ .file = "); try self.genExpr(args[0]);
        try self.emit(", .line = "); try self.genExpr(args[1]);
        try self.emit(", .temporary = false, .cond = null, .funcname = null, .enabled = true, .ignore = 0, .hits = 0 }");
    } else try self.emit(".{ .file = \"\", .line = 0, .temporary = false, .cond = null, .funcname = null, .enabled = true, .ignore = 0, .hits = 0 }");
}

fn genCanonic(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
