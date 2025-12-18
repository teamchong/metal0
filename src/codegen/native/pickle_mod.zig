/// Python pickle module - Full object serialization with proper protocol support
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dumps", genDumps },
    .{ "loads", genLoads },
    .{ "dump", genDump },
    .{ "load", genLoad },
    .{ "HIGHEST_PROTOCOL", genHighestProtocol },
    .{ "DEFAULT_PROTOCOL", genDefaultProtocol },
    .{ "PicklingError", genPicklingError },
    .{ "UnpicklingError", genUnpicklingError },
    .{ "Pickler", genPickler },
    .{ "Unpickler", genUnpickler },
});

fn genDumps(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;

    // Get protocol if specified (2nd arg)
    var protocol: u8 = 4; // default
    if (args.len > 1 and args[1] == .constant and args[1].constant.value == .int) {
        protocol = @intCast(args[1].constant.value.int);
    }

    // Use the full pickle implementation
    try self.emit("(try runtime.pickle.dumpsWithProtocol(");
    try self.genExpr(args[0]);
    try self.emitFmt(", __global_allocator, {d}))", .{protocol});
}

fn genLoads(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("runtime.pickle.PickleValue{ .none = {} }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    // Use the compile-once helper to avoid @TypeOf introspection at each call site
    // This prevents comptime explosion when pickle.loads is called in loops
    try self.emit("runtime.pickle.loadsAny(");
    try self.genExpr(args[0]);
    try self.emit(", __global_allocator)");
}

fn genDump(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    const dump_id = self.nextNameId();
    try self.emitFmt("__m{d}_pickle_dump: {{ const _pickle_data = try runtime.pickle.dumps(", .{dump_id});
    try self.genExpr(args[0]);
    try self.emit(", __global_allocator); const _file = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; _ = _file.write(_pickle_data) catch 0; break :__m{d}_pickle_dump; }}", .{dump_id});
}

fn genLoad(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 1) {
        try b.emitValue(builder_mod.ZigValue.raw("runtime.pickle.PickleValue{ .none = {} }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const load_id = self.nextNameId();
    try self.emitFmt("__m{d}_pickle_load: {{ const _file = ", .{load_id});
    try self.genExpr(args[0]);
    try self.emit("; const _content = _file.readToEndAlloc(__global_allocator, 100 * 1024 * 1024) catch break :__m");
    try self.emitFmt("{d}_pickle_load runtime.pickle.PickleValue{{ .none = {{}} }}; break :__m{d}_pickle_load (runtime.pickle.loads(_content, __global_allocator) catch runtime.pickle.PickleValue{{ .none = {{}} }}); }}", .{ load_id, load_id });
}

fn genHighestProtocol(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(5), builder_mod.EmitConfig.forExpression());
}

fn genDefaultProtocol(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genPicklingError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.PicklingError"), builder_mod.EmitConfig.forExpression());
}

fn genUnpicklingError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.UnpicklingError"), builder_mod.EmitConfig.forExpression());
}

fn genPickler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("runtime.pickle.Pickler.init(__global_allocator, 4)"), builder_mod.EmitConfig.forExpression());
}

fn genUnpickler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("runtime.pickle.Unpickler"), builder_mod.EmitConfig.forExpression());
}
