/// Python pickle module - Object serialization
/// Note: This uses JSON as backing format for simplicity.
/// Full pickle protocol compatibility would require significant work.
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const json = @import("json.zig");

/// Generate pickle.dumps(obj) -> bytes
/// Serializes object to bytes using JSON format
/// Returns []const u8 directly (not wrapped in PyObject)
pub fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Check if argument is a dict type that needs conversion
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    if (arg_type == .dict) {
        // Native dict (StringHashMap) needs conversion to PyDict then dumpsDirect
        try self.emit("pickle_blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("const _dict_map = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emitIndent();
        try self.emit("const _py_dict = try runtime.PyDict.create(__global_allocator);\n");
        try self.emitIndent();
        try self.emit("defer runtime.decref(_py_dict, __global_allocator);\n");
        try self.emitIndent();
        try self.emit("var _it = _dict_map.iterator();\n");
        try self.emitIndent();
        try self.emit("while (_it.next()) |_entry| {\n");
        self.indent();
        try self.emitIndent();
        // Convert value based on inferred value type
        const value_type = arg_type.dict.value.*;
        if (value_type == .int) {
            try self.emit("const _py_val = try runtime.PyInt.create(__global_allocator, _entry.value_ptr.*);\n");
        } else if (value_type == .float) {
            try self.emit("const _py_val = try runtime.PyFloat.create(__global_allocator, _entry.value_ptr.*);\n");
        } else {
            try self.emit("const _py_val = try runtime.PyString.create(__global_allocator, _entry.value_ptr.*);\n");
        }
        try self.emitIndent();
        try self.emit("try runtime.PyDict.set(_py_dict, _entry.key_ptr.*, _py_val);\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        try self.emitIndent();
        try self.emit("break :pickle_blk try runtime.json.dumpsDirect(_py_dict, __global_allocator);\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}");
    } else if (arg_type == .list) {
        // List needs conversion then dumpsDirect
        try self.emit("try runtime.json.dumpsDirect(try runtime.PyList.fromArrayList(");
        try self.genExpr(args[0]);
        try self.emit(", __global_allocator), __global_allocator)");
    } else {
        // Already a PyObject - use dumpsDirect
        try self.emit("try runtime.json.dumpsDirect(");
        try self.genExpr(args[0]);
        try self.emit(", __global_allocator)");
    }
}

/// Generate pickle.loads(data) -> object
/// Deserializes bytes to object using JSON parser (reuses json.loads)
pub fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Pickle loads is just JSON loads in our implementation
    return json.genJsonLoads(self, args);
}

/// Generate pickle.dump(obj, file) -> None
/// Writes serialized object to file
pub fn genDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    // Serialize using json.dumps then write to file
    try self.emit("pickle_dump_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _json_str = ");
    // Generate json.dumps for first arg
    try json.genJsonDumps(self, args[0..1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _file = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _file.write(_json_str) catch 0;\n");
    try self.emitIndent();
    try self.emit("break :pickle_dump_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate pickle.load(file) -> object
/// Reads and deserializes object from file
pub fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Read file content and parse as JSON
    try self.emit("pickle_load_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _file = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _content = _file.reader().readAllAlloc(__global_allocator, 10 * 1024 * 1024) catch break :pickle_load_blk @as(*runtime.PyObject, undefined);\n");
    try self.emitIndent();
    try self.emit("const _json_str_obj = try runtime.PyString.create(__global_allocator, _content);\n");
    try self.emitIndent();
    try self.emit("defer runtime.decref(_json_str_obj, __global_allocator);\n");
    try self.emitIndent();
    try self.emit("break :pickle_load_blk try runtime.json.loads(_json_str_obj, __global_allocator);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate pickle.HIGHEST_PROTOCOL constant (value 5 in Python 3.8+)
pub fn genHIGHEST_PROTOCOL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 5)");
}

/// Generate pickle.DEFAULT_PROTOCOL constant (value 4 in Python 3.8+)
pub fn genDEFAULT_PROTOCOL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 4)");
}

/// Generate pickle.PicklingError exception
pub fn genPicklingError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.PicklingError");
}

/// Generate pickle.UnpicklingError exception
pub fn genUnpicklingError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UnpicklingError");
}

/// Generate pickle.Pickler(file, protocol) class
pub fn genPickler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("undefined");
        return;
    }
    // For now, just store the file reference
    try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
}

/// Generate pickle.Unpickler(file) class
pub fn genUnpickler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("undefined");
        return;
    }
    try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
}
