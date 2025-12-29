/// JSON module - json.loads() and json.dumps() code generation
/// MIGRATED TO ZIGBUILDER - All functions use structured callback APIs
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const NativeType = @import("../../analysis/native_types.zig").NativeType;
const type_traits = @import("../../analysis/traits/type_traits.zig");
const container_traits = @import("../../analysis/traits/container_traits.zig");
const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;
const ZigValue = builder_mod.ZigValue;

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
        const b = try self.getBuilder();
        try b.emitRaw("@compileError(\"json.loads() requires exactly 1 argument\")");
        try self.flushBuilder();
        return;
    }

    // Check if argument is already a PyObject (e.g., from file.read())
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    if (type_traits.isUnknown(arg_type)) {
        // Already a PyObject - pass directly to json.loads
        const arg_val = try self.captureExpr(args[0]);
        const b = try self.getBuilder();
        try b.emitTryCallExpr("runtime.json.loads", &.{
            .{ .value = arg_val },
            .{ .value = ZigValue.raw("__global_allocator") },
        });
        try self.flushBuilder();
    } else {
        // String literal or native string - wrap in PyString first
        const arg_val = try self.captureExpr(args[0]);
        const b = try self.getBuilder();

        const Context = struct {
            arg: ZigValue,
        };

        try b.withLabeledBlock("__json_loads", struct {
            fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: Context) !void {
                // const json_str_obj = try runtime.PyString.create(__global_allocator, arg);
                try bld.emitConstWithValue("json_str_obj", "try runtime.PyString.create(__global_allocator, ", ctx.arg, ")");

                // defer runtime.decref(json_str_obj, __global_allocator);
                try bld.emitDefer("runtime.decref(json_str_obj, __global_allocator)");

                // break :label try runtime.json.loads(json_str_obj, __global_allocator);
                try scope.breakWithRaw("try runtime.json.loads(json_str_obj, __global_allocator)");
            }
        }.emit, Context{ .arg = arg_val });

        try self.flushBuilder();
    }
}

/// Generate code for json.dumps(obj)
/// Maps to: runtime.json.dumps(obj, allocator)
/// Handles conversion from native dict/list to PyObject
pub fn genJsonDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        const b = try self.getBuilder();
        try b.emitRaw("@compileError(\"json.dumps() requires exactly 1 argument\")");
        try self.flushBuilder();
        return;
    }

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
        const arg_val = try self.captureExpr(args[0]);
        const b = try self.getBuilder();
        try b.emitTryCallExpr("runtime.json.dumpsValue", &.{
            .{ .value = arg_val },
            .{ .value = ZigValue.raw("__global_allocator") },
        });
        try self.flushBuilder();
    }
}

/// Generate code to convert native dict to PyDict and dump as JSON
fn genJsonDumpsDict(self: *NativeCodegen, dict_expr: ast.Node, value_type: NativeType) CodegenError!void {
    const dict_val = try self.captureExpr(dict_expr);
    const b = try self.getBuilder();

    const Context = struct {
        dict: ZigValue,
        val_type: NativeType,
    };

    try b.withLabeledBlock("__json", struct {
        fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: Context) !void {
            // const _dict_map = <dict_expr>;
            try bld.emitConstWithValue("_dict_map", "", ctx.dict, "");

            // const _py_dict = try runtime.PyDict.create(__global_allocator);
            try bld.emitConstRaw("_py_dict", "try runtime.PyDict.create(__global_allocator)");

            // errdefer runtime.decref(_py_dict, __global_allocator);
            try bld.emitErrdefer("runtime.decref(_py_dict, __global_allocator)");

            // var _it = _dict_map.iterator();
            try bld.emitVarRaw("_it", null, "_dict_map.iterator()");

            // while (_it.next()) |_entry| { ... }
            try bld.withWhileCapture("_it.next()", "_entry", struct {
                fn emit(inner: *ZigBuilder, val_type: NativeType) !void {
                    // Convert value to PyObject based on type
                    try emitValueToPyObject(inner, "_entry.value_ptr.*", val_type);

                    // try runtime.PyDict.set(_py_dict, _entry.key_ptr.*, _py_val);
                    try inner.emitRawLine("try runtime.PyDict.set(_py_dict, _entry.key_ptr.*, _py_val);");
                }
            }.emit, ctx.val_type);

            // const _result = try runtime.json.dumpsDirect(_py_dict, __global_allocator);
            try bld.emitConstRaw("_result", "try runtime.json.dumpsDirect(_py_dict, __global_allocator)");

            // runtime.decref(_py_dict, __global_allocator);
            try bld.emitRawLine("runtime.decref(_py_dict, __global_allocator);");

            // break :label _result;
            try scope.breakWithRaw("_result");
        }
    }.emit, Context{ .dict = dict_val, .val_type = value_type });

    try self.flushBuilder();
}

