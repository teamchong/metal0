/// Python bdb module - Debugger framework
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Bdb", genBdb },
    .{ "Breakpoint", genBreakpoint },
    .{ "effective", genEffective },
    .{ "checkfuncname", genTrue },
    .{ "set_trace", genVoid },
    .{ "BdbQuit", genBdbQuit },
    .{ "reset", genVoid },
    .{ "trace_dispatch", genNull },
    .{ "dispatch_line", genNull },
    .{ "dispatch_call", genNull },
    .{ "dispatch_return", genNull },
    .{ "dispatch_exception", genNull },
    .{ "is_skipped_module", genFalse },
    .{ "stop_here", genFalse },
    .{ "break_here", genFalse },
    .{ "break_anywhere", genFalse },
    .{ "set_step", genVoid },
    .{ "set_next", genVoid },
    .{ "set_return", genVoid },
    .{ "set_until", genVoid },
    .{ "set_continue", genVoid },
    .{ "set_quit", genVoid },
    .{ "set_break", genNull },
    .{ "clear_break", genNull },
    .{ "clear_bpbynumber", genNull },
    .{ "clear_all_file_breaks", genNull },
    .{ "clear_all_breaks", genNull },
    .{ "get_bpbynumber", genNull },
    .{ "get_break", genFalse },
    .{ "get_breaks", genGetBreaks },
    .{ "get_file_breaks", genGetFileBreaks },
    .{ "get_all_breaks", genGetAllBreaks },
    .{ "get_stack", genGetStack },
    .{ "format_stack_entry", genEmptyString },
    .{ "run", genVoid },
    .{ "runeval", genNull },
    .{ "runctx", genVoid },
    .{ "runcall", genNull },
    .{ "canonic", genCanonic },
});

fn genBdb(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .skip = null, .breaks = .{}, .fncache = .{}, .frame_returning = null }"), builder_mod.EmitConfig.forExpression());
}

fn genBreakpoint(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        try self.withInlineBlock("bp", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v0 = ");
                try c.genExpr(a[0]);
                try c.emit("; const __v1 = ");
                try c.genExpr(a[1]);
                try c.emitFmt("; break :{s} .{{ .file = __v0, .line = __v1, .temporary = false, .cond = null, .funcname = null, .enabled = true, .ignore = 0, .hits = 0 }}", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .file = \"\", .line = 0, .temporary = false, .cond = null, .funcname = null, .enabled = true, .ignore = 0, .hits = 0 }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genEffective(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ null, false }"), builder_mod.EmitConfig.forExpression());
}

fn genTrue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genFalse(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genVoid(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genNull(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genBdbQuit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.BdbQuit"), builder_mod.EmitConfig.forExpression());
}

fn genGetBreaks(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{}){}"), builder_mod.EmitConfig.forExpression());
}

fn genGetFileBreaks(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]i64{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetAllBreaks(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetStack(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ &[_]@TypeOf(.{}){}, 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genEmptyString(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genCanonic(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}
