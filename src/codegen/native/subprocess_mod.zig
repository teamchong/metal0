/// Python subprocess module - spawn new processes
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Zig 0.15: Child.init takes (argv, allocator) as positional args
// Zig 0.15: File.readToEndAlloc is the method to read all content

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "run", genRun },
    .{ "call", genCall },
    .{ "check_call", genCall },
    .{ "check_output", genCheckOutput },
    .{ "Popen", genPopen },
    .{ "getoutput", genGetOutput },
    .{ "getstatusoutput", genGetStatusOutput },
    .{ "PIPE", h.c("-1") }, .{ "STDOUT", h.c("-2") }, .{ "DEVNULL", h.c("-3") },
});

fn genRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "void{}");
        return;
    }
    try self.withInlineBlock("run", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _cmd = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _ = _child.spawn() catch break :{s} .{{ .returncode = -1, .stdout = \"\", .stderr = \"\" }}; const _r = _child.wait() catch break :{s} .{{ .returncode = -1, .stdout = \"\", .stderr = \"\" }}; break :{s} .{{ .returncode = @as(i64, @intCast(_r.Exited)), .stdout = \"\", .stderr = \"\" }}", .{ label, label, label });
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "void{}");
        return;
    }
    try self.withInlineBlock("call", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _cmd = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _ = _child.spawn() catch break :{s} @as(i64, -1); const _r = _child.wait() catch break :{s} @as(i64, -1); break :{s} @as(i64, @intCast(_r.Exited))", .{ label, label, label });
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genCheckOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "\"\"");
        return;
    }
    try self.withInlineBlock("chk", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _cmd = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _child.stdout_behavior = .Pipe; _ = _child.spawn() catch break :{s} \"\"; const _out = _child.stdout.?.readToEndAlloc(__global_allocator, 1024 * 1024) catch break :{s} \"\"; _ = _child.wait() catch unreachable; break :{s} _out", .{ label, label, label });
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genPopen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "void{}");
        return;
    }
    try self.withInlineBlock("pop", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _cmd = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; var _child = std.process.Child.init(&_cmd, __global_allocator); _child.stdout_behavior = .Pipe; _child.stderr_behavior = .Pipe; break :{s} _child", .{label});
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genGetOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "\"\"");
        return;
    }
    try self.withInlineBlock("gout", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _cmd = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; const _argv = [_][]const u8{{ \"/bin/sh\", \"-c\", _cmd }}; var _child = std.process.Child.init(&_argv, __global_allocator); _child.stdout_behavior = .Pipe; _ = _child.spawn() catch break :{s} \"\"; const _out = _child.stdout.?.readToEndAlloc(__global_allocator, 1024 * 1024) catch break :{s} \"\"; _ = _child.wait() catch unreachable; break :{s} _out", .{ label, label, label });
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genGetStatusOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, ".{ @as(i64, -1), \"\" }");
        return;
    }
    try self.withInlineBlock("gso", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _cmd = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; const _argv = [_][]const u8{{ \"/bin/sh\", \"-c\", _cmd }}; var _child = std.process.Child.init(&_argv, __global_allocator); _child.stdout_behavior = .Pipe; _ = _child.spawn() catch break :{s} .{{ @as(i64, -1), \"\" }}; const _out = _child.stdout.?.readToEndAlloc(__global_allocator, 1024 * 1024) catch break :{s} .{{ @as(i64, -1), \"\" }}; const _r = _child.wait() catch break :{s} .{{ @as(i64, -1), _out }}; break :{s} .{{ @as(i64, @intCast(_r.Exited)), _out }}", .{ label, label, label, label });
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}
