/// Python websocket module codegen - WebSocket client
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const bridge = @import("stdlib_bridge.zig");

/// Handler function type
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// WebSocket module function map - exported for dispatch
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "connect", genConnect },
});

/// websocket.connect(url) -> WebSocket object
pub const genConnect = bridge.genSimpleCall(.{ .runtime_path = "runtime.websocket.connect", .arg_count = 1 });
