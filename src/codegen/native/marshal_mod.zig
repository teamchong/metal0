/// Python marshal module - Internal Python object serialization
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "dump", genConst("{}") }, .{ "dumps", genDumps }, .{ "load", genLoad }, .{ "loads", genLoads }, .{ "version", genConst("@as(i32, 4)") },
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
