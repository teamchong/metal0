/// JSON module - json.loads() and json.dumps() code generation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const NativeType = @import("../../analysis/native_types.zig").NativeType;
const type_traits = @import("../../analysis/traits/type_traits.zig");
const container_traits = @import("../../analysis/traits/container_traits.zig");

/// Handler function type
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// JSON module function map - exported for dispatch
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "loads", genJsonLoads },
    .{ "dumps", genJsonDumps },
    .{ "load", genJsonLoad },
    .{ "dump", genJsonDump },
    .{ "JSONEncoder", genJSONEncoder },
    .{ "JSONDecoder", genJSONDecoder },
});

/// Generate code for json.loads(json_string)
/// Parses JSON and returns a PyObject (dict/list/etc)
pub fn genJsonLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"json.loads() requires exactly 1 argument\")");
        return;
    }

    // Always use __global_allocator since it's always available
    // (method allocator param may be discarded as "_" if not used elsewhere)
    const alloc_name = "__global_allocator";

    // Check if argument is already a PyObject (e.g., from file.read())
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    if (type_traits.isUnknown(arg_type)) {
        // Already a PyObject - pass directly to json.loads
        try self.emit("try runtime.json.loads(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.emit(alloc_name);
        try self.emit(")");
    } else {
        // String literal or native string - wrap in PyString first
        const id = self.nextNameId();
        const b = try self.getBuilder();
        try b.writeFmt("(__json_loads_{d}: {{ const json_str_obj = try runtime.PyString.create({s}, ", .{ id, alloc_name });
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);

        try self.genExpr(args[0]);

        const b2 = try self.getBuilder();
        try b2.writeFmt("); defer runtime.decref(json_str_obj, {s}); break :__json_loads_{d} try runtime.json.loads(json_str_obj, {s}); }})", .{ alloc_name, id, alloc_name });
        const output2 = b2.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output2);
    }
}

/// Generate code for json.dumps(obj)
/// Maps to: runtime.json.dumps(obj, allocator)
/// Handles conversion from native dict/list to PyObject
pub fn genJsonDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"json.dumps() requires exactly 1 argument\")");
        return;
    }

    // Always use __global_allocator since it's always available
    // (method allocator param may be discarded as "_" if not used elsewhere)
    const alloc_name = "__global_allocator";

    // Check if argument is a dict type that needs conversion
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    if (container_traits.isDict(arg_type)) {
        // Native dict (StringHashMap) needs conversion to PyDict
        try genJsonDumpsDict(self, args[0], arg_type.dict.value.*);
    } else if (container_traits.isList(arg_type)) {
        // Native list (ArrayList) needs conversion to PyList
        try genJsonDumpsList(self, args[0], arg_type.list.*);
    } else {
        // Native Zig value (string, int, bool, null) - use dumpsValue
        try self.emit("try runtime.json.dumpsValue(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.emit(alloc_name);
        try self.emit(")");
    }
}

/// Generate code to convert native dict to PyDict and dump as JSON
fn genJsonDumpsDict(self: *NativeCodegen, dict_expr: ast.Node, value_type: NativeType) CodegenError!void {
    const id = self.nextNameId();
    const b = try self.getBuilder();
    try b.writeFmt("(__json_{d}: {{\n", .{id});
    self.indent();
    try b.writeIndent();
    try b.write("const _dict_map = ");
    const output1 = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output1);

    // Get the dict expression
    try self.genExpr(dict_expr);

    const b2 = try self.getBuilder();
    try b2.write(";\n");
    try b2.writeIndent();
    try b2.write("const _py_dict = try runtime.PyDict.create(__global_allocator);\n");
    try b2.writeIndent();
    try b2.write("errdefer runtime.decref(_py_dict, __global_allocator);\n");
    try b2.writeIndent();
    try b2.write("var _it = _dict_map.iterator();\n");
    try b2.writeIndent();
    try b2.write("while (_it.next()) |_entry| {\n");
    self.indent();
    try b2.writeIndent();
    const output2 = b2.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output2);

    // Convert value to PyObject based on type
    try genValueToPyObject(self, "_entry.value_ptr.*", value_type);

    const b3 = try self.getBuilder();
    try b3.writeIndent();
    try b3.write("try runtime.PyDict.set(_py_dict, _entry.key_ptr.*, _py_val);\n");
    self.dedent();
    try b3.writeIndent();
    try b3.write("}\n");
    try b3.writeIndent();
    try b3.write("const _result = try runtime.json.dumpsDirect(_py_dict, __global_allocator);\n");
    try b3.writeIndent();
    try b3.write("runtime.decref(_py_dict, __global_allocator);\n");
    try b3.writeIndent();
    try b3.writeFmt("break :__json_{d} _result;\n", .{id});
    self.dedent();
    try b3.writeIndent();
    try b3.write("})");
    const output3 = b3.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output3);
}

