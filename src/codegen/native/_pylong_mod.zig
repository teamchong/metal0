/// Python _pylong module - Pure Python long integer implementation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "log10_base256", genLog10Base256 },
    .{ "spread", genSpread },
    .{ "int_to_decimal_string", genIntToDecimalString },
    .{ "int_from_string", genIntFromString },
    .{ "dec_str_to_int_inner", genDecStrToIntInner },
    .{ "compute_powers", genComputePowers },
});

fn genLog10Base256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(f64, 0.4150374992788438)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genSpread(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("(struct { data: std.AutoHashMap(i64, i64) = .{}, pub fn copy(self: @This()) @This() { return self; } pub fn clear(self: *@This()) void { self.data.clearRetainingCapacity(); } pub fn clearRetainingCapacity(self: *@This()) void { self.data.clearRetainingCapacity(); } pub fn update(self: *@This(), other: @This()) void { _ = other; } pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() { _ = allocator; return self; } pub fn contains(self: @This(), key: i64) bool { return self.data.contains(key); } }{})");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genIntToDecimalString(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("\"0\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    const id = self.nextNameId();
    {
        const b = try self.getBuilder();
        try b.writeFmt("(__pylong_itds_{d}: {{ const __n_{d} = ", .{ id, id });
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.writeFmt("; if (@TypeOf(__n_{d}) == runtime.BigInt) {{ break :__pylong_itds_{d} __n_{d}.toString(__global_allocator); }} else {{ break :__pylong_itds_{d} try std.fmt.allocPrint(__global_allocator, \"{{d}}\", .{{__n_{d}}}); }} }})", .{ id, id, id, id, id });
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genIntFromString(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("@as(i64, 0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    const id = self.nextNameId();
    {
        const b = try self.getBuilder();
        try b.writeFmt("(__pylong_ifs_{d}: {{ const __s_{d} = ", .{ id, id });
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.writeFmt("; const __base_{d}: u8 = ", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (args.len > 1) {
        {
            const b = try self.getBuilder();
            try b.write("@intCast(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write(")");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        const b = try self.getBuilder();
        try b.write("10");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.writeFmt("; break :__pylong_ifs_{d} runtime.builtins.parseInt(__s_{d}, __base_{d}) catch 0; }})", .{ id, id, id });
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genDecStrToIntInner(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("@as(i64, 0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    const id = self.nextNameId();
    {
        const b = try self.getBuilder();
        try b.writeFmt("(__pylong_dsi_{d}: {{ const __s_{d} = ", .{ id, id });
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.writeFmt("; const __guard_{d}: u8 = ", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (args.len > 1) {
        {
            const b = try self.getBuilder();
            try b.write("@intCast(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write(")");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        const b = try self.getBuilder();
        try b.write("8");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.writeFmt("; _ = __guard_{d}; const __max_len_{d}: usize = @intFromFloat(@as(f64, @floatFromInt(@as(u64, 1) << 47)) / 0.4150374992788438); if (__s_{d}.len > __max_len_{d}) {{ return error.ValueError; }} break :__pylong_dsi_{d} runtime.builtins.parseInt(__s_{d}, 10) catch 0; }})", .{ id, id, id, id, id, id });
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genComputePowers(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len < 3) {
        const b = try self.getBuilder();
        try b.write("(runtime.pylong.computePowers(__global_allocator, 0, 2, 0, false))");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    {
        const b = try self.getBuilder();
        try b.write("(runtime.pylong.computePowers(__global_allocator, @intCast(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.write("), @intCast(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[1]);
    {
        const b = try self.getBuilder();
        try b.write("), @intCast(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[2]);
    {
        const b = try self.getBuilder();
        try b.write("), ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (args.len > 3) {
        try self.genExpr(args[3]);
    } else {
        const b = try self.getBuilder();
        try b.write("false");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.write("))");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}
