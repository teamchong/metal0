/// Python contextlib module - Context managers
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "contextmanager", genContextmanager },
    .{ "suppress", genSuppress },
    .{ "redirect_stdout", genRedirectStdout },
    .{ "redirect_stderr", genRedirectStderr },
    .{ "closing", genClosing },
    .{ "nullcontext", genNullcontext },
    .{ "ExitStack", genExitStack },
});

fn genContextmanager(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { pub fn wrap(f: anytype) @TypeOf(f) { return f; } }.wrap"), builder_mod.EmitConfig.forExpression());
}

fn genSuppress(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { pub fn __enter__(__self: @This()) void { _ = &__self; } pub fn __exit__(__self: @This(), exc: anytype) bool { _ = &__self; _ = exc; return true; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genRedirectStdout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { pub fn __enter__(__self: @This()) void { _ = &__self; } pub fn __exit__(__self: @This(), exc: anytype) void { _ = &__self; _ = exc; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genRedirectStderr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { pub fn __enter__(__self: @This()) void { _ = &__self; } pub fn __exit__(__self: @This(), exc: anytype) void { _ = &__self; _ = exc; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genClosing(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("void{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genNullcontext(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genExitStack(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { stack: std.ArrayList(*anyopaque) = .{}, pub fn enter_context(__self: *@This(), cm: anytype) void { _ = __self; _ = cm; } pub fn close(__self: *@This()) void { __self.stack.deinit(__global_allocator); } }{}"), builder_mod.EmitConfig.forExpression());
}
