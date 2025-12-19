/// Python hashlib module - md5, sha1, sha256, sha512
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "md5", h.hashNew("md5") }, .{ "sha1", h.hashNew("sha1") }, .{ "sha224", h.hashNew("sha224") },
    .{ "sha256", h.hashNew("sha256") }, .{ "sha384", h.hashNew("sha384") }, .{ "sha512", h.hashNew("sha512") },
    .{ "new", genNew },
});

fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    if (args.len > 1) {
        try self.withInlineBlock("hash_new", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                const b = try c.getBuilder();
                try b.write("var _h = try hashlib.new(");
                const output1 = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output1);
                try c.genExpr(a[0]);
                {
                    const b2 = try c.getBuilder();
                    try b2.write("); _h.update(");
                    const output2 = b2.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output2);
                }
                try c.genExpr(a[1]);
                {
                    const b3 = try c.getBuilder();
                    try b3.writeFmt("); break :{s} _h", .{label});
                    const output3 = b3.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output3);
                }
            }
        }.emit);
    } else {
        const b = try self.getBuilder();
        try b.write("try hashlib.new(");
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.write(")");
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
    }
}
