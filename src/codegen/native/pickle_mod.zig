/// Python pickle module - Object serialization (uses JSON as backing format)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;
const json = @import("json.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dumps", genDumps }, .{ "loads", genLoads }, .{ "dump", genDump }, .{ "load", genLoad },
    .{ "HIGHEST_PROTOCOL", h.I64(5) }, .{ "DEFAULT_PROTOCOL", h.I64(4) },
    .{ "PicklingError", h.err("PicklingError") }, .{ "UnpicklingError", h.err("UnpicklingError") },
    .{ "Pickler", h.c("try runtime.io.BytesIO.create(__global_allocator)") },
    .{ "Unpickler", h.c("try runtime.io.BytesIO.create(__global_allocator)") },
});

pub fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    if (arg_type == .dict) {
        try self.emit("pickle_blk: { const _dict_map = "); try self.genExpr(args[0]);
        const value_type = arg_type.dict.value.*;
        if (value_type == .int) {
            try self.emit("; const _py_dict = try runtime.PyDict.create(__global_allocator); defer runtime.decref(_py_dict, __global_allocator); var _it = _dict_map.iterator(); while (_it.next()) |_entry| { const _py_val = try runtime.PyInt.create(__global_allocator, _entry.value_ptr.*); try runtime.PyDict.set(_py_dict, _entry.key_ptr.*, _py_val); } break :pickle_blk try runtime.json.dumpsDirect(_py_dict, __global_allocator); }");
        } else if (value_type == .float) {
            try self.emit("; const _py_dict = try runtime.PyDict.create(__global_allocator); defer runtime.decref(_py_dict, __global_allocator); var _it = _dict_map.iterator(); while (_it.next()) |_entry| { const _py_val = try runtime.PyFloat.create(__global_allocator, _entry.value_ptr.*); try runtime.PyDict.set(_py_dict, _entry.key_ptr.*, _py_val); } break :pickle_blk try runtime.json.dumpsDirect(_py_dict, __global_allocator); }");
        } else {
            try self.emit("; const _py_dict = try runtime.PyDict.create(__global_allocator); defer runtime.decref(_py_dict, __global_allocator); var _it = _dict_map.iterator(); while (_it.next()) |_entry| { const _py_val = try runtime.PyString.create(__global_allocator, _entry.value_ptr.*); try runtime.PyDict.set(_py_dict, _entry.key_ptr.*, _py_val); } break :pickle_blk try runtime.json.dumpsDirect(_py_dict, __global_allocator); }");
        }
    } else if (arg_type == .list) {
        try self.emit("try runtime.json.dumpsDirect(try runtime.PyList.fromArrayList("); try self.genExpr(args[0]); try self.emit(", __global_allocator), __global_allocator)");
    } else if (arg_type == .bool) {
        const use_binary = args.len > 1 and args[1] == .constant and args[1].constant.value == .int and args[1].constant.value.int >= 2;
        if (use_binary) { try self.emit("if ("); try self.genExpr(args[0]); try self.emit(") \"\\x80\\x02\\x88.\" else \"\\x80\\x02\\x89.\""); }
        else { try self.emit("if ("); try self.genExpr(args[0]); try self.emit(") \"I01\\n.\" else \"I00\\n.\""); }
    } else if (arg_type == .int) {
        try self.emit("try runtime.json.dumpsDirect(try runtime.PyInt.create(__global_allocator, "); try self.genExpr(args[0]); try self.emit("), __global_allocator)");
    } else if (arg_type == .float) {
        try self.emit("try runtime.json.dumpsDirect(try runtime.PyFloat.create(__global_allocator, "); try self.genExpr(args[0]); try self.emit("), __global_allocator)");
    } else if (arg_type == .string or @as(std.meta.Tag(@TypeOf(arg_type)), arg_type) == .string) {
        try self.emit("try runtime.json.dumpsDirect(try runtime.PyString.create(__global_allocator, "); try self.genExpr(args[0]); try self.emit("), __global_allocator)");
    } else {
        try self.emit("try runtime.json.dumpsDirect("); try self.genExpr(args[0]); try self.emit(", __global_allocator)");
    }
}

pub const genLoads = h.wrap("runtime.pickleLoads(", ")", "null");

pub fn genDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("pickle_dump_blk: { const _json_str = ");
    try json.genJsonDumps(self, args[0..1]);
    try self.emit("; const _file = "); try self.genExpr(args[1]);
    try self.emit("; _ = _file.write(_json_str) catch 0; break :pickle_dump_blk; }");
}

pub fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("pickle_load_blk: { const _file = "); try self.genExpr(args[0]);
    try self.emit("; const _content = _file.reader().readAllAlloc(__global_allocator, 10 * 1024 * 1024) catch break :pickle_load_blk @as(*runtime.PyObject, undefined); const _json_str_obj = try runtime.PyString.create(__global_allocator, _content); defer runtime.decref(_json_str_obj, __global_allocator); break :pickle_load_blk try runtime.json.loads(_json_str_obj, __global_allocator); }");
}
