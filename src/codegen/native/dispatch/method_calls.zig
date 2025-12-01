/// Method call dispatchers (string, list, dict methods)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const zig_keywords = @import("zig_keywords");

const methods = @import("../methods.zig");
const io_mod = @import("../io.zig");
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
    .{ "isdecimal", methods.genIsdecimal },
    .{ "isnumeric", methods.genIsnumeric },
    .{ "encode", methods.genEncode },
    .{ "decode", methods.genDecode },
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
    // Deque methods (deque uses ArrayList internally)
    .{ "appendleft", methods.genAppendleft },
    .{ "popleft", methods.genPopleft },
    .{ "extendleft", methods.genExtendleft },
    .{ "rotate", methods.genRotate },
});

// Dict methods - O(1) lookup via StaticStringMap
const DictMethods = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "keys", methods.genKeys },
    .{ "values", methods.genValues },
    .{ "items", methods.genItems },
});

// File methods - O(1) lookup via StaticStringMap
const FileMethods = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "read", methods.genFileRead },
    .{ "write", methods.genFileWrite },
    .{ "close", methods.genFileClose },
});

// Float methods - O(1) lookup via StaticStringMap
const FloatMethods = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "is_integer", methods.genFloatIsInteger },
    .{ "as_integer_ratio", methods.genFloatAsIntegerRatio },
    .{ "hex", methods.genFloatHex },
    .{ "conjugate", methods.genFloatConjugate },
    .{ "__truediv__", methods.genFloatTruediv },
    .{ "__rtruediv__", methods.genFloatRtruediv },
    .{ "__floordiv__", methods.genFloatFloordiv },
    .{ "__mod__", methods.genFloatMod },
    .{ "__floor__", methods.genFloatFloor },
    .{ "__ceil__", methods.genFloatCeil },
    .{ "__trunc__", methods.genFloatTrunc },
    .{ "__round__", methods.genFloatRound },
});

// StringIO/BytesIO stream methods - O(1) lookup
const StreamMethods = std.StaticStringMap(void).initComptime(.{
    .{ "write", {} },
    .{ "read", {} },
    .{ "getvalue", {} },
    .{ "seek", {} },
    .{ "tell", {} },
    .{ "truncate", {} },
    .{ "close", {} },
});

