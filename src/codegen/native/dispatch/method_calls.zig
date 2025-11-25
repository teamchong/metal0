/// Method call dispatchers (string, list, dict methods)
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

const methods = @import("../methods.zig");
const pandas_mod = @import("../pandas.zig");
const unittest_mod = @import("../unittest/mod.zig");

// Handler type for standard methods (obj, args)
const MethodHandler = *const fn (*NativeCodegen, ast.Node, []ast.Node) CodegenError!void;

// Handler type for pandas column methods (obj only)
const ColumnHandler = *const fn (*NativeCodegen, ast.Node) CodegenError!void;

// String methods - O(1) lookup via StaticStringMap
const StringMethods = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "split", methods.genSplit },
    .{ "upper", methods.genUpper },
    .{ "lower", methods.genLower },
    .{ "strip", methods.genStrip },
    .{ "replace", methods.genReplace },
    .{ "join", methods.genJoin },
    .{ "startswith", methods.genStartswith },
    .{ "endswith", methods.genEndswith },
    .{ "find", methods.genFind },
    .{ "isdigit", methods.genIsdigit },
    .{ "isalpha", methods.genIsalpha },
    .{ "isalnum", methods.genIsalnum },
    .{ "isspace", methods.genIsspace },
    .{ "islower", methods.genIslower },
    .{ "isupper", methods.genIsupper },
    .{ "lstrip", methods.genLstrip },
    .{ "rstrip", methods.genRstrip },
    .{ "capitalize", methods.genCapitalize },
    .{ "title", methods.genTitle },
    .{ "swapcase", methods.genSwapcase },
    .{ "rfind", methods.genRfind },
    .{ "rindex", methods.genRindex },
    .{ "ljust", methods.genLjust },
    .{ "rjust", methods.genRjust },
    .{ "center", methods.genCenter },
    .{ "zfill", methods.genZfill },
    .{ "isascii", methods.genIsascii },
    .{ "istitle", methods.genIstitle },
    .{ "isprintable", methods.genIsprintable },
});

// List methods - O(1) lookup via StaticStringMap
const ListMethods = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "append", methods.genAppend },
    .{ "pop", methods.genPop },
    .{ "extend", methods.genExtend },
    .{ "insert", methods.genInsert },
    .{ "remove", methods.genRemove },
    .{ "reverse", methods.genReverse },
    .{ "sort", methods.genSort },
    .{ "clear", methods.genClear },
    .{ "copy", methods.genCopy },
});

// Dict methods - O(1) lookup via StaticStringMap
const DictMethods = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "keys", methods.genKeys },
    .{ "values", methods.genValues },
    .{ "items", methods.genItems },
});

// Pandas column methods - O(1) lookup via StaticStringMap
const PandasColumnMethods = std.StaticStringMap(ColumnHandler).initComptime(.{
    .{ "sum", pandas_mod.genColumnSum },
    .{ "mean", pandas_mod.genColumnMean },
    .{ "describe", pandas_mod.genColumnDescribe },
    .{ "min", pandas_mod.genColumnMin },
    .{ "max", pandas_mod.genColumnMax },
    .{ "std", pandas_mod.genColumnStd },
});

// Special method types for dispatch
const SpecialMethodType = enum { count, index, get };

// Special methods lookup - O(1)
const SpecialMethods = std.StaticStringMap(SpecialMethodType).initComptime(.{
    .{ "count", .count },
    .{ "index", .index },
    .{ "get", .get },
});

// Queue method output patterns
const QueueMethodOutput = struct {
    prefix: []const u8,
    suffix: []const u8,
    has_arg: bool,
};

// Queue methods lookup - O(1)
const QueueMethods = std.StaticStringMap(QueueMethodOutput).initComptime(.{
    .{ "put_nowait", QueueMethodOutput{ .prefix = "try ", .suffix = ".put_nowait(", .has_arg = true } },
    .{ "get_nowait", QueueMethodOutput{ .prefix = "try ", .suffix = ".get_nowait()", .has_arg = false } },
    .{ "empty", QueueMethodOutput{ .prefix = "", .suffix = ".empty()", .has_arg = false } },
    .{ "full", QueueMethodOutput{ .prefix = "", .suffix = ".full()", .has_arg = false } },
    .{ "qsize", QueueMethodOutput{ .prefix = "", .suffix = ".qsize()", .has_arg = false } },
});

// unittest assertion methods - O(1) lookup
const UnittestMethods = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "assertEqual", unittest_mod.genAssertEqual },
    .{ "assertTrue", unittest_mod.genAssertTrue },
    .{ "assertFalse", unittest_mod.genAssertFalse },
    .{ "assertIsNone", unittest_mod.genAssertIsNone },
    .{ "assertGreater", unittest_mod.genAssertGreater },
    .{ "assertLess", unittest_mod.genAssertLess },
    .{ "assertGreaterEqual", unittest_mod.genAssertGreaterEqual },
    .{ "assertLessEqual", unittest_mod.genAssertLessEqual },
    .{ "assertNotEqual", unittest_mod.genAssertNotEqual },
    .{ "assertIs", unittest_mod.genAssertIs },
    .{ "assertIsNot", unittest_mod.genAssertIsNot },
    .{ "assertIsNotNone", unittest_mod.genAssertIsNotNone },
    .{ "assertIn", unittest_mod.genAssertIn },
    .{ "assertNotIn", unittest_mod.genAssertNotIn },
    .{ "assertAlmostEqual", unittest_mod.genAssertAlmostEqual },
    .{ "assertNotAlmostEqual", unittest_mod.genAssertNotAlmostEqual },
    .{ "assertCountEqual", unittest_mod.genAssertCountEqual },
    .{ "assertRaises", unittest_mod.genAssertRaises },
    .{ "assertRegex", unittest_mod.genAssertRegex },
    .{ "assertNotRegex", unittest_mod.genAssertNotRegex },
    .{ "assertIsInstance", unittest_mod.genAssertIsInstance },
    .{ "assertNotIsInstance", unittest_mod.genAssertNotIsInstance },
});

