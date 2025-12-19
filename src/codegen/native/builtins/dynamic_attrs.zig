/// Dynamic attribute and scope access builtins
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const builder_mod = @import("codegen.builder");

// MIGRATED TO ZIGBUILDER

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

pub fn genGetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try emitConst(self, "return error.TypeError");
        return;
    }
    try emitConst(self, "runtime.getattr_builtin(");
    try self.genExpr(args[0]); // object
    try emitConst(self, ", ");
    try self.genExpr(args[1]); // name
    try emitConst(self, ")");
}

pub fn genSetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) {
        try emitConst(self, "return error.TypeError");
        return;
    }
    // Handle setattr for both:
    // 1. PyType objects (metaclass instances) - use .setattr() method
    // 2. Regular objects with __dict__ - use __dict__.put()
    // Use comptime type introspection to select the correct approach
    const id = self.nextNameId();
    try emitFmtConst(self, "__m{d}_setattr: {{ const __sa_obj = ", .{id});
    try self.genExpr(args[0]);
    try emitConst(self, "; const __sa_name = ");
    try self.genExpr(args[1]);
    try emitConst(self, "; const __sa_name_str: []const u8 = if (@hasField(@TypeOf(__sa_name), \"__base_value__\")) __sa_name.__base_value__ else __sa_name; const __sa_val = ");
    try self.genExpr(args[2]);
    // Check if object is a PyType (has setattr method) vs regular struct (has __dict__ field)
    try emitConst(self, "; const __sa_obj_type = @TypeOf(__sa_obj); ");
    try emitConst(self, "const __is_pytype = @typeInfo(__sa_obj_type) == .pointer and @hasDecl(@typeInfo(__sa_obj_type).pointer.child, \"setattr\"); ");
    if (self.inside_defer) {
        try emitConst(self, "if (__is_pytype) { @constCast(__sa_obj).setattr(__sa_name_str, runtime.PyValue.from(__sa_val)) catch unreachable; ");
        try emitConst(self, "} else if (@hasField(@typeInfo(__sa_obj_type).pointer.child, \"__dict__\")) { ");
        try emitConst(self, "@constCast(&__sa_obj.__dict__).put(__sa_name_str, runtime.PyValue.from(__sa_val)) catch unreachable; ");
    } else {
        try emitConst(self, "if (__is_pytype) { try @constCast(__sa_obj).setattr(__sa_name_str, runtime.PyValue.from(__sa_val)); ");
        try emitConst(self, "} else if (@hasField(@typeInfo(__sa_obj_type).pointer.child, \"__dict__\")) { ");
        try emitConst(self, "try @constCast(&__sa_obj.__dict__).put(__sa_name_str, runtime.PyValue.from(__sa_val)); ");
    }
    try emitFmtConst(self, "}} break :__m{d}_setattr {{}}; }}", .{id});
}

pub fn genHasattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try emitConst(self, "return error.TypeError");
        return;
    }
    try emitConst(self, "runtime.hasattr_builtin(");
    try self.genExpr(args[0]);
    try emitConst(self, ", ");
    try self.genExpr(args[1]);
    try emitConst(self, ")");
}

pub fn genVars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitConst(self, "runtime.vars_builtin(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try emitConst(self, ")");
}

pub fn genGlobals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try emitConst(self, "runtime.globals_builtin()");
}

pub fn genLocals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try emitConst(self, "runtime.locals_builtin()");
}

pub fn genDir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitConst(self, "runtime.dir_builtin(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try emitConst(self, "null");
    }
    try emitConst(self, ")");
}
