/// Python _posixsubprocess module - Internal posixsubprocess support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _posixsubprocess.fork_exec(args, executable_list, close_fds, pass_fds, cwd, env, p2cread, p2cwrite, c2pread, c2pwrite, errread, errwrite, errpipe_read, errpipe_write, restore_signals, call_setsid, pgid_to_set, gid, extra_groups, uid, child_umask, preexec_fn, use_vfork)
pub fn genForkExec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -1)");
}

/// Generate _posixsubprocess.cloexec_pipe()
pub fn genCloexecPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, -1), @as(i32, -1) }");
}
