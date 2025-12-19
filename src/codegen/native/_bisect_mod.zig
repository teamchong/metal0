/// Python _bisect module - C accelerator for bisect (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "bisect_left", genBisectLeft },
    .{ "bisect_right", genBisectRight },
    .{ "bisect", genBisectRight },
    .{ "insort_left", genInsort },
    .{ "insort_right", genInsort },
    .{ "insort", genInsort },
});

fn genBisectLeft(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("0");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("bsl", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const arr = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const x = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) {{ const mid = (lo + hi) / 2; if (arr[mid] < x) {{ lo = mid + 1; }} else {{ hi = mid; }} }} break :{s} @as(i64, @intCast(lo))", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

fn genBisectRight(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("0");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("bsr", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const arr = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const x = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) {{ const mid = (lo + hi) / 2; if (x < arr[mid]) {{ hi = mid; }} else {{ lo = mid + 1; }} }} break :{s} @as(i64, @intCast(lo))", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

fn genInsort(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    try b.write("{}");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
