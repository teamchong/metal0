/// JSON module - json.loads() and json.dumps() code generation
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const NativeType = @import("../../analysis/native_types.zig").NativeType;

/// Generate code for json.loads(json_string)
/// Parses JSON and returns a PyObject (dict/list/etc)
pub fn genJsonLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // runtime.json.loads expects (*PyObject, allocator) and returns !*PyObject
    // We need to wrap string literal in PyString first
    try self.output.appendSlice(self.allocator, "blk: { const json_str_obj = try runtime.PyString.create(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, "); defer runtime.decref(json_str_obj, allocator); break :blk try runtime.json.loads(json_str_obj, allocator); }");
}

/// Generate code for json.dumps(obj)
/// Maps to: runtime.json.dumps(obj, allocator)
/// Handles conversion from native dict/list to PyObject
pub fn genJsonDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Check if argument is a dict type that needs conversion
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    if (arg_type == .dict) {
        // Native dict (StringHashMap) needs conversion to PyDict
        try genJsonDumpsDict(self, args[0], arg_type.dict.value.*);
    } else if (arg_type == .list) {
        // Native list (ArrayList) needs conversion to PyList
        try genJsonDumpsList(self, args[0], arg_type.list.*);
    } else {
        // Already a PyObject or primitive - use directly
        try self.output.appendSlice(self.allocator, "try runtime.json.dumps(");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ", allocator)");
    }
}

/// Generate code to convert native dict to PyDict and dump as JSON
fn genJsonDumpsDict(self: *NativeCodegen, dict_expr: ast.Node, value_type: NativeType) CodegenError!void {
    try self.output.appendSlice(self.allocator, "json_blk: {\n");
    self.indent();
    try self.emitIndent();

    // Get the dict expression
    try self.output.appendSlice(self.allocator, "const _dict_map = ");
    try self.genExpr(dict_expr);
    try self.output.appendSlice(self.allocator, ";\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _py_dict = try runtime.PyDict.create(allocator);\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "errdefer runtime.decref(_py_dict, allocator);\n");

    // Iterate and convert each entry
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _it = _dict_map.iterator();\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (_it.next()) |_entry| {\n");
    self.indent();
    try self.emitIndent();

    // Convert value to PyObject based on type
    try genValueToPyObject(self, "_entry.value_ptr.*", value_type);

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try runtime.PyDict.set(_py_dict, _entry.key_ptr.*, _py_val);\n");

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _result = try runtime.json.dumps(_py_dict, allocator);\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "runtime.decref(_py_dict, allocator);\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :json_blk _result;\n");

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code to convert native list to PyList and dump as JSON
fn genJsonDumpsList(self: *NativeCodegen, list_expr: ast.Node, elem_type: NativeType) CodegenError!void {
    try self.output.appendSlice(self.allocator, "json_blk: {\n");
    self.indent();
    try self.emitIndent();

    // Get the list expression
    try self.output.appendSlice(self.allocator, "const _list_arr = ");
    try self.genExpr(list_expr);
    try self.output.appendSlice(self.allocator, ";\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _py_list = try runtime.PyList.create(allocator);\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "errdefer runtime.decref(_py_list, allocator);\n");

    // Iterate and convert each element
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "for (_list_arr.items) |_item| {\n");
    self.indent();
    try self.emitIndent();

    // Convert element to PyObject based on type
    try genValueToPyObject(self, "_item", elem_type);

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try runtime.PyList.append(_py_list, _py_val);\n");

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _result = try runtime.json.dumps(_py_list, allocator);\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "runtime.decref(_py_list, allocator);\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :json_blk _result;\n");

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code to convert a native value to PyObject
fn genValueToPyObject(self: *NativeCodegen, value_expr: []const u8, value_type: NativeType) CodegenError!void {
    switch (value_type) {
        .int => {
            try self.output.appendSlice(self.allocator, "const _py_val = try runtime.PyInt.create(allocator, ");
            try self.output.appendSlice(self.allocator, value_expr);
            try self.output.appendSlice(self.allocator, ");\n");
        },
        .float => {
            try self.output.appendSlice(self.allocator, "const _py_val = try runtime.PyFloat.create(allocator, ");
            try self.output.appendSlice(self.allocator, value_expr);
            try self.output.appendSlice(self.allocator, ");\n");
        },
        .bool => {
            try self.output.appendSlice(self.allocator, "const _py_val = try runtime.PyInt.create(allocator, if (");
            try self.output.appendSlice(self.allocator, value_expr);
            try self.output.appendSlice(self.allocator, ") @as(i64, 1) else @as(i64, 0));\n");
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "_py_val.type_id = .bool;\n");
        },
        .string => {
            try self.output.appendSlice(self.allocator, "const _py_val = try runtime.PyString.create(allocator, ");
            try self.output.appendSlice(self.allocator, value_expr);
            try self.output.appendSlice(self.allocator, ");\n");
        },
        else => {
            // Fallback: assume it's already a PyObject or use string conversion
            try self.output.appendSlice(self.allocator, "const _py_val = try runtime.PyString.create(allocator, ");
            try self.output.appendSlice(self.allocator, value_expr);
            try self.output.appendSlice(self.allocator, ");\n");
        },
    }
}
