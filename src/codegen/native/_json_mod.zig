/// Python _json module - C accelerator for json (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "encode_basestring", genEncodeBasestring },
    .{ "encode_basestring_ascii", genEncodeBasestringAscii },
    .{ "scanstring", genScanstring },
    .{ "make_encoder", genMakeEncoder },
    .{ "make_scanner", genMakeScanner },
});

fn genEncodeBasestring(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.string("\"\""), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("eb", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const s = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; var result: std.ArrayList(u8) = .{{}}; result.append(__global_allocator, '\"') catch @panic(\"json encode OOM\"); for (s) |c| {{ switch (c) {{ '\"' => result.appendSlice(__global_allocator, \"\\\\\\\"\") catch @panic(\"json encode OOM\"), '\\\\' => result.appendSlice(__global_allocator, \"\\\\\\\\\") catch @panic(\"json encode OOM\"), '\\n' => result.appendSlice(__global_allocator, \"\\\\n\") catch @panic(\"json encode OOM\"), '\\r' => result.appendSlice(__global_allocator, \"\\\\r\") catch @panic(\"json encode OOM\"), '\\t' => result.appendSlice(__global_allocator, \"\\\\t\") catch @panic(\"json encode OOM\"), else => result.append(__global_allocator, c) catch @panic(\"json encode OOM\"), }} }} result.append(__global_allocator, '\"') catch @panic(\"json encode OOM\"); break :{s} result.items", .{label});
        }
    }.emit);
}

fn genEncodeBasestringAscii(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.string("\"\""), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("eba", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const s = ");
            try c.genExpr(a[0]);
            // Note: The inner format string {x:0>4} must be escaped as {{x:0>4}} in the Zig string literal
            try c.emitFmt("; var result: std.ArrayList(u8) = .{{}}; result.append(__global_allocator, '\"') catch @panic(\"json encode OOM\"); for (s) |c| {{ if (c < 0x20 or c > 0x7e) {{ result.appendSlice(__global_allocator, \"\\\\u\") catch @panic(\"json encode OOM\"); var buf: [4]u8 = undefined; _ = std.fmt.bufPrint(&buf, \"{{x:0>4}}\", .{{c}}) catch unreachable; result.appendSlice(__global_allocator, &buf) catch @panic(\"json encode OOM\"); }} else {{ switch (c) {{ '\"' => result.appendSlice(__global_allocator, \"\\\\\\\"\") catch @panic(\"json encode OOM\"), '\\\\' => result.appendSlice(__global_allocator, \"\\\\\\\\\") catch @panic(\"json encode OOM\"), else => result.append(__global_allocator, c) catch @panic(\"json encode OOM\"), }} }} }} result.append(__global_allocator, '\"') catch @panic(\"json encode OOM\"); break :{s} result.items", .{label});
        }
    }.emit);
}

fn genScanstring(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 2) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", 0 }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("ss", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const string = ");
            try c.genExpr(a[0]);
            try c.emit("; const end_idx = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; _ = string; break :{s} .{{ \"\", end_idx }}", .{label});
        }
    }.emit);
}

fn genMakeEncoder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genMakeScanner(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}
