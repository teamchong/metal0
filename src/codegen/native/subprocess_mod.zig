/// Python subprocess module - spawn new processes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "run", genRun }, .{ "call", genCall }, .{ "check_call", genCall }, .{ "check_output", genCheckOutput },
    .{ "Popen", genPopen }, .{ "getoutput", genGetoutput }, .{ "getstatusoutput", genGetstatusoutput },
    .{ "PIPE", genPIPE }, .{ "STDOUT", genSTDOUT }, .{ "DEVNULL", genDEVNULL },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genPIPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-1"); }
fn genSTDOUT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-2"); }
fn genDEVNULL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-3"); }

// Child process helper - emits common setup code
fn emitChildInit(self: *NativeCodegen, pipe_stdout: bool) CodegenError!void {
    try self.emit("var _child = std.process.Child.init(.{ .argv = _cmd, .allocator = allocator");
    if (pipe_stdout) try self.emit(", .stdout_behavior = .pipe");
    try self.emit(" });\n");
}

pub fn genRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _cmd = "); try self.genExpr(args[0]); try self.emit(";\n");
    try self.emitIndent(); try emitChildInit(self, false);
    try self.emitIndent(); try self.emit("_ = _child.spawn() catch break :blk .{ .returncode = -1, .stdout = \"\", .stderr = \"\" };\n");
    try self.emitIndent(); try self.emit("const _r = _child.wait() catch break :blk .{ .returncode = -1, .stdout = \"\", .stderr = \"\" };\n");
    try self.emitIndent(); try self.emit("break :blk .{ .returncode = @as(i64, @intCast(_r.Exited)), .stdout = \"\", .stderr = \"\" }; }");
}

pub fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _cmd = "); try self.genExpr(args[0]); try self.emit(";\n");
    try self.emitIndent(); try emitChildInit(self, false);
    try self.emitIndent(); try self.emit("_ = _child.spawn() catch break :blk @as(i64, -1);\n");
    try self.emitIndent(); try self.emit("const _r = _child.wait() catch break :blk @as(i64, -1);\n");
    try self.emitIndent(); try self.emit("break :blk @as(i64, @intCast(_r.Exited)); }");
}

pub fn genCheckOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _cmd = "); try self.genExpr(args[0]); try self.emit(";\n");
    try self.emitIndent(); try emitChildInit(self, true);
    try self.emitIndent(); try self.emit("_ = _child.spawn() catch break :blk \"\";\n");
    try self.emitIndent(); try self.emit("const _out = _child.stdout.reader().readAllAlloc(__global_allocator, 1024 * 1024) catch break :blk \"\";\n");
    try self.emitIndent(); try self.emit("_ = _child.wait() catch {}; break :blk _out; }");
}

pub fn genPopen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _cmd = "); try self.genExpr(args[0]); try self.emit(";\n");
    try self.emitIndent(); try self.emit("var _child = std.process.Child.init(.{ .argv = _cmd, .allocator = allocator, .stdout_behavior = .pipe, .stderr_behavior = .pipe });\n");
    try self.emitIndent(); try self.emit("break :blk _child; }");
}

fn genShellCmd(self: *NativeCodegen, args: []ast.Node, label: []const u8, result_type: []const u8) CodegenError!void {
    if (args.len == 0) return;
    try self.emit(label); try self.emit(": { const _cmd = "); try self.genExpr(args[0]); try self.emit(";\n");
    try self.emitIndent(); try self.emit("const _argv = [_][]const u8{ \"/bin/sh\", \"-c\", _cmd };\n");
    try self.emitIndent(); try self.emit("var _child = std.process.Child.init(.{ .argv = &_argv, .allocator = allocator, .stdout_behavior = .pipe });\n");
    try self.emitIndent(); try self.emit("_ = _child.spawn() catch break :"); try self.emit(label); try self.emit(" "); try self.emit(result_type); try self.emit(";\n");
    try self.emitIndent(); try self.emit("const _out = _child.stdout.reader().readAllAlloc(__global_allocator, 1024 * 1024) catch \"\";\n");
}

pub fn genGetoutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genShellCmd(self, args, "blk", "\"\"");
    try self.emitIndent(); try self.emit("_ = _child.wait() catch {}; break :blk _out; }");
}

pub fn genGetstatusoutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genShellCmd(self, args, "blk", ".{ @as(i64, -1), \"\" }");
    try self.emitIndent(); try self.emit("const _r = _child.wait() catch break :blk .{ @as(i64, -1), _out };\n");
    try self.emitIndent(); try self.emit("break :blk .{ @as(i64, @intCast(_r.Exited)), _out }; }");
}
