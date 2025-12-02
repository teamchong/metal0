/// Python subprocess module - spawn new processes
const std = @import("std");
const h = @import("mod_helper.zig");

const child_init = "var _child = std.process.Child.init(.{ .argv = _cmd, .allocator = allocator";
const child_spawn = "_child.spawn() catch break :blk";
const child_wait = "_child.wait() catch break :blk";

const runBody = "; " ++ child_init ++ " }); _ = " ++ child_spawn ++ " .{ .returncode = -1, .stdout = \"\", .stderr = \"\" }; const _r = " ++ child_wait ++ " .{ .returncode = -1, .stdout = \"\", .stderr = \"\" }; break :blk .{ .returncode = @as(i64, @intCast(_r.Exited)), .stdout = \"\", .stderr = \"\" }; }";
const callBody = "; " ++ child_init ++ " }); _ = " ++ child_spawn ++ " @as(i64, -1); const _r = " ++ child_wait ++ " @as(i64, -1); break :blk @as(i64, @intCast(_r.Exited)); }";
const checkOutputBody = "; " ++ child_init ++ ", .stdout_behavior = .pipe }); _ = " ++ child_spawn ++ " \"\"; const _out = _child.stdout.reader().readAllAlloc(__global_allocator, 1024 * 1024) catch break :blk \"\"; _ = _child.wait() catch {}; break :blk _out; }";
const popenBody = "; var _child = std.process.Child.init(.{ .argv = _cmd, .allocator = allocator, .stdout_behavior = .pipe, .stderr_behavior = .pipe }); break :blk _child; }";
const getoutputBody = "; const _argv = [_][]const u8{ \"/bin/sh\", \"-c\", _cmd }; var _child = std.process.Child.init(.{ .argv = &_argv, .allocator = allocator, .stdout_behavior = .pipe }); _ = " ++ child_spawn ++ " \"\"; const _out = _child.stdout.reader().readAllAlloc(__global_allocator, 1024 * 1024) catch \"\"; _ = _child.wait() catch {}; break :blk _out; }";
const getstatusoutputBody = "; const _argv = [_][]const u8{ \"/bin/sh\", \"-c\", _cmd }; var _child = std.process.Child.init(.{ .argv = &_argv, .allocator = allocator, .stdout_behavior = .pipe }); _ = " ++ child_spawn ++ " .{ @as(i64, -1), \"\" }; const _out = _child.stdout.reader().readAllAlloc(__global_allocator, 1024 * 1024) catch \"\"; const _r = " ++ child_wait ++ " .{ @as(i64, -1), _out }; break :blk .{ @as(i64, @intCast(_r.Exited)), _out }; }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "run", h.wrap("blk: { const _cmd = ", runBody, "void{}") },
    .{ "call", h.wrap("blk: { const _cmd = ", callBody, "void{}") },
    .{ "check_call", h.wrap("blk: { const _cmd = ", callBody, "void{}") },
    .{ "check_output", h.wrap("blk: { const _cmd = ", checkOutputBody, "\"\"") },
    .{ "Popen", h.wrap("blk: { const _cmd = ", popenBody, "void{}") },
    .{ "getoutput", h.wrap("blk: { const _cmd = ", getoutputBody, "\"\"") },
    .{ "getstatusoutput", h.wrap("blk: { const _cmd = ", getstatusoutputBody, ".{ @as(i64, -1), \"\" }") },
    .{ "PIPE", h.c("-1") }, .{ "STDOUT", h.c("-2") }, .{ "DEVNULL", h.c("-3") },
});
