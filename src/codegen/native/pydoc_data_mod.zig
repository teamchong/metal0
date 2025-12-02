/// Python pydoc_data module - Pydoc data files
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "topics", genTopics },
});

/// Generate pydoc_data.topics dict - Documentation topics
pub fn genTopics(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}
