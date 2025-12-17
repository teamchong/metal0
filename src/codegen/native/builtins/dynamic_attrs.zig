/// Dynamic attribute and scope access builtins
const std = @import("std");
const ast = @import("analysis.ast");
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
    // Handle setattr for both:
    // 1. PyType objects (metaclass instances) - use .setattr() method
    // 2. Regular objects with __dict__ - use __dict__.put()
    // Use comptime type introspection to select the correct approach
    try self.emit("blk: { const __sa_obj = ");
    try self.genExpr(args[0]);
    try self.emit("; const __sa_name = ");
    try self.genExpr(args[1]);
    try self.emit("; const __sa_name_str: []const u8 = if (@hasField(@TypeOf(__sa_name), \"__base_value__\")) __sa_name.__base_value__ else __sa_name;");
    try self.emit(" const __sa_val = ");
    try self.genExpr(args[2]);
    try self.emit("; ");
    // Check if object is a PyType (has setattr method) vs regular struct (has __dict__ field)
    try self.emit("const __sa_obj_type = @TypeOf(__sa_obj); ");
    try self.emit("const __is_pytype = @typeInfo(__sa_obj_type) == .pointer and @hasDecl(@typeInfo(__sa_obj_type).pointer.child, \"setattr\"); ");
    if (self.inside_defer) {
        try self.emit("if (__is_pytype) { @constCast(__sa_obj).setattr(__sa_name_str, runtime.PyValue.from(__sa_val)) catch unreachable; ");
        try self.emit("} else if (@hasField(@typeInfo(__sa_obj_type).pointer.child, \"__dict__\")) { ");
        try self.emit("@constCast(&__sa_obj.__dict__).put(__sa_name_str, runtime.PyValue.from(__sa_val)) catch unreachable; ");
    } else {
        try self.emit("if (__is_pytype) { try @constCast(__sa_obj).setattr(__sa_name_str, runtime.PyValue.from(__sa_val)); ");
        try self.emit("} else if (@hasField(@typeInfo(__sa_obj_type).pointer.child, \"__dict__\")) { ");
        try self.emit("try @constCast(&__sa_obj.__dict__).put(__sa_name_str, runtime.PyValue.from(__sa_val)); ");
    }
    try self.emit("} break :blk {}; }");
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

pub fn genDir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("runtime.dir_builtin(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("null");
    }
    try self.emit(")");
}
