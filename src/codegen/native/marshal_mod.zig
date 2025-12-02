/// Python marshal module - Internal Python object serialization
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dump", h.c("{}") }, .{ "dumps", genDumps }, .{ "load", genLoad }, .{ "loads", genLoads }, .{ "version", h.I32(4) },
});

fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        if (args[0] == .constant and args[0].constant.value == .bool) {
            try self.emit(if (args[0].constant.value.bool) "\"T\"" else "\"F\"");
            return;
        }
        const uid = self.output.items.len;
        try self.emitFmt("marshal_dumps_{d}: {{ const val = ", .{uid});
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = val; break :marshal_dumps_{d} \"\"; }}", .{uid});
    } else try self.emit("\"\"");
}

fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const uid = self.output.items.len;
        try self.emitFmt("marshal_load_{d}: {{ const file = ", .{uid});
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = file; break :marshal_load_{d} null; }}", .{uid});
    } else try self.emit("null");
}

fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("runtime.marshalLoads("); try self.genExpr(args[0]); try self.emit(")"); }
    else try self.emit("null");
}
