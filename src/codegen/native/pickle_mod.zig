/// Python pickle module - Full object serialization with proper protocol support
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

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
    try self.emit("(try runtime.pickle.dumpsWithProtocol(");
    try self.genExpr(args[0]);
    try self.emitFmt(", __global_allocator, {d}))", .{protocol});
}

fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("runtime.Py_None");
        return;
    }
    // Use the compile-once helper to avoid @TypeOf introspection at each call site
    // This prevents comptime explosion when pickle.loads is called in loops
    // Returns *PyObject like json.loads() for Python compatibility
    try self.emitCallCtx("runtime.pickle.loadsAny", args[0], struct {
        pub fn f(s: *NativeCodegen, arg: ast.Node) CodegenError!void {
            try s.genExpr(arg);
            try s.emit(", __global_allocator");
        }
    }.f);
}

fn genDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("pickle_dump", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _pickle_data = try runtime.pickle.dumps(");
            try c.genExpr(a[0]);
            try c.emit(", __global_allocator); const _file = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; _ = _file.write(_pickle_data) catch 0; break :{s}", .{label});
        }
    }.emit);
}

fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit("runtime.Py_None");
        return;
    }
    // pickle.load() now returns *PyObject like json.load()
    try self.withInlineBlock("pickle_load", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _file = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const _content = _file.readToEndAlloc(__global_allocator, 100 * 1024 * 1024) catch break :{s} runtime.Py_None; break :{s} (runtime.pickle.loads(_content, __global_allocator) catch runtime.Py_None)", .{ label, label });
        }
    }.emit);
}

fn genHighestProtocol(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("5");
}

fn genDefaultProtocol(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("4");
}

fn genPicklingError(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("error.PicklingError");
}

fn genUnpicklingError(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("error.UnpicklingError");
}

fn genPickler(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("runtime.pickle.Pickler.init(__global_allocator, 4)");
}

fn genUnpickler(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("runtime.pickle.Unpickler");
}
