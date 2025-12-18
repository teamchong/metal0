/// Python copy module - copy, deepcopy
/// MIGRATED TO ZIGBUILDER
/// Uses runtime helpers to avoid comptime explosion from @typeInfo/@TypeOf/@hasField inline checks
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "copy", genCopy },
    .{ "deepcopy", genDeepcopy },
    .{ "replace", genReplace },
});

/// Generate copy.copy(obj) - shallow copy using runtime helper
/// Emits: try runtime.copy_ops.shallowCopy(@TypeOf(obj), __global_allocator, obj)
fn genCopy(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("void{}"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.emit("try runtime.copy_ops.shallowCopy(@TypeOf(");
    try self.genExpr(args[0]);
    try self.emit("), __global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate copy.deepcopy(obj) - deep copy using runtime helper
/// Emits: try runtime.copy_ops.deepCopy(@TypeOf(obj), __global_allocator, obj)
pub fn genDeepcopy(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("void{}"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.emit("try runtime.copy_ops.deepCopy(@TypeOf(");
    try self.genExpr(args[0]);
    try self.emit("), __global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

fn genReplace(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("void{}"), builder_mod.EmitConfig.forExpression());
    }
}
