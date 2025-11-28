/// Python marshal module - Internal Python object serialization
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate marshal.dump(value, file, version=4)
pub fn genDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate marshal.dumps(value, version=4)
pub fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const uid = self.output.items.len;
        try self.emitFmt("marshal_dumps_{d}: {{ const val = ", .{uid});
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = val; break :marshal_dumps_{d} \"\"; }}", .{uid});
    } else {
        try self.emit("\"\"");
    }
}

/// Generate marshal.load(file)
pub fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const uid = self.output.items.len;
        try self.emitFmt("marshal_load_{d}: {{ const file = ", .{uid});
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = file; break :marshal_load_{d} null; }}", .{uid});
    } else {
        try self.emit("null");
    }
}

/// Generate marshal.loads(bytes)
pub fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const uid = self.output.items.len;
        try self.emitFmt("marshal_loads_{d}: {{ const data = ", .{uid});
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = data; break :marshal_loads_{d} null; }}", .{uid});
    } else {
        try self.emit("null");
    }
}

/// Generate marshal.version constant
pub fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}
