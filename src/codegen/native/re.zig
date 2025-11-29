/// RE module - using comptime bridge
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const bridge = @import("stdlib_bridge.zig");

// Comptime-generated handlers with variable args support for flags
// re.search(pattern, string[, flags]) - 2-3 args
pub const genReSearch = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.search", .min_args = 2, .max_args = 3 });
// re.match(pattern, string[, flags]) - 2-3 args
pub const genReMatch = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.match", .min_args = 2, .max_args = 3 });
// re.fullmatch(pattern, string[, flags]) - 2-3 args
pub const genReFullmatch = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.fullmatch", .min_args = 2, .max_args = 3 });
// re.sub(pattern, repl, string[, count[, flags]]) - 3-5 args
pub const genReSub = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.sub", .min_args = 3, .max_args = 5 });
// re.subn(pattern, repl, string[, count[, flags]]) - 3-5 args (returns tuple)
pub const genReSubn = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.subn", .min_args = 3, .max_args = 5 });
// re.findall(pattern, string[, flags]) - 2-3 args
pub const genReFindall = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.findall", .min_args = 2, .max_args = 3 });
// re.finditer(pattern, string[, flags]) - 2-3 args (returns iterator)
pub const genReFinditer = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.finditer", .min_args = 2, .max_args = 3 });
// re.compile(pattern[, flags]) - 1-2 args
pub const genReCompile = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.compile", .min_args = 1, .max_args = 2 });
// re.split(pattern, string[, maxsplit[, flags]]) - 2-4 args
pub const genReSplit = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.split", .min_args = 2, .max_args = 4 });
// re.escape(pattern) - 1 arg
pub const genReEscape = bridge.genSimpleCall(.{ .runtime_path = "runtime.re.escape", .arg_count = 1 });
// re.purge() - 0 args
pub const genRePurge = bridge.genNoArgCall(.{ .runtime_path = "runtime.re.purge", .needs_allocator = false });

// re module flag constants
/// re.IGNORECASE / re.I - case insensitive matching
pub fn genIGNORECASE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 2)"); // re.IGNORECASE = 2
}

pub const genI = genIGNORECASE;

/// re.MULTILINE / re.M - ^ and $ match at line breaks
pub fn genMULTILINE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 8)"); // re.MULTILINE = 8
}

pub const genM = genMULTILINE;

/// re.DOTALL / re.S - dot matches newlines
pub fn genDOTALL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 16)"); // re.DOTALL = 16
}

pub const genS = genDOTALL;

/// re.VERBOSE / re.X - allow comments and whitespace in pattern
pub fn genVERBOSE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 64)"); // re.VERBOSE = 64
}

pub const genX = genVERBOSE;

/// re.ASCII / re.A - make \w, \W, \b, \B, \d, \D, \s, \S ASCII-only
pub fn genASCII(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 256)"); // re.ASCII = 256
}

pub const genA = genASCII;

/// re.LOCALE / re.L - locale-dependent matching
pub fn genLOCALE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 4)"); // re.LOCALE = 4
}

pub const genL = genLOCALE;

/// re.UNICODE / re.U - unicode matching (default in Python 3)
pub fn genUNICODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 32)"); // re.UNICODE = 32
}

pub const genU = genUNICODE;

/// re.error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.RegexError");
}

/// re.Pattern type
pub fn genPattern(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Pattern\"");
}

/// re.Match type
pub fn genMatch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Match\"");
}