// HashObject methods (hashlib.md5(), sha256(), etc.) - O(1) lookup
const HashMethods = std.StaticStringMap(void).initComptime(.{
    .{ "update", {} },
    .{ "digest", {} },
    .{ "hexdigest", {} },
    .{ "copy", {} },
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

// SQLite3 Cursor methods - O(1) lookup
const SqliteCursorMethodOutput = struct {
    prefix: []const u8,
    suffix: []const u8,
    has_arg: bool,
};

const SqliteCursorMethods = std.StaticStringMap(SqliteCursorMethodOutput).initComptime(.{
    .{ "execute", SqliteCursorMethodOutput{ .prefix = "try ", .suffix = ".execute(", .has_arg = true } },
    .{ "executemany", SqliteCursorMethodOutput{ .prefix = "try ", .suffix = ".executemany(", .has_arg = true } },
    .{ "fetchone", SqliteCursorMethodOutput{ .prefix = "try ", .suffix = ".fetchone()", .has_arg = false } },
    .{ "fetchall", SqliteCursorMethodOutput{ .prefix = "try ", .suffix = ".fetchall()", .has_arg = false } },
    .{ "fetchmany", SqliteCursorMethodOutput{ .prefix = "try ", .suffix = ".fetchmany(", .has_arg = true } },
    .{ "close", SqliteCursorMethodOutput{ .prefix = "", .suffix = ".close()", .has_arg = false } },
});

// SQLite3 Connection methods - O(1) lookup
const SqliteConnectionMethods = std.StaticStringMap(SqliteCursorMethodOutput).initComptime(.{
    .{ "cursor", SqliteCursorMethodOutput{ .prefix = "", .suffix = ".cursor()", .has_arg = false } },
    .{ "execute", SqliteCursorMethodOutput{ .prefix = "try ", .suffix = ".execute(", .has_arg = true } },
    .{ "commit", SqliteCursorMethodOutput{ .prefix = "try ", .suffix = ".commit()", .has_arg = false } },
    .{ "rollback", SqliteCursorMethodOutput{ .prefix = "try ", .suffix = ".rollback()", .has_arg = false } },
    .{ "close", SqliteCursorMethodOutput{ .prefix = "", .suffix = ".close()", .has_arg = false } },
});

// unittest assertion methods - O(1) lookup
pub const UnittestMethods = std.StaticStringMap(MethodHandler).initComptime(.{
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
    .{ "assertRaisesRegex", unittest_mod.genAssertRaisesRegex },
    .{ "assertRegex", unittest_mod.genAssertRegex },
    .{ "assertNotRegex", unittest_mod.genAssertNotRegex },
    .{ "assertIsInstance", unittest_mod.genAssertIsInstance },
    .{ "assertNotIsInstance", unittest_mod.genAssertNotIsInstance },
    .{ "assertIsSubclass", unittest_mod.genAssertIsSubclass },
    .{ "assertNotIsSubclass", unittest_mod.genAssertNotIsSubclass },
    .{ "assertWarns", unittest_mod.genAssertWarns },
    .{ "assertWarnsRegex", unittest_mod.genAssertWarnsRegex },
    .{ "assertStartsWith", unittest_mod.genAssertStartsWith },
    .{ "assertNotStartsWith", unittest_mod.genAssertNotStartsWith },
    .{ "assertEndsWith", unittest_mod.genAssertEndsWith },
    .{ "assertHasAttr", unittest_mod.genAssertHasAttr },
    .{ "assertNotHasAttr", unittest_mod.genAssertNotHasAttr },
    .{ "assertSequenceEqual", unittest_mod.genAssertSequenceEqual },
    .{ "assertListEqual", unittest_mod.genAssertListEqual },
    .{ "assertTupleEqual", unittest_mod.genAssertTupleEqual },
    .{ "assertSetEqual", unittest_mod.genAssertSetEqual },
    .{ "assertDictEqual", unittest_mod.genAssertDictEqual },
    .{ "assertMultiLineEqual", unittest_mod.genAssertMultiLineEqual },
    .{ "assertLogs", unittest_mod.genAssertLogs },
    .{ "assertNoLogs", unittest_mod.genAssertNoLogs },
    .{ "fail", unittest_mod.genFail },
    .{ "skipTest", unittest_mod.genSkipTest },
    .{ "assertFloatsAreIdentical", unittest_mod.genAssertFloatsAreIdentical },
    .{ "addCleanup", unittest_mod.genAddCleanup },
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

    // Handle explicit parent __init__/__new__ calls: Parent.__init__(self) or module.Type.__new__(cls)
    // These are used in class inheritance to call parent's __init__ or __new__
    if (std.mem.eql(u8, method_name, "__init__") or std.mem.eql(u8, method_name, "__new__")) {
        // Check if obj is an attribute access (module.Type or just Type)
        // Pattern: array.array.__init__(self) -> emit {}
        // Pattern: str.__new__(cls, value) -> emit value (for builtin base types)
        if (obj == .attribute or obj == .name) {
            const parent_name = if (obj == .name) obj.name.id else if (obj == .attribute) obj.attribute.attr else "";

            // For builtin types (str, int, float, bool), __new__ creates an instance with a value
            // e.g., float.__new__(cls, 2*value) should return 2*value as the base value
            const is_builtin_new = std.mem.eql(u8, method_name, "__new__") and
                (std.mem.eql(u8, parent_name, "str") or
                std.mem.eql(u8, parent_name, "int") or
                std.mem.eql(u8, parent_name, "float") or
                std.mem.eql(u8, parent_name, "bool"));

            if (is_builtin_new) {
                if (call.args.len >= 2) {
                    // Return the value argument (second arg after cls)
                    // e.g., bool.__new__(bool, 1) -> true, bool.__new__(bool, 0) -> false
                    if (std.mem.eql(u8, parent_name, "bool")) {
                        try self.emit("runtime.toBool(");
                        try self.genExpr(call.args[1]);
                        try self.emit(")");
                    } else {
                        try self.genExpr(call.args[1]);
                    }
                    return true;
                } else {
                    // No value argument - return default for the type
                    // bool.__new__(bool) -> false, int.__new__(int) -> 0, etc.
                    if (std.mem.eql(u8, parent_name, "bool")) {
                        try self.emit("false");
                    } else if (std.mem.eql(u8, parent_name, "int")) {
                        try self.emit("@as(i64, 0)");
                    } else if (std.mem.eql(u8, parent_name, "float")) {
                        try self.emit("@as(f64, 0.0)");
                    } else if (std.mem.eql(u8, parent_name, "str")) {
                        try self.emit("\"\"");
                    } else {
                        try self.emit("{}");
                    }
                    return true;
                }
            }

            // For __init__ or __new__ without value, emit no-op
            // The actual initialization is handled by struct init
            try self.emit("{}");
            return true;
        }
    }

    // Handle explicit parent method calls: Parent.method(self, ...) for complex parent types
    // Pattern: array.array.__getitem__(self, i) when class inherits from array.array
    if (try handleComplexParentMethodCall(self, call, method_name, obj)) {
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

    // Try float methods (is_integer, as_integer_ratio, hex, conjugate)
    // Float methods are unambiguous (no other type has these methods), so we can
    // dispatch regardless of inferred type. This handles:
    // - Direct float literals: (1.0).is_integer()
    // - Variables inferred as float: f.is_integer()
    // - Tuple field access: __tuple__.@"0".as_integer_ratio()
    // Since no other Python type has these methods, dispatching is always safe.
    if (FloatMethods.get(method_name)) |handler| {
        try handler(self, obj, call.args);
        return true;
    }

    // Try file/stream methods with type-aware dispatch
    if (FileMethods.has(method_name) or StreamMethods.has(method_name)) {
        // Infer object type to dispatch correctly
        const obj_type = self.type_inferrer.inferExpr(obj) catch .unknown;
        if (obj_type == .stringio or obj_type == .bytesio) {
            // StringIO/BytesIO stream methods
            if (try handleStreamMethod(self, method_name, obj, call.args)) {
                return true;
            }
        } else if (obj_type == .file or obj_type == .unknown) {
            // File methods (PyFile) - only for actual file objects or unknown types
            // Skip if it's a known non-file type like sqlite_connection
            if (FileMethods.get(method_name)) |handler| {
                try handler(self, obj, call.args);
                return true;
            }
        }
    }

    // HashObject methods (hashlib hash objects)
    if (HashMethods.has(method_name)) {
        const obj_type = self.type_inferrer.inferExpr(obj) catch .unknown;
        if (obj_type == .hash_object) {
            if (try handleHashMethod(self, method_name, obj, call.args)) {
                return true;
            }
        }
    }

    // Special cases that need custom handling (count, index, get)
    if (try handleSpecialMethods(self, call, method_name, obj)) {
        return true;
    }

    // Queue methods (asyncio.Queue)
    if (try handleQueueMethods(self, call, method_name, obj)) {
        return true;
    }

    // SQLite3 methods (Connection and Cursor)
    if (try handleSqliteMethods(self, call, method_name, obj)) {
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
            // count only handles single-arg case; fall through for other arities
            if (call.args.len != 1) return false;

            // count - needs type-based dispatch (list vs string)
            const is_list = blk: {
                // Check for list literal
                if (obj == .list) break :blk true;
                // Check for list variable
                if (obj == .name) {
                    const var_name = obj.name.id;
                    if (self.getSymbolType(var_name)) |var_type| {
                        break :blk var_type == .list;
                    }
                }
                // Infer from type_inferrer
                const obj_type = self.type_inferrer.inferExpr(obj) catch .unknown;
                break :blk obj_type == .list;
            };

            if (is_list) {
                const genListCount = @import("../methods/list.zig").genCount;
                try genListCount(self, obj, call.args);
            } else {
                try methods.genCount(self, obj, call.args);
            }
        },
        .index => {
            // index only handles single-arg case; fall through for other arities
            // (e.g., a.index(0, 2) with start/end params should use native method)
            if (call.args.len != 1) return false;

            // index - string version (genStrIndex) vs list version
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
                const genListIndex = @import("../methods/list.zig").genIndex;
                try genListIndex(self, obj, call.args);
            } else {
                try methods.genStrIndex(self, obj, call.args);
            }
        },
        .get => {
            // get - only dict.get(key) with args, NOT module.get() like requests.get()
            if (call.args.len == 0) return false;
            // Skip if obj is a name that's an imported module
            if (obj == .name) {
                if (self.imported_modules.contains(obj.name.id)) {
                    return false; // Let module function handler deal with it
                }
            }
            try methods.genGet(self, obj, call.args);
        },
    }
    return true;
}

/// Handle explicit parent method calls for complex parent types (like array.array)
/// Pattern: array.array.__getitem__(self, i) -> inlined parent method code
fn handleComplexParentMethodCall(self: *NativeCodegen, call: ast.Node.Call, method_name: []const u8, obj: ast.Node) CodegenError!bool {
    // Check if we're inside a class with a complex parent
    const parent_name = self.current_class_parent orelse return false;

    // Check if obj is an attribute access matching the parent (e.g., array.array)
    if (obj != .attribute) return false;
    const attr = obj.attribute;

    // Build the full parent name from the attribute chain (e.g., "array.array")
    var parent_full_name: []const u8 = undefined;
    if (attr.value.* == .name) {
        // Pattern: module.Type (e.g., array.array)
        const module_name = attr.value.name.id;
        const type_name = attr.attr;

        // Allocate and format the full name
        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("{s}.{s}", .{ module_name, type_name });
        parent_full_name = buf.items;
        defer buf.deinit(self.allocator);

        // Check if this matches our current class's parent
        if (!std.mem.eql(u8, parent_full_name, parent_name)) return false;
    } else {
        return false;
    }

    // Look up the complex parent info
    const generators = @import("../statements/functions/generators.zig");
    const parent_info = generators.getComplexParentInfo(parent_name) orelse return false;

    // Find the method in the parent's methods
    for (parent_info.methods) |method| {
        if (std.mem.eql(u8, method.name, method_name)) {
            // Found the method - inline the code with argument substitution
            // Skip 'self' argument (first arg) when substituting
            var code = method.inline_code;

            // Replace {self} with the self variable name
            // The first argument to parent method is 'self'
            const self_var = if (self.method_nesting_depth > 0) "__self" else "self";

            // Build the output by substituting placeholders
            var result = std.ArrayList(u8){};
            var i: usize = 0;
            while (i < code.len) {
                if (code[i] == '{') {
                    // Find closing brace
                    var j = i + 1;
                    while (j < code.len and code[j] != '}') : (j += 1) {}
                    if (j < code.len) {
                        const placeholder = code[i + 1 .. j];
                        if (std.mem.eql(u8, placeholder, "self")) {
                            // Replace {self} with actual self variable
                            try result.appendSlice(self.allocator, self_var);
                        } else {
                            // Replace {0}, {1}, etc. with call arguments (after self)
                            const arg_idx = std.fmt.parseInt(usize, placeholder, 10) catch {
                                try result.append(self.allocator, code[i]);
                                i += 1;
                                continue;
                            };
                            // Arguments in call: first is 'self', so we want arg_idx + 1
                            if (arg_idx + 1 < call.args.len) {
                                const arg = call.args[arg_idx + 1];
                                const genExpr = @import("../expressions.zig").genExpr;
                                const output_before = self.output.items.len;
                                try genExpr(self, arg);
                                const arg_code = self.output.items[output_before..];
                                try result.appendSlice(self.allocator, arg_code);
                                // Remove from main output - we're building our own
                                self.output.shrinkRetainingCapacity(output_before);
                            } else {
                                try result.appendSlice(self.allocator, "undefined");
                            }
                        }
                        i = j + 1;
                        continue;
                    }
                }
                try result.append(self.allocator, code[i]);
                i += 1;
            }

            // Emit the result
            try self.emit(result.items);
            result.deinit(self.allocator);
            return true;
        }
    }

    return false;
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
        // No parent class found (e.g., inheriting from external module like unittest.TestCase)
        // Generate a no-op {} since we can't call the actual parent method
        // This is safe because test methods in unittest typically don't need parent return values
        try self.emit("{}");
        return true;
    };

    const parent = @import("../expressions.zig");

    // Generate: ParentClass.method(@ptrCast(@constCast(self)), args)
    // Need @constCast because self is *const Child, and parent method may expect mutable pointer
    // Need @ptrCast because self is *Child but parent method expects *Parent
    // Escape method name if it's a Zig keyword (e.g., "test" -> @"test")
    try self.emit(parent_class);
    try self.emit(".");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method_name);
    try self.emit("(@ptrCast(@constCast(self))");

    // Add remaining arguments
    for (call.args) |arg| {
        try self.emit(", ");
        try parent.genExpr(self, arg);
    }

    try self.emit(")");
    return true;
}

