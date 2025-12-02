/// Dynamic attribute and scope access builtins
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

pub fn genGetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("return error.TypeError");
        return;
    }
    try self.emit("runtime.getattr_builtin(");
    try self.genExpr(args[0]); // object
    try self.emit(", ");
    try self.genExpr(args[1]); // name
    try self.emit(")");
}

pub fn genSetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) {
        try self.emit("return error.TypeError");
        return;
    }
    // For objects with __dict__, directly set the attribute
    // Need to handle str subclasses - extract __base_value__ if present for key
    // Zig 0.15: managed containers use put(key, value) not put(allocator, key, value)
    // Use @constCast since the object may be declared as const (HashMap stores data via pointers,
    // so @constCast works correctly - the internal data is heap-allocated)
    try self.emit("blk: { const __sa_name = ");
    try self.genExpr(args[1]);
    try self.emit("; const __sa_name_str: []const u8 = if (@hasField(@TypeOf(__sa_name), \"__base_value__\")) __sa_name.__base_value__ else __sa_name;");
    try self.emit(" const __sa_val = ");
    try self.genExpr(args[2]);
    try self.emit("; try @constCast(&");
    try self.genExpr(args[0]);
    try self.emit(".__dict__).put(__sa_name_str, runtime.PyValue.from(__sa_val)); break :blk {}; }");
}

pub fn genHasattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("return error.TypeError");
        return;
    }
    try self.emit("runtime.hasattr_builtin(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

pub fn genVars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("runtime.vars_builtin(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try self.emit(")");
}

pub fn genGlobals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.globals_builtin()");
}

pub fn genLocals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.locals_builtin()");
}
