/// Python copy module - copy, deepcopy
/// MIGRATED TO ZIGBUILDER
/// Uses runtime helpers to avoid comptime explosion from @typeInfo/@TypeOf/@hasField inline checks
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "copy", genCopy },
    .{ "deepcopy", genDeepcopy },
    .{ "replace", genReplace },
});

/// Generate copy.copy(obj) - shallow copy using runtime helper
/// Emits: try runtime.copy_ops.shallowCopy(@TypeOf(obj), __global_allocator, obj)
fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "void{}");
        return;
    }
    try emitConst(self, "try runtime.copy_ops.shallowCopy(@TypeOf(");
    try self.genExpr(args[0]);
    try emitConst(self, "), __global_allocator, ");
    try self.genExpr(args[0]);
    try emitConst(self, ")");
}

/// Generate copy.deepcopy(obj) - deep copy using runtime helper
/// Emits: try runtime.copy_ops.deepCopy(@TypeOf(obj), __global_allocator, obj)
pub fn genDeepcopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "void{}");
        return;
    }
    try emitConst(self, "try runtime.copy_ops.deepCopy(@TypeOf(");
    try self.genExpr(args[0]);
    try emitConst(self, "), __global_allocator, ");
    try self.genExpr(args[0]);
    try emitConst(self, ")");
}

fn genReplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try emitConst(self, "void{}");
    }
}
