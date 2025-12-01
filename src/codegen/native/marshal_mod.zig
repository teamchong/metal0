/// Python marshal module - Internal Python object serialization
const std = @import("std");
const ast = @import("ast");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "dump", genDump },
    .{ "dumps", genDumps },
    .{ "load", genLoad },
    .{ "loads", genLoads },
    .{ "version", genVersion },
});
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate marshal.dump(value, file, version=4)
pub fn genDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate marshal.dumps(value, version=4)
/// For AOT compilation, we serialize at compile time by encoding the type+value
pub fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // For bool constants, we encode as 'T' for True, 'F' for False
        // This is a simplified marshal format for AOT use
        if (args[0] == .constant) {
            if (args[0].constant.value == .bool) {
                if (args[0].constant.value.bool) {
                    try self.emit("\"T\""); // Marshal format for True
                } else {
                    try self.emit("\"F\""); // Marshal format for False
                }
                return;
            }
        }
        // Fallback: stub for unsupported types
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
/// Decodes the simplified marshal format used by genDumps
pub fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // Use runtime function to decode the marshal data
        try self.emit("runtime.marshalLoads(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("null");
    }
}

/// Generate marshal.version constant
pub fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}
