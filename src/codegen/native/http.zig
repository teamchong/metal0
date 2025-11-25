/// HTTP module - using comptime bridge
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const bridge = @import("stdlib_bridge.zig");

// Comptime-generated handlers
pub const genHttpGet = bridge.genFieldAccessCall(.{ .runtime_path = "runtime.http.get", .arg_count = 1, .field = "body" });
pub const genHttpPost = bridge.genFieldAccessCall(.{ .runtime_path = "runtime.http.post", .arg_count = 2, .field = "body" });