/// Generate code to convert native list to PyList and dump as JSON
fn genJsonDumpsList(self: *NativeCodegen, list_expr: ast.Node, elem_type: NativeType) CodegenError!void {
    const id = self.nextNameId();
    const b = try self.getBuilder();
    try b.writeFmt("(__json_{d}: {{\n", .{id});
    self.indent();
    try b.writeIndent();
    try b.write("const _list_arr = ");
    const output1 = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output1);

    // Get the list expression
    try self.genExpr(list_expr);

    const b2 = try self.getBuilder();
    try b2.write(";\n");
    try b2.writeIndent();
    try b2.write("const _py_list = try runtime.PyList.create(__global_allocator);\n");
    try b2.writeIndent();
    try b2.write("errdefer runtime.decref(_py_list, __global_allocator);\n");
    try b2.writeIndent();
    try b2.write("for (_list_arr.items) |_item| {\n");
    self.indent();
    try b2.writeIndent();
    const output2 = b2.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output2);

    // Convert element to PyObject based on type
    try genValueToPyObject(self, "_item", elem_type);

    const b3 = try self.getBuilder();
    try b3.writeIndent();
    try b3.write("try runtime.PyList.append(_py_list, _py_val);\n");
    self.dedent();
    try b3.writeIndent();
    try b3.write("}\n");
    try b3.writeIndent();
    try b3.write("const _result = try runtime.json.dumpsDirect(_py_list, __global_allocator);\n");
    try b3.writeIndent();
    try b3.write("runtime.decref(_py_list, __global_allocator);\n");
    try b3.writeIndent();
    try b3.writeFmt("break :__json_{d} _result;\n", .{id});
    self.dedent();
    try b3.writeIndent();
    try b3.write("})");
    const output3 = b3.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output3);
}

/// Generate code to convert a native value to PyObject
fn genValueToPyObject(self: *NativeCodegen, value_expr: []const u8, value_type: NativeType) CodegenError!void {
    const b = try self.getBuilder();
    switch (value_type) {
        .int => {
            try b.write("const _py_val = try runtime.PyInt.create(__global_allocator, ");
            try b.write(value_expr);
            try b.write(");\n");
        },
        .float => {
            try b.write("const _py_val = try runtime.PyFloat.create(__global_allocator, ");
            try b.write(value_expr);
            try b.write(");\n");
        },
        .bool => {
            try b.write("const _py_val = try runtime.PyInt.create(__global_allocator, if (");
            try b.write(value_expr);
            try b.write(") @as(i64, 1) else @as(i64, 0));\n");
            try b.writeIndent();
            try b.write("_py_val.type_id = .bool;\n");
        },
        .string => {
            try b.write("const _py_val = try runtime.PyString.create(__global_allocator, ");
            try b.write(value_expr);
            try b.write(");\n");
        },
        else => {
            // Fallback: assume it's already a PyObject or use string conversion
            try b.write("const _py_val = try runtime.PyString.create(__global_allocator, ");
            try b.write(value_expr);
            try b.write(");\n");
        },
    }
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

/// Generate code for json.load(file)
/// Reads from file object and parses JSON
pub fn genJsonLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // json.load() requires at least 1 argument
    if (args.len < 1) return error.UnsupportedSyntax;

    const id = self.nextNameId();
    const b = try self.getBuilder();
    try b.writeFmt("(__json_load_{d}: {{\n", .{id});
    self.indent();
    try b.writeIndent();
    try b.write("const _file = ");
    const output1 = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output1);

    try self.genExpr(args[0]);

    const b2 = try self.getBuilder();
    try b2.write(";\n");
    try b2.writeIndent();
    try b2.write("const _content = try runtime.PyFile.read(_file, __global_allocator);\n");
    try b2.writeIndent();
    try b2.writeFmt("break :__json_load_{d} try runtime.json.loads(_content, __global_allocator);\n", .{id});
    self.dedent();
    try b2.writeIndent();
    try b2.write("})");
    const output2 = b2.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output2);
}

