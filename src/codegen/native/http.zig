/// HTTP module - using comptime bridge
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const bridge = @import("stdlib_bridge.zig");

/// Handler function type
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// HTTP module function map - exported for dispatch
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "get", genHttpGet },
    .{ "post", genHttpPost },
});

// Comptime-generated handlers - use PyObject wrappers for Python compatibility
pub const genHttpGet = bridge.genSimpleCall(.{ .runtime_path = "runtime.http.getAsPyString", .arg_count = 1 });
pub const genHttpPost = bridge.genSimpleCall(.{ .runtime_path = "runtime.http.postAsPyString", .arg_count = 2 });
