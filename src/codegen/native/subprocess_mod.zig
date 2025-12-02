/// Python subprocess module - spawn new processes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "run", genRun }, .{ "call", genCall }, .{ "check_call", genCall }, .{ "check_output", genCheckOutput },
    .{ "Popen", genPopen }, .{ "getoutput", genGetoutput }, .{ "getstatusoutput", genGetstatusoutput },
    .{ "PIPE", genConst("-1") }, .{ "STDOUT", genConst("-2") }, .{ "DEVNULL", genConst("-3") },
});

const child_init = "var _child = std.process.Child.init(.{ .argv = _cmd, .allocator = allocator";
const child_spawn = "_child.spawn() catch break :blk";
const child_wait = "_child.wait() catch break :blk";

pub fn genRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _cmd = "); try self.genExpr(args[0]);
    try self.emit("; " ++ child_init ++ " }); _ = " ++ child_spawn ++ " .{ .returncode = -1, .stdout = \"\", .stderr = \"\" }; const _r = " ++ child_wait ++ " .{ .returncode = -1, .stdout = \"\", .stderr = \"\" }; break :blk .{ .returncode = @as(i64, @intCast(_r.Exited)), .stdout = \"\", .stderr = \"\" }; }");
}

pub fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _cmd = "); try self.genExpr(args[0]);
    try self.emit("; " ++ child_init ++ " }); _ = " ++ child_spawn ++ " @as(i64, -1); const _r = " ++ child_wait ++ " @as(i64, -1); break :blk @as(i64, @intCast(_r.Exited)); }");
}

pub fn genCheckOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _cmd = "); try self.genExpr(args[0]);
    try self.emit("; " ++ child_init ++ ", .stdout_behavior = .pipe }); _ = " ++ child_spawn ++ " \"\"; const _out = _child.stdout.reader().readAllAlloc(__global_allocator, 1024 * 1024) catch break :blk \"\"; _ = _child.wait() catch {}; break :blk _out; }");
}

pub fn genPopen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _cmd = "); try self.genExpr(args[0]);
    try self.emit("; var _child = std.process.Child.init(.{ .argv = _cmd, .allocator = allocator, .stdout_behavior = .pipe, .stderr_behavior = .pipe }); break :blk _child; }");
}

pub fn genGetoutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _cmd = "); try self.genExpr(args[0]);
    try self.emit("; const _argv = [_][]const u8{ \"/bin/sh\", \"-c\", _cmd }; var _child = std.process.Child.init(.{ .argv = &_argv, .allocator = allocator, .stdout_behavior = .pipe }); _ = " ++ child_spawn ++ " \"\"; const _out = _child.stdout.reader().readAllAlloc(__global_allocator, 1024 * 1024) catch \"\"; _ = _child.wait() catch {}; break :blk _out; }");
}

pub fn genGetstatusoutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _cmd = "); try self.genExpr(args[0]);
    try self.emit("; const _argv = [_][]const u8{ \"/bin/sh\", \"-c\", _cmd }; var _child = std.process.Child.init(.{ .argv = &_argv, .allocator = allocator, .stdout_behavior = .pipe }); _ = " ++ child_spawn ++ " .{ @as(i64, -1), \"\" }; const _out = _child.stdout.reader().readAllAlloc(__global_allocator, 1024 * 1024) catch \"\"; const _r = " ++ child_wait ++ " .{ @as(i64, -1), _out }; break :blk .{ @as(i64, @intCast(_r.Exited)), _out }; }");
}
