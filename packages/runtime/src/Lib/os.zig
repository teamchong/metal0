/// os module - Operating system interfaces
/// CPython Reference: https://docs.python.org/3.12/library/os.html
///
/// This module provides a modular implementation of Python's os module:
/// - constants.zig - Platform constants (sep, pathsep, name, etc.)
/// - env.zig - Environment variables (getenv, getenvDefault)
/// - fd.zig - File descriptor operations (open, close, read, write)
/// - file_ops.zig - File operations (listdir, mkdir, remove, rename, etc.)
/// - path.zig - os.path submodule (join, basename, dirname, etc.)
/// - process.zig - Process operations (getcwd, chdir, fork, exec, wait, etc.)
/// - stat.zig - stat_result and stat operations (stat, lstat, fstat)
/// - walk.zig - Directory traversal (walk, WalkEntry, WalkIterator)

// Re-export all submodules
pub const constants = @import("os/constants.zig");
pub const env = @import("os/env.zig");
pub const fd = @import("os/fd.zig");
pub const file_ops = @import("os/file_ops.zig");
pub const path = @import("os/path.zig");
pub const process = @import("os/process.zig");
pub const stat_mod = @import("os/stat.zig");
pub const walk = @import("os/walk.zig");

// Re-export constants at top level
pub const sep = constants.sep;
pub const altsep = constants.altsep;
pub const pathsep = constants.pathsep;
pub const linesep = constants.linesep;
pub const curdir = constants.curdir;
pub const pardir = constants.pardir;
pub const extsep = constants.extsep;
pub const devnull = constants.devnull;
pub const name = constants.name;

// Re-export environment functions
pub const getenv = env.getenv;
pub const getenvDefault = env.getenvDefault;

// Re-export file descriptor functions
pub const open = fd.open;
pub const close = fd.close;
pub const read = fd.read;
pub const write = fd.write;

// Re-export file operation functions
pub const listdir = file_ops.listdir;
pub const mkdir = file_ops.mkdir;
pub const makedirs = file_ops.makedirs;
pub const remove = file_ops.remove;
pub const unlink = file_ops.unlink;
pub const rmdir = file_ops.rmdir;
pub const removedirs = file_ops.removedirs;
pub const rename = file_ops.rename;
pub const exists = file_ops.exists;
pub const isfile = file_ops.isfile;
pub const isdir = file_ops.isdir;
pub const getsize = file_ops.getsize;

// Re-export process functions
pub const getcwd = process.getcwd;
pub const chdir = process.chdir;
pub const getpid = process.getpid;
pub const getppid = process.getppid;
pub const fork = process.fork;
pub const execv = process.execv;
pub const execve = process.execve;
pub const execvp = process.execvp;
pub const _exit = process._exit;
pub const wait = process.wait;
pub const waitpid = process.waitpid;
pub const kill = process.kill;
pub const getuid = process.getuid;
pub const geteuid = process.geteuid;
pub const getgid = process.getgid;
pub const getegid = process.getegid;
pub const setsid = process.setsid;
pub const setuid = process.setuid;
pub const setgid = process.setgid;
pub const WNOHANG = process.WNOHANG;
pub const WUNTRACED = process.WUNTRACED;
pub const WEXITSTATUS = process.WEXITSTATUS;
pub const WIFEXITED = process.WIFEXITED;
pub const WIFSIGNALED = process.WIFSIGNALED;
pub const WTERMSIG = process.WTERMSIG;
pub const WIFSTOPPED = process.WIFSTOPPED;
pub const WSTOPSIG = process.WSTOPSIG;

// Re-export stat types and functions
pub const stat_result = stat_mod.stat_result;
pub const StatResult = stat_mod.StatResult;
pub const stat = stat_mod.stat;
pub const lstat = stat_mod.lstat;
pub const fstat = stat_mod.fstat;

// Re-export walk types and functions
pub const WalkEntry = walk.WalkEntry;
pub const WalkIterator = walk.WalkIterator;
// Note: walk.walk and walk.walkTopdown need to be accessed as @import("os/walk.zig").walk
// because they are functions that need allocator context
