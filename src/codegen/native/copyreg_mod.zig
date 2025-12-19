/// Python copyreg module - Register pickle support functions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output - uses h.NativeCodegen from mod_helper
fn emitConst(self: *h.NativeCodegen, val: []const u8) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *h.NativeCodegen, comptime fmt: []const u8, args: anytype) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}



pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "pickle", genPickle },
    .{ "constructor", genConstructor },
    .{ "dispatch_table", genDispatchTable },
    .{ "_extension_registry", genExtensionRegistry },
    .{ "_inverted_registry", genInvertedRegistry },
    .{ "_extension_cache", genExtensionCache },
    .{ "add_extension", genAddExtension },
    .{ "remove_extension", genRemoveExtension },
    .{ "clear_extension_cache", genClearExtensionCache },
    .{ "__newobj__", genNewobj },
    .{ "__newobj_ex__", genNewobjEx },
});

fn genPickle(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genConstructor(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(?*const fn() anytype, null)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genDispatchTable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("hashmap_helper.AutoHashMap(usize, ?*anyopaque).init(__global_allocator)"), builder_mod.EmitConfig.forExpression());
}

fn genExtensionRegistry(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("hashmap_helper.StringHashMap(i32).init(__global_allocator)"), builder_mod.EmitConfig.forExpression());
}

fn genInvertedRegistry(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("hashmap_helper.AutoHashMap(i32, []const u8).init(__global_allocator)"), builder_mod.EmitConfig.forExpression());
}

fn genExtensionCache(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("hashmap_helper.AutoHashMap(i32, ?*anyopaque).init(__global_allocator)"), builder_mod.EmitConfig.forExpression());
}

fn genAddExtension(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genRemoveExtension(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genClearExtensionCache(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genNewobj(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("newobj", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const cls = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; break :{s} cls{{}}", .{label});
        }
    }.emit);
}

fn genNewobjEx(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("newobj_ex", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const cls = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; break :{s} cls{{}}", .{label});
        }
    }.emit);
}
