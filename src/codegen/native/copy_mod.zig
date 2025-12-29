/// Python copy module - copy, deepcopy
/// MIGRATED TO ZIGBUILDER
/// Uses runtime helpers to avoid comptime explosion from @typeInfo/@TypeOf/@hasField inline checks
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "copy", genCopy },
    .{ "deepcopy", genDeepcopy },
    .{ "replace", genReplace },
});

// === Structured helpers for copy operations ===

/// Helper: emit try runtime.copy_ops.{func}(@TypeOf(arg), __global_allocator, arg)
/// Uses auto-close pattern for guaranteed bracket matching
fn emitCopyCall(self: *NativeCodegen, func: []const u8, arg: ast.Node) CodegenError!void {
    try self.emit("try runtime.copy_ops.");
    try self.emit(func);
    const Ctx = struct { a: ast.Node };
    try self.emitCallCtx("", Ctx{ .a = arg }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emitCallCtx("@TypeOf", ctx.a, struct {
                pub fn inner(ss: *NativeCodegen, a: ast.Node) CodegenError!void {
                    try ss.genExpr(a);
                }
            }.inner);
            try s.emit(", __global_allocator, ");
            try s.genExpr(ctx.a);
        }
    }.f);
}

/// Generate copy.copy(obj) - shallow copy using runtime helper
/// Emits: try runtime.copy_ops.shallowCopy(@TypeOf(obj), __global_allocator, obj)
fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("void{}");
        return;
    }
    try emitCopyCall(self, "shallowCopy", args[0]);
}

/// Generate copy.deepcopy(obj) - deep copy using runtime helper
/// Emits: try runtime.copy_ops.deepCopy(@TypeOf(obj), __global_allocator, obj)
pub fn genDeepcopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("void{}");
        return;
    }
    try emitCopyCall(self, "deepCopy", args[0]);
}

fn genReplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("void{}");
    }
}
