/// Python pickle module - Full object serialization with proper protocol support
const std = @import("std");
const h = @import("mod_helper.zig");
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
    if (args.len == 0) {
        try self.emit("runtime.pickle.PickleValue{ .none = {} }");
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
    try self.withInlineBlock("pickle_dump", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _pickle_data = try runtime.pickle.dumps(");
            try c.genExpr(a[0]);
            try c.emit(", __global_allocator); const _file = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; _ = _file.write(_pickle_data) catch 0; break :{s}", .{label});
        }
    }.emit);
}

fn genLoad(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len < 1) {
        try self.emit("runtime.pickle.PickleValue{ .none = {} }");
        return;
    }
    try self.withInlineBlock("pickle_load", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _file = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const _content = _file.readToEndAlloc(__global_allocator, 100 * 1024 * 1024) catch break :{s} runtime.pickle.PickleValue{{ .none = {{}} }}; break :{s} (runtime.pickle.loads(_content, __global_allocator) catch runtime.pickle.PickleValue{{ .none = {{}} }})", .{ label, label });
        }
    }.emit);
}

fn genHighestProtocol(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    // Emit directly to output buffer (not builder) for attribute access detection
    try self.emit("5");
}

fn genDefaultProtocol(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    // Emit directly to output buffer (not builder) for attribute access detection
    try self.emit("4");
}

fn genPicklingError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("error.PicklingError");
}

fn genUnpicklingError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("error.UnpicklingError");
}

fn genPickler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("runtime.pickle.Pickler.init(__global_allocator, 4)");
}

fn genUnpickler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("runtime.pickle.Unpickler");
}
