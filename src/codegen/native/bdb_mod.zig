/// Python bdb module - Debugger framework
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate bdb.Bdb(skip=None)
pub fn genBdb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .skip = null, .breaks = .{}, .fncache = .{}, .frame_returning = null }");
}

/// Generate bdb.Breakpoint(file, line, temporary=False, cond=None, funcname=None)
pub fn genBreakpoint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit(".{ .file = ");
        try self.genExpr(args[0]);
        try self.emit(", .line = ");
        try self.genExpr(args[1]);
        try self.emit(", .temporary = false, .cond = null, .funcname = null, .enabled = true, .ignore = 0, .hits = 0 }");
    } else {
        try self.emit(".{ .file = \"\", .line = 0, .temporary = false, .cond = null, .funcname = null, .enabled = true, .ignore = 0, .hits = 0 }");
    }
}

/// Generate bdb.effective(file, line, frame)
pub fn genEffective(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ null, false }");
}

/// Generate bdb.checkfuncname(b, frame)
pub fn genCheckfuncname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate bdb.set_trace(frame=None)
pub fn genSetTrace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate bdb.BdbQuit exception
pub fn genBdbQuit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.BdbQuit");
}

/// Generate Bdb.reset()
pub fn genReset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Bdb.trace_dispatch(frame, event, arg)
pub fn genTraceDispatch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.dispatch_line(frame)
pub fn genDispatchLine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.dispatch_call(frame, arg)
pub fn genDispatchCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.dispatch_return(frame, arg)
pub fn genDispatchReturn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.dispatch_exception(frame, arg)
pub fn genDispatchException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.is_skipped_module(module_name)
pub fn genIsSkippedModule(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Bdb.stop_here(frame)
pub fn genStopHere(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Bdb.break_here(frame)
pub fn genBreakHere(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Bdb.break_anywhere(frame)
pub fn genBreakAnywhere(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Bdb.set_step()
pub fn genSetStep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Bdb.set_next(frame)
pub fn genSetNext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Bdb.set_return(frame)
pub fn genSetReturn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Bdb.set_until(frame, lineno=None)
pub fn genSetUntil(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Bdb.set_continue()
pub fn genSetContinue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Bdb.set_quit()
pub fn genSetQuit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Bdb.set_break(filename, lineno, temporary=False, cond=None, funcname=None)
pub fn genSetBreak(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.clear_break(filename, lineno)
pub fn genClearBreak(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.clear_bpbynumber(arg)
pub fn genClearBpbynumber(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.clear_all_file_breaks(filename)
pub fn genClearAllFileBreaks(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.clear_all_breaks()
pub fn genClearAllBreaks(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.get_bpbynumber(arg)
pub fn genGetBpbynumber(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.get_break(filename, lineno)
pub fn genGetBreak(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Bdb.get_breaks(filename, lineno)
pub fn genGetBreaks(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate Bdb.get_file_breaks(filename)
pub fn genGetFileBreaks(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]i64{}");
}

/// Generate Bdb.get_all_breaks()
pub fn genGetAllBreaks(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate Bdb.get_stack(f, t)
pub fn genGetStack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ &[_]@TypeOf(.{}){}, 0 }");
}

/// Generate Bdb.format_stack_entry(frame_lineno, lprefix=': ')
pub fn genFormatStackEntry(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate Bdb.run(cmd, globals=None, locals=None)
pub fn genRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Bdb.runeval(expr, globals=None, locals=None)
pub fn genRuneval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.runctx(cmd, globals, locals)
pub fn genRunctx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Bdb.runcall(func, *args, **kwds)
pub fn genRuncall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Bdb.canonic(filename)
pub fn genCanonic(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}