/// Try to dispatch method call (obj.method())
/// Returns true if dispatched successfully
pub fn tryDispatch(self: *NativeCodegen, call: ast.Node.Call) CodegenError!bool {
    if (call.func.* != .attribute) return false;

    const method_name = call.func.attribute.attr;
    const obj = call.func.attribute.value.*;

    // Handle super().method() calls for inheritance
    if (try handleSuperCall(self, call, method_name, obj)) {
        return true;
    }

    // Try string methods first (most common)
    if (StringMethods.get(method_name)) |handler| {
        try handler(self, obj, call.args);
        return true;
    }

    // Try list methods
    if (ListMethods.get(method_name)) |handler| {
        try handler(self, obj, call.args);
        return true;
    }

    // Try dict methods
    if (DictMethods.get(method_name)) |handler| {
        try handler(self, obj, call.args);
        return true;
    }

    // Special cases that need custom handling (count, index, get)
    if (try handleSpecialMethods(self, call, method_name, obj)) {
        return true;
    }

    // Queue methods (asyncio.Queue)
    if (try handleQueueMethods(self, call, method_name, obj)) {
        return true;
    }

    // Pandas column methods (DataFrame column operations)
    if (obj == .subscript) { // df['col'].method()
        if (PandasColumnMethods.get(method_name)) |handler| {
            try handler(self, obj);
            return true;
        }
    }

    // unittest assertion methods (self.assertEqual, etc.)
    // Check if obj is 'self' - unittest methods called on self
    if (obj == .name and std.mem.eql(u8, obj.name.id, "self")) {
        // Special handling for subTest which needs keyword arguments
        if (std.mem.eql(u8, method_name, "subTest")) {
            try unittest_mod.genSubTest(self, obj, call.args, call.keyword_args);
            return true;
        }
        if (UnittestMethods.get(method_name)) |handler| {
            try handler(self, obj, call.args);
            return true;
        }
    }

    return false;
}

/// Handle methods that need special logic (count, index, get)
fn handleSpecialMethods(self: *NativeCodegen, call: ast.Node.Call, method_name: []const u8, obj: ast.Node) CodegenError!bool {
    const method_type = SpecialMethods.get(method_name) orelse return false;

    switch (method_type) {
        .count => {
            // count - needs type-based dispatch (list vs string)
            const is_list = blk: {
                if (obj == .name) {
                    const var_name = obj.name.id;
                    if (self.getSymbolType(var_name)) |var_type| {
                        break :blk var_type == .list;
                    }
                }
                break :blk false;
            };

            if (is_list) {
                const genListCount = @import("../methods/list.zig").genCount;
                try genListCount(self, obj, call.args);
            } else {
                try methods.genCount(self, obj, call.args);
            }
        },
        .index => {
            // index - string version (genStrIndex) vs list version
            try methods.genStrIndex(self, obj, call.args);
        },
        .get => {
            // get - only dict.get(key) with args
            if (call.args.len == 0) return false;
            try methods.genGet(self, obj, call.args);
        },
    }
    return true;
}

/// Handle super().method() calls for inheritance
/// Pattern: super().foo(args) -> ParentClass.foo(@ptrCast(self), args)
fn handleSuperCall(self: *NativeCodegen, call: ast.Node.Call, method_name: []const u8, obj: ast.Node) CodegenError!bool {
    // Check if obj is a call to super()
    if (obj != .call) return false;
    const super_call = obj.call;
    if (super_call.func.* != .name) return false;
    if (!std.mem.eql(u8, super_call.func.name.id, "super")) return false;

    // We're inside super().method() - need to find parent class
    const current_class = self.current_class_name orelse {
        // Not inside a class method - can't use super()
        return false;
    };

    const parent_class = self.getParentClassName(current_class) orelse {
        // No parent class - can't use super()
        return false;
    };

    const parent = @import("../expressions.zig");

    // Generate: ParentClass.method(@ptrCast(self), args)
    // Need @ptrCast because self is *const Child but parent method expects *const Parent
    try self.output.appendSlice(self.allocator, parent_class);
    try self.output.appendSlice(self.allocator, ".");
    try self.output.appendSlice(self.allocator, method_name);
    try self.output.appendSlice(self.allocator, "(@ptrCast(self)");

    // Add remaining arguments
    for (call.args) |arg| {
        try self.output.appendSlice(self.allocator, ", ");
        try parent.genExpr(self, arg);
    }

    try self.output.appendSlice(self.allocator, ")");
    return true;
}

/// Handle asyncio.Queue methods
fn handleQueueMethods(self: *NativeCodegen, call: ast.Node.Call, method_name: []const u8, obj: ast.Node) CodegenError!bool {
    const queue_method = QueueMethods.get(method_name) orelse return false;
    const parent = @import("../expressions.zig");

    if (queue_method.prefix.len > 0) {
        try self.output.appendSlice(self.allocator, queue_method.prefix);
    }
    try parent.genExpr(self, obj);
    try self.output.appendSlice(self.allocator, queue_method.suffix);

    if (queue_method.has_arg) {
        if (call.args.len > 0) {
            try parent.genExpr(self, call.args[0]);
        }
        try self.output.appendSlice(self.allocator, ")");
    }

    return true;
}
