/// Python hmac module - HMAC (Hash-based Message Authentication Code)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "new", genNew },
    .{ "digest", genDigest },
    .{ "compare_digest", h.compareDigest() },
});

/// Generate code for hmac.new(key, msg) - returns hexadecimal HMAC digest
fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("\"\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    try self.withInlineBlock("hmac_new", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _key = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _msg = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; var _hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(_key); _hmac.update(_msg); var _out: [32]u8 = undefined; _hmac.final(&_out); const _hex = __global_allocator.alloc(u8, 64) catch break :{s} \"\"; const _hex_chars = \"0123456789abcdef\"; for (_out, 0..) |byte, i| {{ _hex[i * 2] = _hex_chars[byte >> 4]; _hex[i * 2 + 1] = _hex_chars[byte & 0x0f]; }} break :{s} _hex", .{ label, label });
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

/// Generate code for hmac.digest(key, msg) - returns binary HMAC digest
fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("\"\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    try self.withInlineBlock("hmac_digest", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _key = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _msg = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; var _hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(_key); _hmac.update(_msg); const _result = __global_allocator.alloc(u8, 32) catch break :{s} \"\"; _hmac.final(_result[0..32]); break :{s} _result", .{ label, label });
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}