/// Handle asyncio.Queue methods
fn handleQueueMethods(self: *NativeCodegen, call: ast.Node.Call, method_name: []const u8, obj: ast.Node) CodegenError!bool {
    const queue_method = QueueMethods.get(method_name) orelse return false;
    const parent = @import("../expressions.zig");

    if (queue_method.prefix.len > 0) {
        try self.emit(queue_method.prefix);
    }
    try parent.genExpr(self, obj);
    try self.emit(queue_method.suffix);

    if (queue_method.has_arg) {
        if (call.args.len > 0) {
            try parent.genExpr(self, call.args[0]);
        }
        try self.emit(")");
    }

    return true;
}

/// Handle StringIO/BytesIO stream methods
fn handleStreamMethod(self: *NativeCodegen, method_name: []const u8, obj: ast.Node, args: []ast.Node) CodegenError!bool {
    const parent = @import("../expressions.zig");

    // Generate receiver expression once
    var receiver_buf = std.ArrayList(u8){};
    defer receiver_buf.deinit(self.allocator);
    const saved_output = self.output;
    self.output = receiver_buf;
    try parent.genExpr(self, obj);
    const receiver = try self.output.toOwnedSlice(self.allocator);
    defer self.allocator.free(receiver);
    self.output = saved_output;

    // Use simple string comparison for method dispatch
    const fnv = @import("fnv_hash");
    const WRITE = comptime fnv.hash("write");
    const READ = comptime fnv.hash("read");
    const GETVALUE = comptime fnv.hash("getvalue");
    const SEEK = comptime fnv.hash("seek");
    const TELL = comptime fnv.hash("tell");
    const TRUNCATE = comptime fnv.hash("truncate");
    const CLOSE = comptime fnv.hash("close");

    const method_hash = fnv.hash(method_name);
    if (method_hash == WRITE) {
        // stream.write(data) - returns bytes written (caller handles discard if needed)
        try self.emit(receiver);
        try self.emit(".write(");
        if (args.len > 0) try parent.genExpr(self, args[0]);
        try self.emit(")");
    } else if (method_hash == READ) {
        try self.emit(receiver);
        try self.emit(".read()");
    } else if (method_hash == GETVALUE) {
        try self.emit(receiver);
        try self.emit(".getvalue()");
    } else if (method_hash == SEEK) {
        try self.emit(receiver);
        try self.emit(".seek(");
        if (args.len > 0) try parent.genExpr(self, args[0]) else try self.emit("0");
        try self.emit(")");
    } else if (method_hash == TELL) {
        try self.emit(receiver);
        try self.emit(".tell()");
    } else if (method_hash == TRUNCATE) {
        try self.emit(receiver);
        try self.emit(".truncate()");
    } else if (method_hash == CLOSE) {
        try self.emit(receiver);
        try self.emit(".close()");
    } else {
        return false;
    }
    return true;
}

