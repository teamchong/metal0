/// RE module - using comptime bridge
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const bridge = @import("stdlib_bridge.zig");

// Comptime-generated handlers (one line each!)
pub const genReSearch = bridge.genSimpleCall(.{ .runtime_path = "runtime.re.search", .arg_count = 2 });
pub const genReMatch = bridge.genSimpleCall(.{ .runtime_path = "runtime.re.match", .arg_count = 2 });
pub const genReSub = bridge.genSimpleCall(.{ .runtime_path = "runtime.re.sub", .arg_count = 3 });
pub const genReFindall = bridge.genSimpleCall(.{ .runtime_path = "runtime.re.findall", .arg_count = 2 });
pub const genReCompile = bridge.genSimpleCall(.{ .runtime_path = "runtime.re.compile", .arg_count = 1 });
pub const genReSplit = bridge.genSimpleCall(.{ .runtime_path = "runtime.re.split", .arg_count = 2 });