/// Generate code for json.dump(obj, file)
/// Writes JSON to file object
pub fn genJsonDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // json.dump() requires at least 2 arguments
    if (args.len < 2) return error.UnsupportedSyntax;

    const id = self.nextNameId();
    const b = try self.getBuilder();
    try b.writeFmt("(__json_dump_{d}: {{\n", .{id});
    self.indent();
    try b.writeIndent();
    try b.write("const _obj = ");
    const output1 = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output1);

    try self.genExpr(args[0]);

    const b2 = try self.getBuilder();
    try b2.write(";\n");
    try b2.writeIndent();
    try b2.write("const _file = ");
    const output2 = b2.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output2);

    try self.genExpr(args[1]);

    const b3 = try self.getBuilder();
    try b3.write(";\n");
    try b3.writeIndent();
    try b3.write("const _json_str = try runtime.json.dumpsValue(_obj, __global_allocator);\n");
    try b3.writeIndent();
    try b3.write("_ = runtime.PyFile.write(_file, _json_str) catch 0;\n");
    try b3.writeIndent();
    try b3.writeFmt("break :__json_dump_{d} null;\n", .{id});
    self.dedent();
    try b3.writeIndent();
    try b3.write("})");
    const output3 = b3.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output3);
}

/// Generate code for json.JSONEncoder class
pub fn genJSONEncoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Return a stub encoder struct
    const b = try self.getBuilder();
    try b.write("struct {\n");
    self.indent();
    try b.writeIndent();
    try b.write("pub fn encode(self: *const @This(), allocator: std.mem.Allocator, obj: anytype) ![]u8 {\n");
    self.indent();
    try b.writeIndent();
    try b.write("_ = self;\n");
    try b.writeIndent();
    try b.write("return try runtime.json.dumpsValue(obj, allocator);\n");
    self.dedent();
    try b.writeIndent();
    try b.write("}\n");
    self.dedent();
    try b.writeIndent();
    try b.write("}{}");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

/// Generate code for json.JSONDecoder class
pub fn genJSONDecoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Return a stub decoder struct
    const b = try self.getBuilder();
    try b.write("struct {\n");
    self.indent();
    try b.writeIndent();
    try b.write("pub fn decode(self: *const @This(), allocator: std.mem.Allocator, s: []const u8) !*runtime.PyObject {\n");
    self.indent();
    try b.writeIndent();
    try b.write("_ = self;\n");
    try b.writeIndent();
    try b.write("const str_obj = try runtime.PyString.create(__global_allocator, s);\n");
    try b.writeIndent();
    try b.write("defer runtime.decref(str_obj, allocator);\n");
    try b.writeIndent();
    try b.write("return try runtime.json.loads(str_obj, allocator);\n");
    self.dedent();
    try b.writeIndent();
    try b.write("}\n");
    self.dedent();
    try b.writeIndent();
    try b.write("}{}");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