/// Handle HashObject methods (update, digest, hexdigest, copy)
fn handleHashMethod(self: *NativeCodegen, method_name: []const u8, obj: ast.Node, args: []ast.Node) CodegenError!bool {
    const parent = @import("../expressions.zig");

    // Generate receiver expression once
    var receiver_buf = std.ArrayList(u8){};
    defer receiver_buf.deinit(self.allocator);
    const saved_output = self.output;
    self.output = receiver_buf;
    try parent.genExpr(self, obj);
    const receiver = try self.output.toOwnedSlice(self.allocator);
    defer self.allocator.free(receiver);
    self.output = saved_output;

    const fnv = @import("fnv_hash");
    const UPDATE = comptime fnv.hash("update");
    const DIGEST = comptime fnv.hash("digest");
    const HEXDIGEST = comptime fnv.hash("hexdigest");
    const COPY = comptime fnv.hash("copy");

    const method_hash = fnv.hash(method_name);
    if (method_hash == UPDATE) {
        // h.update(data) - modifies in place
        try self.emit(receiver);
        try self.emit(".update(");
        if (args.len > 0) try parent.genExpr(self, args[0]);
        try self.emit(")");
    } else if (method_hash == DIGEST) {
        // h.digest(allocator) - returns bytes
        const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
        try self.emit("try ");
        try self.emit(receiver);
        try self.emitFmt(".digest({s})", .{alloc_name});
    } else if (method_hash == HEXDIGEST) {
        // h.hexdigest(allocator) - returns hex string
        // Use scope-aware allocator: __global_allocator in functions, allocator in main()
        const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
        try self.emit("try ");
        try self.emit(receiver);
        try self.emitFmt(".hexdigest({s})", .{alloc_name});
    } else if (method_hash == COPY) {
        // h.copy() - returns a copy
        try self.emit(receiver);
        try self.emit(".copy()");
    } else {
        return false;
    }
    return true;
}

