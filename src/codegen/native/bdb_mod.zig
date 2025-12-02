/// Python bdb module - Debugger framework
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Bdb", genBdb }, .{ "Breakpoint", genBreakpoint }, .{ "effective", genEffective },
    .{ "checkfuncname", genTrue }, .{ "set_trace", genUnit }, .{ "BdbQuit", genBdbQuit },
    .{ "reset", genUnit }, .{ "trace_dispatch", genNull }, .{ "dispatch_line", genNull },
    .{ "dispatch_call", genNull }, .{ "dispatch_return", genNull }, .{ "dispatch_exception", genNull },
    .{ "is_skipped_module", genFalse }, .{ "stop_here", genFalse }, .{ "break_here", genFalse },
    .{ "break_anywhere", genFalse }, .{ "set_step", genUnit }, .{ "set_next", genUnit },
    .{ "set_return", genUnit }, .{ "set_until", genUnit }, .{ "set_continue", genUnit },
    .{ "set_quit", genUnit }, .{ "set_break", genNull }, .{ "clear_break", genNull },
    .{ "clear_bpbynumber", genNull }, .{ "clear_all_file_breaks", genNull }, .{ "clear_all_breaks", genNull },
    .{ "get_bpbynumber", genNull }, .{ "get_break", genFalse }, .{ "get_breaks", genEmptyBpSlice },
    .{ "get_file_breaks", genEmptyI64Slice }, .{ "get_all_breaks", genEmpty },
    .{ "get_stack", genStackResult }, .{ "format_stack_entry", genEmptyStr },
    .{ "run", genUnit }, .{ "runeval", genNull }, .{ "runctx", genUnit }, .{ "runcall", genNull },
    .{ "canonic", genCanonic },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genEmptyBpSlice(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{}){}"); }
fn genEmptyI64Slice(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]i64{}"); }
fn genStackResult(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ &[_]@TypeOf(.{}){}, 0 }"); }
fn genEffective(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ null, false }"); }
fn genBdbQuit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.BdbQuit"); }

fn genBdb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .skip = null, .breaks = .{}, .fncache = .{}, .frame_returning = null }");
}

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
