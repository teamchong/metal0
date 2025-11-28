/// Python copyreg module - Register pickle support functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate copyreg.pickle(ob_type, pickle_function, constructor_ob=None)
pub fn genPickle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate copyreg.constructor(object)
pub fn genConstructor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*const fn() anytype, null)");
    }
}

/// Generate copyreg.dispatch_table
pub fn genDispatch_table(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyDict(usize, @TypeOf(.{ null, null })).init()");
}

/// Generate copyreg._extension_registry
pub fn gen_extension_registry(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyDict(@TypeOf(.{ \"\", \"\" }), i32).init()");
}

/// Generate copyreg._inverted_registry
pub fn gen_inverted_registry(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyDict(i32, @TypeOf(.{ \"\", \"\" })).init()");
}

/// Generate copyreg._extension_cache
pub fn gen_extension_cache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyDict(i32, ?anyopaque).init()");
}

/// Generate copyreg.add_extension(module, name, code)
pub fn genAdd_extension(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate copyreg.remove_extension(module, name, code)
pub fn genRemove_extension(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate copyreg.clear_extension_cache()
pub fn genClear_extension_cache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate copyreg.__newobj__(cls, *args)
pub fn gen__newobj__(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const cls = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk cls{}; }");
    } else {
        try self.emit(".{}");
    }
}

/// Generate copyreg.__newobj_ex__(cls, args, kwargs)
pub fn gen__newobj_ex__(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const cls = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk cls{}; }");
    } else {
        try self.emit(".{}");
    }
}
