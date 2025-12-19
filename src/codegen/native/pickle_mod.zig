/// Python pickle module - Full object serialization with proper protocol support
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

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

fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;

    // Get protocol if specified (2nd arg)
    var protocol: u8 = 4; // default
    if (args.len > 1 and args[1] == .constant and args[1].constant.value == .int) {
        protocol = @intCast(args[1].constant.value.int);
    }

    // Use the full pickle implementation
    try emitConst(self, "(try runtime.pickle.dumpsWithProtocol(");
    try self.genExpr(args[0]);
    try emitFmtConst(self, ", __global_allocator, {d}))", .{protocol});
}

fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "runtime.pickle.PickleValue{ .none = {} }");
        return;
    }
    // Use the compile-once helper to avoid @TypeOf introspection at each call site
    // This prevents comptime explosion when pickle.loads is called in loops
    try emitConst(self, "runtime.pickle.loadsAny(");
    try self.genExpr(args[0]);
    try emitConst(self, ", __global_allocator)");
}

fn genDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("pickle_dump", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const _pickle_data = try runtime.pickle.dumps(");
            try c.genExpr(a[0]);
            try emitConst(c, ", __global_allocator); const _file = ");
            try c.genExpr(a[1]);
            try emitFmtConst(c, "; _ = _file.write(_pickle_data) catch 0; break :{s}", .{label});
        }
    }.emit);
}

fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try emitConst(self, "runtime.pickle.PickleValue{ .none = {} }");
        return;
    }
    try self.withInlineBlock("pickle_load", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const _file = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; const _content = _file.readToEndAlloc(__global_allocator, 100 * 1024 * 1024) catch break :{s} runtime.pickle.PickleValue{{ .none = {{}} }}; break :{s} (runtime.pickle.loads(_content, __global_allocator) catch runtime.pickle.PickleValue{{ .none = {{}} }})", .{ label, label });
        }
    }.emit);
}

fn genHighestProtocol(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "5");
}

fn genDefaultProtocol(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "4");
}

fn genPicklingError(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "error.PicklingError");
}

fn genUnpicklingError(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "error.UnpicklingError");
}

fn genPickler(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "runtime.pickle.Pickler.init(__global_allocator, 4)");
}

fn genUnpickler(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "runtime.pickle.Unpickler");
}
