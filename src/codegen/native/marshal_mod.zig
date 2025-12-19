/// Python marshal module - Internal Python object serialization
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dump", h.c("{}") }, .{ "dumps", genDumps }, .{ "load", genLoad },
    .{ "loads", h.wrap("runtime.marshalLoads(", ")", "null") }, .{ "version", h.I32(4) },
});

fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        if (args[0] == .constant and args[0].constant.value == .bool) {
            try emitConst(self, if (args[0].constant.value.bool) "\"T\"" else "\"F\"");
            return;
        }
        const uid = self.output.items.len;
        try emitFmtConst(self, "marshal_dumps_{d}: {{ const val = ", .{uid});
        try self.genExpr(args[0]);
        try emitFmtConst(self, "; _ = val; break :marshal_dumps_{d} \"\"; }}", .{uid});
    } else {
        try emitConst(self, "\"\"");
    }
}

fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const uid = self.output.items.len;
        try emitFmtConst(self, "marshal_load_{d}: {{ const file = ", .{uid});
        try self.genExpr(args[0]);
        try emitFmtConst(self, "; _ = file; break :marshal_load_{d} null; }}", .{uid});
    } else {
        try emitConst(self, "null");
    }
}
