/// Dynamic attribute and scope access builtins
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const builder_mod = @import("codegen.builder");

pub fn genGetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("return error.TypeError");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    {
        const b = try self.getBuilder();
        try b.write("runtime.getattr_builtin(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]); // object
    {
        const b = try self.getBuilder();
        try b.write(", ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[1]); // name
    {
        const b = try self.getBuilder();
        try b.write(")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

pub fn genSetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) {
        const b = try self.getBuilder();
        try b.write("return error.TypeError");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    // Handle setattr for both:
    // 1. PyType objects (metaclass instances) - use .setattr() method
    // 2. Regular objects with __dict__ - use __dict__.put()
    // Use comptime type introspection to select the correct approach
    const id = self.nextNameId();
    {
        const b = try self.getBuilder();
        try b.writeFmt("__m{d}_setattr: {{ const __sa_obj = ", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.write("; const __sa_name = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[1]);
    {
        const b = try self.getBuilder();
        try b.write("; const __sa_name_str: []const u8 = if (@hasField(@TypeOf(__sa_name), \"__base_value__\")) __sa_name.__base_value__ else __sa_name;");
        try b.write(" const __sa_val = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[2]);
    {
        const b = try self.getBuilder();
        try b.write("; ");
        // Check if object is a PyType (has setattr method) vs regular struct (has __dict__ field)
        try b.write("const __sa_obj_type = @TypeOf(__sa_obj); ");
        try b.write("const __is_pytype = @typeInfo(__sa_obj_type) == .pointer and @hasDecl(@typeInfo(__sa_obj_type).pointer.child, \"setattr\"); ");
        if (self.inside_defer) {
            try b.write("if (__is_pytype) { @constCast(__sa_obj).setattr(__sa_name_str, runtime.PyValue.from(__sa_val)) catch unreachable; ");
            try b.write("} else if (@hasField(@typeInfo(__sa_obj_type).pointer.child, \"__dict__\")) { ");
            try b.write("@constCast(&__sa_obj.__dict__).put(__sa_name_str, runtime.PyValue.from(__sa_val)) catch unreachable; ");
        } else {
            try b.write("if (__is_pytype) { try @constCast(__sa_obj).setattr(__sa_name_str, runtime.PyValue.from(__sa_val)); ");
            try b.write("} else if (@hasField(@typeInfo(__sa_obj_type).pointer.child, \"__dict__\")) { ");
            try b.write("try @constCast(&__sa_obj.__dict__).put(__sa_name_str, runtime.PyValue.from(__sa_val)); ");
        }
        try b.writeFmt("}} break :__m{d}_setattr {{}}; }}", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

pub fn genHasattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("return error.TypeError");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    {
        const b = try self.getBuilder();
        try b.write("runtime.hasattr_builtin(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.write(", ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[1]);
    {
        const b = try self.getBuilder();
        try b.write(")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

pub fn genVars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    {
        const b = try self.getBuilder();
        try b.write("runtime.vars_builtin(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    {
        const b = try self.getBuilder();
        try b.write(")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

pub fn genGlobals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.write("runtime.globals_builtin()");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

pub fn genLocals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.write("runtime.locals_builtin()");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

pub fn genDir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    {
        const b = try self.getBuilder();
        try b.write("runtime.dir_builtin(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        const b = try self.getBuilder();
        try b.write("null");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.write(")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}
