/// Dynamic attribute and scope access builtins
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const builder_mod = @import("codegen.builder");

// MIGRATED TO ZIGBUILDER

/// Helper: emit runtime.hasattr_builtin(obj, name) with guaranteed bracket matching
fn emitHasattrBuiltin(self: *NativeCodegen, obj: ast.Node, name: ast.Node) CodegenError!void {
    const Ctx = struct { o: ast.Node, n: ast.Node };
    try self.emitCallCtx("runtime.hasattr_builtin", Ctx{ .o = obj, .n = name }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.genExpr(ctx.o);
            try s.emit(", ");
            try s.genExpr(ctx.n);
        }
    }.f);
}

/// Helper: emit runtime.vars_builtin(arg) with guaranteed bracket matching
fn emitVarsBuiltin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emitCallCtx("runtime.vars_builtin", args, struct {
        pub fn f(s: *NativeCodegen, a: []ast.Node) CodegenError!void {
            if (a.len > 0) {
                try s.genExpr(a[0]);
            }
        }
    }.f);
}

/// Helper: emit runtime.dir_builtin(arg_or_null) with guaranteed bracket matching
fn emitDirBuiltin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emitCallCtx("runtime.dir_builtin", args, struct {
        pub fn f(s: *NativeCodegen, a: []ast.Node) CodegenError!void {
            if (a.len > 0) {
                try s.genExpr(a[0]);
            } else {
                try s.emit("null");
            }
        }
    }.f);
}

pub fn genGetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("return error.TypeError");
        return;
    }
    // Use comptime type check to handle both struct types (staticmethod, classmethod)
    // and *PyObject types
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_getattr: {{ const __ga_obj = ", .{id});
    try self.genExpr(args[0]); // object
    try self.emit("; const __ga_name = ");
    try self.genExpr(args[1]); // name
    try self.emit("; const __ga_info = @typeInfo(@TypeOf(__ga_obj)); ");
    try self.emitFmt("break :__m{d}_getattr if (__ga_info == .@\"struct\") ", .{id});
    try self.emit("runtime.structGetattr(__ga_obj, __ga_name) ");
    try self.emit("else if (__ga_info == .pointer and @typeInfo(__ga_info.pointer.child) == .@\"struct\") ");
    try self.emit("runtime.structGetattr(__ga_obj, __ga_name) ");
    try self.emit("else runtime.getattr_builtin(__ga_obj, __ga_name); }");
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
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_setattr: {{ const __sa_obj = ", .{id});
    try self.genExpr(args[0]);
    try self.emit("; const __sa_name = ");
    try self.genExpr(args[1]);
    try self.emit("; const __sa_name_str: []const u8 = if (@hasField(@TypeOf(__sa_name), \"__base_value__\")) __sa_name.__base_value__ else __sa_name; const __sa_val = ");
    try self.genExpr(args[2]);
    // Check if object is a PyType (has setattr method) vs regular struct (has __dict__ field)
    try self.emit("; const __sa_obj_type = @TypeOf(__sa_obj); ");
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
    try self.emitFmt("}} break :__m{d}_setattr; }}", .{id});
}

pub fn genHasattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("return error.TypeError");
        return;
    }
    try emitHasattrBuiltin(self, args[0], args[1]);
}

pub fn genVars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitVarsBuiltin(self, args);
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
    try emitDirBuiltin(self, args);
}
