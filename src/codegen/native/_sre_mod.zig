/// Python _sre module - Internal SRE support (C accelerator for regex)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compile", genCompile },
    .{ "c_o_d_e_s_i_z_e", genCodesize },
    .{ "m_a_g_i_c", genMagic },
    .{ "getlower", genGetlower },
    .{ "getcodesize", genGetcodesizeFunc },
    .{ "match", genMatch },
    .{ "fullmatch", genFullmatch },
    .{ "search", genSearch },
    .{ "findall", genFindall },
    .{ "finditer", genFinditer },
    .{ "sub", genSub },
    .{ "subn", genSubn },
    .{ "split", genSplit },
    .{ "group", genGroup },
    .{ "groups", genGroups },
    .{ "groupdict", genGroupdict },
    .{ "start", genStart },
    .{ "end", genEnd },
    .{ "span", genSpan },
    .{ "expand", genExpand },
});

fn genCompile(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("sre", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                const b = try c.getBuilder();
                try b.write("const __v = ");
                const output1 = try b.getBodyDupe();
                try c.output.appendSlice(c.allocator, output1);
                try c.genExpr(a[0]);
                {
                    const b2 = try c.getBuilder();
                    try b2.writeFmt("; break :{s} .{{ .pattern = __v, .flags = 0, .groups = 0 }}", .{label});
                    const output2 = try b2.getBodyDupe();
                    try c.output.appendSlice(c.allocator, output2);
                }
            }
        }.emit);
    } else {
        try self.emit(".{ .pattern = \"\", .flags = 0, .groups = 0 }");
    }
}

fn genCodesize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 4)");
}

fn genMagic(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 20171005)");
}

fn genGetlower(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(i32, 0)");
    }
}

fn genGetcodesizeFunc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 4)");
}

fn genMatch(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("null");
}

fn genFullmatch(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("null");
}

fn genSearch(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("null");
}

fn genFindall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("&[_][]const u8{}");
}

fn genFinditer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("&[_]@TypeOf(null){}");
}

fn genSub(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("\"\"");
    }
}

fn genSubn(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 1) {
        {
            const b = try self.getBuilder();
            try b.write(".{ ");
            const output = try b.getBodyDupe();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write(", @as(i64, 0) }");
            const output = try b.getBodyDupe();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        try self.emit(".{ \"\", @as(i64, 0) }");
    }
}

fn genSplit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("&[_][]const u8{}");
}

fn genGroup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("\"\"");
}

fn genGroups(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{}");
}

fn genGroupdict(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{}");
}

fn genStart(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i64, 0)");
}

fn genEnd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i64, 0)");
}

fn genSpan(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{ @as(i64, 0), @as(i64, 0) }");
}

fn genExpand(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("\"\"");
}
