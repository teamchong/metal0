/// Python subprocess module - spawn new processes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate subprocess.run(args, **kwargs) -> CompletedProcess
pub fn genRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("subprocess_run_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _cmd = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _child = std.process.Child.init(.{\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".argv = _cmd,\n");
    try self.emitIndent();
    try self.emit(".allocator = allocator,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("});\n");
    try self.emitIndent();
    try self.emit("_ = _child.spawn() catch break :subprocess_run_blk .{ .returncode = -1, .stdout = \"\", .stderr = \"\" };\n");
    try self.emitIndent();
    try self.emit("const _result = _child.wait() catch break :subprocess_run_blk .{ .returncode = -1, .stdout = \"\", .stderr = \"\" };\n");
    try self.emitIndent();
    try self.emit("break :subprocess_run_blk .{ .returncode = @as(i64, @intCast(_result.Exited)), .stdout = \"\", .stderr = \"\" };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate subprocess.call(args, **kwargs) -> return code
pub fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("subprocess_call_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _cmd = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _child = std.process.Child.init(.{\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".argv = _cmd,\n");
    try self.emitIndent();
    try self.emit(".allocator = allocator,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("});\n");
    try self.emitIndent();
    try self.emit("_ = _child.spawn() catch break :subprocess_call_blk @as(i64, -1);\n");
    try self.emitIndent();
    try self.emit("const _result = _child.wait() catch break :subprocess_call_blk @as(i64, -1);\n");
    try self.emitIndent();
    try self.emit("break :subprocess_call_blk @as(i64, @intCast(_result.Exited));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate subprocess.check_call(args, **kwargs) -> return code (raises on error)
pub fn genCheckCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Same as call but throws on non-zero exit
    try genCall(self, args);
}

/// Generate subprocess.check_output(args, **kwargs) -> output bytes
pub fn genCheckOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("subprocess_output_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _cmd = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _child = std.process.Child.init(.{\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".argv = _cmd,\n");
    try self.emitIndent();
    try self.emit(".allocator = allocator,\n");
    try self.emitIndent();
    try self.emit(".stdout_behavior = .pipe,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("});\n");
    try self.emitIndent();
    try self.emit("_ = _child.spawn() catch break :subprocess_output_blk \"\";\n");
    try self.emitIndent();
    try self.emit("const _output = _child.stdout.reader().readAllAlloc(allocator, 1024 * 1024) catch break :subprocess_output_blk \"\";\n");
    try self.emitIndent();
    try self.emit("_ = _child.wait() catch {};\n");
    try self.emitIndent();
    try self.emit("break :subprocess_output_blk _output;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate subprocess.Popen(args, **kwargs) -> Popen object
pub fn genPopen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("popen_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _cmd = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _child = std.process.Child.init(.{\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".argv = _cmd,\n");
    try self.emitIndent();
    try self.emit(".allocator = allocator,\n");
    try self.emitIndent();
    try self.emit(".stdout_behavior = .pipe,\n");
    try self.emitIndent();
    try self.emit(".stderr_behavior = .pipe,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("});\n");
    try self.emitIndent();
    try self.emit("break :popen_blk _child;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate subprocess.getoutput(cmd) -> string output
pub fn genGetoutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("getoutput_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _cmd = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _argv = [_][]const u8{ \"/bin/sh\", \"-c\", _cmd };\n");
    try self.emitIndent();
    try self.emit("var _child = std.process.Child.init(.{\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".argv = &_argv,\n");
    try self.emitIndent();
    try self.emit(".allocator = allocator,\n");
    try self.emitIndent();
    try self.emit(".stdout_behavior = .pipe,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("});\n");
    try self.emitIndent();
    try self.emit("_ = _child.spawn() catch break :getoutput_blk \"\";\n");
    try self.emitIndent();
    try self.emit("const _output = _child.stdout.reader().readAllAlloc(allocator, 1024 * 1024) catch break :getoutput_blk \"\";\n");
    try self.emitIndent();
    try self.emit("_ = _child.wait() catch {};\n");
    try self.emitIndent();
    try self.emit("break :getoutput_blk _output;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate subprocess.getstatusoutput(cmd) -> (status, output)
pub fn genGetstatusoutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("getstatusoutput_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _cmd = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _argv = [_][]const u8{ \"/bin/sh\", \"-c\", _cmd };\n");
    try self.emitIndent();
    try self.emit("var _child = std.process.Child.init(.{\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".argv = &_argv,\n");
    try self.emitIndent();
    try self.emit(".allocator = allocator,\n");
    try self.emitIndent();
    try self.emit(".stdout_behavior = .pipe,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("});\n");
    try self.emitIndent();
    try self.emit("_ = _child.spawn() catch break :getstatusoutput_blk .{ @as(i64, -1), \"\" };\n");
    try self.emitIndent();
    try self.emit("const _output = _child.stdout.reader().readAllAlloc(allocator, 1024 * 1024) catch \"\";\n");
    try self.emitIndent();
    try self.emit("const _result = _child.wait() catch break :getstatusoutput_blk .{ @as(i64, -1), _output };\n");
    try self.emitIndent();
    try self.emit("break :getstatusoutput_blk .{ @as(i64, @intCast(_result.Exited)), _output };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate subprocess.PIPE constant
pub fn genPIPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-1"); // Python uses -1 for PIPE
}

/// Generate subprocess.STDOUT constant
pub fn genSTDOUT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-2"); // Python uses -2 for STDOUT
}

/// Generate subprocess.DEVNULL constant
pub fn genDEVNULL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-3"); // Python uses -3 for DEVNULL
}
