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
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_run: {{ const _cmd = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _ = _child.spawn() catch break :__m{d}_run .{{ .returncode = -1, .stdout = \"\", .stderr = \"\" }}; const _r = _child.wait() catch break :__m{d}_run .{{ .returncode = -1, .stdout = \"\", .stderr = \"\" }}; break :__m{d}_run .{{ .returncode = @as(i64, @intCast(_r.Exited)), .stdout = \"\", .stderr = \"\" }}; }})", .{ id, id, id });
}

fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("void{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_call: {{ const _cmd = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _ = _child.spawn() catch break :__m{d}_call @as(i64, -1); const _r = _child.wait() catch break :__m{d}_call @as(i64, -1); break :__m{d}_call @as(i64, @intCast(_r.Exited)); }})", .{ id, id, id });
}

fn genCheckOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_chk: {{ const _cmd = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _child.stdout_behavior = .Pipe; _ = _child.spawn() catch break :__m{d}_chk \"\"; const _out = _child.stdout.?.readToEndAlloc(__global_allocator, 1024 * 1024) catch break :__m{d}_chk \"\"; _ = _child.wait() catch unreachable; break :__m{d}_chk _out; }})", .{ id, id, id });
}

fn genPopen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("void{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_pop: {{ const _cmd = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _child.stdout_behavior = .Pipe; _child.stderr_behavior = .Pipe; break :__m{d}_pop _child; }})", .{id});
}

fn genGetOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_gout: {{ const _cmd = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; const _argv = [_][]const u8{{ \"/bin/sh\", \"-c\", _cmd }}; var _child = std.process.Child.init(&_argv, __global_allocator); _child.stdout_behavior = .Pipe; _ = _child.spawn() catch break :__m{d}_gout \"\"; const _out = _child.stdout.?.readToEndAlloc(__global_allocator, 1024 * 1024) catch break :__m{d}_gout \"\"; _ = _child.wait() catch unreachable; break :__m{d}_gout _out; }})", .{ id, id, id });
}

fn genGetStatusOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ @as(i64, -1), \"\" }"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_gso: {{ const _cmd = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; const _argv = [_][]const u8{{ \"/bin/sh\", \"-c\", _cmd }}; var _child = std.process.Child.init(&_argv, __global_allocator); _child.stdout_behavior = .Pipe; _ = _child.spawn() catch break :__m{d}_gso .{{ @as(i64, -1), \"\" }}; const _out = _child.stdout.?.readToEndAlloc(__global_allocator, 1024 * 1024) catch break :__m{d}_gso .{{ @as(i64, -1), \"\" }}; const _r = _child.wait() catch break :__m{d}_gso .{{ @as(i64, -1), _out }}; break :__m{d}_gso .{{ @as(i64, @intCast(_r.Exited)), _out }}; }})", .{ id, id, id, id });
}
