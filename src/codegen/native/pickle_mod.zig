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
    const b = try self.getBuilder();
    try b.write("(try runtime.pickle.dumpsWithProtocol(");
    const output1 = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output1);
    try self.genExpr(args[0]);
    {
        const b2 = try self.getBuilder();
        try b2.writeFmt(", __global_allocator, {d}))", .{protocol});
        const output2 = b2.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output2);
    }
}

fn genLoads(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("runtime.pickle.PickleValue{ .none = {} }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    // Use the compile-once helper to avoid @TypeOf introspection at each call site
    // This prevents comptime explosion when pickle.loads is called in loops
    const b = try self.getBuilder();
    try b.write("runtime.pickle.loadsAny(");
    const output1 = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output1);
    try self.genExpr(args[0]);
    {
        const b2 = try self.getBuilder();
        try b2.write(", __global_allocator)");
        const output2 = b2.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output2);
    }
}

fn genDump(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("pickle_dump", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _pickle_data = try runtime.pickle.dumps(");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write(", __global_allocator); const _file = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; _ = _file.write(_pickle_data) catch 0; break :{s}", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

fn genLoad(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len < 1) {
        const b = try self.getBuilder();
        try b.write("runtime.pickle.PickleValue{ .none = {} }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("pickle_load", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _file = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; const _content = _file.readToEndAlloc(__global_allocator, 100 * 1024 * 1024) catch break :{s} runtime.pickle.PickleValue{{ .none = {{}} }}; break :{s} (runtime.pickle.loads(_content, __global_allocator) catch runtime.pickle.PickleValue{{ .none = {{}} }})", .{ label, label });
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genHighestProtocol(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("5");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genDefaultProtocol(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("4");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genPicklingError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("error.PicklingError");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genUnpicklingError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("error.UnpicklingError");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genPickler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("runtime.pickle.Pickler.init(__global_allocator, 4)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genUnpickler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("runtime.pickle.Unpickler");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