/// Handle SQLite3 Connection and Cursor methods
fn handleSqliteMethods(self: *NativeCodegen, call: ast.Node.Call, method_name: []const u8, obj: ast.Node) CodegenError!bool {
    // Check object type to determine if this is a sqlite3 object
    const obj_type = self.type_inferrer.inferExpr(obj) catch .unknown;

    const parent = @import("../expressions.zig");

    // Handle sqlite3.Cursor methods
    if (obj_type == .sqlite_cursor) {
        if (SqliteCursorMethods.get(method_name)) |sqlite_method| {
            if (sqlite_method.prefix.len > 0) {
                try self.emit(sqlite_method.prefix);
            }
            try parent.genExpr(self, obj);
            try self.emit(sqlite_method.suffix);

            if (sqlite_method.has_arg) {
                if (call.args.len > 0) {
                    try parent.genExpr(self, call.args[0]);
                }
                try self.emit(")");
            }
            return true;
        }
    }

    // Handle sqlite3.Connection methods
    if (obj_type == .sqlite_connection) {
        if (SqliteConnectionMethods.get(method_name)) |sqlite_method| {
            if (sqlite_method.prefix.len > 0) {
                try self.emit(sqlite_method.prefix);
            }
            try parent.genExpr(self, obj);
            try self.emit(sqlite_method.suffix);

            if (sqlite_method.has_arg) {
                if (call.args.len > 0) {
                    try parent.genExpr(self, call.args[0]);
                }
                try self.emit(")");
            }
            return true;
        }
    }

    return false;
}
