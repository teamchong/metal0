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
// re.sub(pattern, repl, string[, count[, flags]]) - 3-5 args
pub const genReSub = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.sub", .min_args = 3, .max_args = 5 });
// re.findall(pattern, string[, flags]) - 2-3 args
pub const genReFindall = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.findall", .min_args = 2, .max_args = 3 });
// re.compile(pattern[, flags]) - 1-2 args
pub const genReCompile = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.compile", .min_args = 1, .max_args = 2 });
// re.split(pattern, string[, maxsplit[, flags]]) - 2-4 args
pub const genReSplit = bridge.genVarArgCall(.{ .runtime_path = "runtime.re.split", .min_args = 2, .max_args = 4 });