/// Generate code to convert native list to PyList and dump as JSON
fn genJsonDumpsList(self: *NativeCodegen, list_expr: ast.Node, elem_type: NativeType) CodegenError!void {
    const list_val = try self.captureExpr(list_expr);
    const b = try self.getBuilder();

    const Context = struct {
        list: ZigValue,
        elem_type: NativeType,
    };

    try b.withLabeledBlock("__json", struct {
        fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: Context) !void {
            // const _list_arr = <list_expr>;
            try bld.emitConstWithValue("_list_arr", "", ctx.list, "");

            // const _py_list = try runtime.PyList.create(__global_allocator);
            try bld.emitConstRaw("_py_list", "try runtime.PyList.create(__global_allocator)");

            // errdefer runtime.decref(_py_list, __global_allocator);
            try bld.emitErrdefer("runtime.decref(_py_list, __global_allocator)");

            // for (_list_arr.items) |_item| { ... }
            try bld.withForRaw("_list_arr.items", "_item", struct {
                fn emit(inner: *ZigBuilder, elem_t: NativeType) !void {
                    // Convert element to PyObject based on type
                    try emitValueToPyObject(inner, "_item", elem_t);

                    // try runtime.PyList.append(_py_list, _py_val);
                    try inner.emitRawLine("try runtime.PyList.append(_py_list, _py_val);");
                }
            }.emit, ctx.elem_type);

            // const _result = try runtime.json.dumpsDirect(_py_list, __global_allocator);
            try bld.emitConstRaw("_result", "try runtime.json.dumpsDirect(_py_list, __global_allocator)");

            // runtime.decref(_py_list, __global_allocator);
            try bld.emitRawLine("runtime.decref(_py_list, __global_allocator);");

            // break :label _result;
            try scope.breakWithRaw("_result");
        }
    }.emit, Context{ .list = list_val, .elem_type = elem_type });

    try self.flushBuilder();
}

/// Emit code to convert a native value to PyObject (builder helper)
fn emitValueToPyObject(b: *ZigBuilder, value_expr: []const u8, value_type: NativeType) !void {
    switch (value_type) {
        .int => {
            try b.emitConstRaw("_py_val", try std.fmt.allocPrint(b.allocator, "try runtime.PyInt.create(__global_allocator, {s})", .{value_expr}));
        },
        .float => {
            try b.emitConstRaw("_py_val", try std.fmt.allocPrint(b.allocator, "try runtime.PyFloat.create(__global_allocator, {s})", .{value_expr}));
        },
        .bool => {
            try b.emitConstRaw("_py_val", try std.fmt.allocPrint(b.allocator, "try runtime.PyInt.create(__global_allocator, if ({s}) @as(i64, 1) else @as(i64, 0))", .{value_expr}));
            try b.emitRawLine("_py_val.type_id = .bool;");
        },
        .string => {
            try b.emitConstRaw("_py_val", try std.fmt.allocPrint(b.allocator, "try runtime.PyString.create(__global_allocator, {s})", .{value_expr}));
        },
        else => {
            try b.emitConstRaw("_py_val", try std.fmt.allocPrint(b.allocator, "try runtime.PyString.create(__global_allocator, {s})", .{value_expr}));
        },
    }
}

/// Generate code for json.load(file)
/// Reads from file object and parses JSON
pub fn genJsonLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;

    const file_val = try self.captureExpr(args[0]);
    const b = try self.getBuilder();

    const Context = struct {
        file: ZigValue,
    };

    try b.withLabeledBlock("__json_load", struct {
        fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: Context) !void {
            // const _file = <file_expr>;
            try bld.emitConstWithValue("_file", "", ctx.file, "");

            // const _content = try runtime.PyFile.read(_file, __global_allocator);
            try bld.emitConstRaw("_content", "try runtime.PyFile.read(_file, __global_allocator)");

            // break :label try runtime.json.loads(_content, __global_allocator);
            try scope.breakWithRaw("try runtime.json.loads(_content, __global_allocator)");
        }
    }.emit, Context{ .file = file_val });

    try self.flushBuilder();
}

/// Generate code for json.dump(obj, file)
/// Writes JSON to file object
pub fn genJsonDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;

    const obj_val = try self.captureExpr(args[0]);
    const file_val = try self.captureExpr(args[1]);
    const b = try self.getBuilder();

    const Context = struct {
        obj: ZigValue,
        file: ZigValue,
    };

    try b.withLabeledBlock("__json_dump", struct {
        fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: Context) !void {
            // const _obj = <obj_expr>;
            try bld.emitConstWithValue("_obj", "", ctx.obj, "");

            // const _file = <file_expr>;
            try bld.emitConstWithValue("_file", "", ctx.file, "");

            // const _json_str = try runtime.json.dumpsValue(_obj, __global_allocator);
            try bld.emitConstRaw("_json_str", "try runtime.json.dumpsValue(_obj, __global_allocator)");

            // _ = runtime.PyFile.write(_file, _json_str) catch 0;
            try bld.emitRawLine("_ = runtime.PyFile.write(_file, _json_str) catch 0;");

            // break :label null;
            try scope.breakWithRaw("null");
        }
    }.emit, Context{ .obj = obj_val, .file = file_val });

    try self.flushBuilder();
}

/// Generate code for json.JSONEncoder class
pub fn genJSONEncoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.withStructInstance(struct {
        fn emit(builder: *ZigBuilder, _: void) !void {
            try builder.withPubFnDef("encode", "self_: *const @This(), allocator: std.mem.Allocator, obj: anytype", "![]u8", struct {
                fn emit(bld: *ZigBuilder, _: void) !void {
                    try bld.emitDiscard("self_");
                    try bld.emitReturn(ZigValue.raw("try runtime.json.dumpsValue(obj, allocator)"));
                }
            }.emit, {});
        }
    }.emit, {});
    try self.flushBuilder();
}

/// Generate code for json.JSONDecoder class
pub fn genJSONDecoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.withStructInstance(struct {
        fn emit(builder: *ZigBuilder, _: void) !void {
            try builder.withPubFnDef("decode", "self_: *const @This(), allocator: std.mem.Allocator, s: []const u8", "!*runtime.PyObject", struct {
                fn emit(bld: *ZigBuilder, _: void) !void {
                    try bld.emitDiscard("self_");
                    try bld.emitConstRaw("str_obj", "try runtime.PyString.create(__global_allocator, s)");
                    try bld.emitDefer("runtime.decref(str_obj, allocator)");
                    try bld.emitReturn(ZigValue.raw("try runtime.json.loads(str_obj, allocator)"));
                }
            }.emit, {});
        }
    }.emit, {});
    try self.flushBuilder();
}
