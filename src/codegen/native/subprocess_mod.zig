/// Python subprocess module - spawn new processes
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Zig 0.15: Child.init takes (argv, allocator) as positional args
// Zig 0.15: File.readToEndAlloc is the method to read all content

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "run", genRun },
    .{ "call", genCall },
    .{ "check_call", genCall },
    .{ "check_output", genCheckOutput },
    .{ "Popen", genPopen },
    .{ "getoutput", genGetOutput },
    .{ "getstatusoutput", genGetStatusOutput },
    .{ "PIPE", h.c("-1") }, .{ "STDOUT", h.c("-2") }, .{ "DEVNULL", h.c("-3") },
});

fn genRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("void{}"); return; }
    const label = try self.emitInlineBlockStart("run");
    try self.emit("const _cmd = "); try self.genExpr(args[0]);
    try self.emitFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _ = _child.spawn() catch break :{s} .{{ .returncode = -1, .stdout = \"\", .stderr = \"\" }}; const _r = _child.wait() catch break :{s} .{{ .returncode = -1, .stdout = \"\", .stderr = \"\" }}; break :{s} .{{ .returncode = @as(i64, @intCast(_r.Exited)), .stdout = \"\", .stderr = \"\" }}; ", .{ label, label, label });
    try self.emitInlineBlockEnd();
}

fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("void{}"); return; }
    const label = try self.emitInlineBlockStart("call");
    try self.emit("const _cmd = "); try self.genExpr(args[0]);
    try self.emitFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _ = _child.spawn() catch break :{s} @as(i64, -1); const _r = _child.wait() catch break :{s} @as(i64, -1); break :{s} @as(i64, @intCast(_r.Exited)); ", .{ label, label, label });
    try self.emitInlineBlockEnd();
}

fn genCheckOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    const label = try self.emitInlineBlockStart("chk");
    try self.emit("const _cmd = "); try self.genExpr(args[0]);
    try self.emitFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _child.stdout_behavior = .Pipe; _ = _child.spawn() catch break :{s} \"\"; const _out = _child.stdout.?.readToEndAlloc(__global_allocator, 1024 * 1024) catch break :{s} \"\"; _ = _child.wait() catch unreachable; break :{s} _out; ", .{ label, label, label });
    try self.emitInlineBlockEnd();
}

fn genPopen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("void{}"); return; }
    const label = try self.emitInlineBlockStart("pop");
    try self.emit("const _cmd = "); try self.genExpr(args[0]);
    try self.emitFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _child.stdout_behavior = .Pipe; _child.stderr_behavior = .Pipe; break :{s} _child; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genGetOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    const label = try self.emitInlineBlockStart("gout");
    try self.emit("const _cmd = "); try self.genExpr(args[0]);
    try self.emitFmt("; const _argv = [_][]const u8{{ \"/bin/sh\", \"-c\", _cmd }}; var _child = std.process.Child.init(&_argv, __global_allocator); _child.stdout_behavior = .Pipe; _ = _child.spawn() catch break :{s} \"\"; const _out = _child.stdout.?.readToEndAlloc(__global_allocator, 1024 * 1024) catch break :{s} \"\"; _ = _child.wait() catch unreachable; break :{s} _out; ", .{ label, label, label });
    try self.emitInlineBlockEnd();
}

fn genGetStatusOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ @as(i64, -1), \"\" }"); return; }
    const label = try self.emitInlineBlockStart("gso");
    try self.emit("const _cmd = "); try self.genExpr(args[0]);
    try self.emitFmt("; const _argv = [_][]const u8{{ \"/bin/sh\", \"-c\", _cmd }}; var _child = std.process.Child.init(&_argv, __global_allocator); _child.stdout_behavior = .Pipe; _ = _child.spawn() catch break :{s} .{{ @as(i64, -1), \"\" }}; const _out = _child.stdout.?.readToEndAlloc(__global_allocator, 1024 * 1024) catch break :{s} .{{ @as(i64, -1), \"\" }}; const _r = _child.wait() catch break :{s} .{{ @as(i64, -1), _out }}; break :{s} .{{ @as(i64, @intCast(_r.Exited)), _out }}; ", .{ label, label, label, label });
    try self.emitInlineBlockEnd();
}
