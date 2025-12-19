/// Python marshal module - Internal Python object serialization
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dump", h.c("{}") }, .{ "dumps", genDumps }, .{ "load", genLoad },
    .{ "loads", h.wrap("runtime.marshalLoads(", ")", "null") }, .{ "version", h.I32(4) },
});

fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        if (args[0] == .constant and args[0].constant.value == .bool) {
            try b.write(if (args[0].constant.value.bool) "\"T\"" else "\"F\"");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
            return;
        }
        const uid = self.output.items.len;
        try b.writeFmt("marshal_dumps_{d}: {{ const val = ", .{uid});
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.writeFmt("; _ = val; break :marshal_dumps_{d} \"\"; }}", .{uid});
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
    } else {
        try b.write("\"\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const uid = self.output.items.len;
        try b.writeFmt("marshal_load_{d}: {{ const file = ", .{uid});
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.writeFmt("; _ = file; break :marshal_load_{d} null; }}", .{uid});
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
    } else {
        try b.write("null");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}
