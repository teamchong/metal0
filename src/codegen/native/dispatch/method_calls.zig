/// Method call dispatchers (string, list, dict methods)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const zig_keywords = @import("utils.zig_keywords");

const methods = @import("../methods.zig");
const io_mod = @import("../io.zig");
const unittest_mod = @import("../unittest/mod.zig");

// Trait imports for type-aware dispatch
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const container_traits = @import("../../../analysis/traits/container_traits.zig");
const string_traits = @import("../../../analysis/traits/string_traits.zig");

/// Helper: emit @as(i64, @intFromBool(obj)) - fully structured with emitCallCtx
fn emitBoolToInt(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    try self.emitCallCtx("@as", obj, struct {
        pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
            try s.emit("i64, ");
            try s.emitCallCtx("@intFromBool", e, struct {
                pub fn g(s2: *NativeCodegen, e2: ast.Node) CodegenError!void {
                    try s2.genExpr(e2);
                }
            }.g);
        }
    }.f);
}

/// Helper: emit runtime.toBool(expr) with guaranteed bracket matching
fn emitToBool(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    try self.emitCallCtx("runtime.toBool", expr, struct {
        pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
            try s.genExpr(e);
        }
    }.f);
}

/// Builtin types that support __new__ with value extraction
const BuiltinNewTypes = std.StaticStringMap(void).initComptime(.{
    .{ "str", {} }, .{ "int", {} }, .{ "float", {} }, .{ "bool", {} },
});

/// Default values for builtin types in __new__ without args
const BuiltinTypeDefaults = std.StaticStringMap([]const u8).initComptime(.{
    .{ "bool", "false" }, .{ "int", "@as(i64, 0)" },
    .{ "float", "@as(f64, 0.0)" }, .{ "str", "\"\"" },
});

// Handler type for standard methods (obj, args)
const MethodHandler = *const fn (*NativeCodegen, ast.Node, []ast.Node) CodegenError!void;

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
    .{ "splitlines", methods.genSplitlines },
    // Note: 'format' is handled specially below (needs keyword args)
});

// String methods that are UNIQUE to strings (no collision with other types)
// Used for safe dispatch on unknown types - Zig type checking catches misuse
fn isUniqueStringMethod(name: []const u8) bool {
    const unique_methods = std.StaticStringMap(void).initComptime(.{
        // Unique string methods - no other Python type has these
        .{ "replace", {} },
        .{ "upper", {} },
        .{ "lower", {} },
        .{ "capitalize", {} },
        .{ "title", {} },
        .{ "swapcase", {} },
        .{ "strip", {} },
        .{ "lstrip", {} },
        .{ "rstrip", {} },
        .{ "split", {} },
        .{ "rsplit", {} },
        .{ "splitlines", {} },
        .{ "startswith", {} },
        .{ "endswith", {} },
        .{ "isdigit", {} },
        .{ "isalpha", {} },
        .{ "isalnum", {} },
        .{ "isspace", {} },
        .{ "islower", {} },
        .{ "isupper", {} },
        .{ "isascii", {} },
        .{ "istitle", {} },
        .{ "isprintable", {} },
        .{ "isdecimal", {} },
        .{ "isnumeric", {} },
        .{ "ljust", {} },
        .{ "rjust", {} },
        .{ "center", {} },
        .{ "zfill", {} },
        .{ "encode", {} },
        .{ "decode", {} },
        .{ "rfind", {} },
        .{ "rindex", {} },
        // Note: 'join' excluded - collides with thread.join()
        // Note: 'find' excluded - could be ambiguous
        // Note: 'count' excluded - used by list.count() too
        // Note: 'index' excluded - used by list.index() too
    });
    return unique_methods.has(name);
}

/// Generate PyValue string method call for uncertain types
/// Returns true if handled, false if should fall through
fn genPyValueStringMethod(self: *NativeCodegen, obj: ast.Node, method_name: []const u8, args: []ast.Node) CodegenError!bool {
    const parent = @import("../expressions.zig");
    const categories = @import("method_categories.zig");

    const kind = categories.getPyValueStringMethodKind(method_name) orelse return false;

    switch (kind) {
        .bool_result => {
            // startswith, endswith - emit: runtime.PyValue.from(obj).method(prefix)
            try self.emit("runtime.PyValue.from(");
            try parent.genExpr(self, obj);
            try self.emit(").");
            try self.emit(method_name);
            try self.emit("(");
            if (args.len > 0) {
                try parent.genExpr(self, args[0]);
            } else {
                try self.emit("\"\"");
            }
            try self.emit(")");
        },
        .slice_result => {
            // strip, lstrip, rstrip, upper, lower - emit: runtime.PyValue.from(obj).method()
            try self.emit("runtime.PyValue.from(");
            try parent.genExpr(self, obj);
            try self.emit(").");
            try self.emit(method_name);
            try self.emit("()");
        },
        .replace_result => {
            // replace(old, new) - emit: runtime.string_utils.replace(obj.asString(), old, new)
            try self.emit("(try runtime.string_utils.replace(__global_allocator, runtime.PyValue.from(");
            try parent.genExpr(self, obj);
            try self.emit(").asString(), ");
            if (args.len > 0) {
                try parent.genExpr(self, args[0]);
            } else {
                try self.emit("\"\"");
            }
            try self.emit(", ");
            if (args.len > 1) {
                try parent.genExpr(self, args[1]);
            } else {
                try self.emit("\"\"");
            }
            try self.emit("))");
        },
        .find_result => {
            // find - emit: runtime.PyValue.from(obj).find(substr)
            try self.emit("runtime.PyValue.from(");
            try parent.genExpr(self, obj);
            try self.emit(").find(");
            if (args.len > 0) {
                try parent.genExpr(self, args[0]);
            } else {
                try self.emit("\"\"");
            }
            try self.emit(")");
        },
        .list_result => {
            // split - needs allocator: (try runtime.PyValue.from(obj).split(alloc, sep)).items
            try self.emit("(try runtime.PyValue.from(");
            try parent.genExpr(self, obj);
            try self.emit(").split(__global_allocator, ");
            if (args.len > 0) {
                try parent.genExpr(self, args[0]);
            } else {
                try self.emit("\" \""); // Default: split on whitespace
            }
            try self.emit(")).items");
        },
    }
    return true;
}

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

// Defaultdict methods - special handling for IntDefaultDict
// copy() calls the native copy method, not the dict iteration pattern
const DefaultdictMethods = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "copy", genDefaultdictCopy },
    .{ "keys", methods.genKeys },
    .{ "values", methods.genValues },
    .{ "items", methods.genItems },
});

// Helper: defaultdict.copy() -> try d.copy()
fn genDefaultdictCopy(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("(try ");
    try self.genExpr(obj);
    try self.emit(".copy())");
}

// Dict methods - O(1) lookup via StaticStringMap
const DictMethods = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "keys", methods.genKeys },
    .{ "values", methods.genValues },
    .{ "items", methods.genItems },
    .{ "update", methods.genDictUpdate },
    .{ "clear", methods.genDictClear },
    .{ "copy", methods.genDictCopy },
    .{ "pop", methods.genDictPop },
    .{ "popitem", methods.genDictPopitem },
    .{ "setdefault", methods.genDictSetdefault },
});

// Set methods - O(1) lookup via StaticStringMap
const SetMethods = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "add", methods.genSetAdd },
    .{ "remove", methods.genSetRemove },
    .{ "discard", methods.genSetDiscard },
    .{ "clear", methods.genSetClear },
    .{ "pop", methods.genSetPop },
    .{ "copy", methods.genSetCopy },
    .{ "update", methods.genSetUpdate },
    .{ "union", methods.genSetUnion },
    .{ "intersection", methods.genSetIntersection },
    .{ "difference", methods.genSetDifference },
    .{ "symmetric_difference", methods.genSetSymmetricDifference },
    .{ "issubset", methods.genSetIssubset },
    .{ "issuperset", methods.genSetIssuperset },
    .{ "isdisjoint", methods.genSetIsdisjoint },
    .{ "intersection_update", methods.genSetIntersectionUpdate },
    .{ "difference_update", methods.genSetDifferenceUpdate },
    .{ "symmetric_difference_update", methods.genSetSymmetricDifferenceUpdate },
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
/// Two-Flow: Uncertain objects (PyValue typed) use their own method handlers with safety checks
pub fn tryDispatch(self: *NativeCodegen, call: ast.Node.Call) CodegenError!bool {
    if (call.func.* != .attribute) return false;

    const method_name = call.func.attribute.attr;
    const obj = call.func.attribute.value.*;

    // Two-Flow: Check if object variable is uncertain (PyValue or unknown confidence)
    // Individual method handlers now have Two-Flow checks built in, but we can
    // add a safety net here for PyValue method dispatch if needed
    if (obj == .name) {
        const var_name = obj.name.id;
        // Check if variable is explicitly PyValue typed
        if (self.type_inferrer.var_types.get(var_name)) |var_type| {
            if (var_type == .pyvalue) {
                // For PyValue objects, let the individual handlers deal with extraction
                // The handlers (genSplit, genStrip, genJoin, etc.) now check for .pyvalue
                // and extract .string, .list, etc. as needed
            }
        }
    }

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

            // Handle type.__new__(cls, name, bases, dict) for metaclass creation
            // Pattern: type.__new__(cls, name, bases, dict) -> runtime.typeNew(metaclass, name, bases, dict)
            if (std.mem.eql(u8, method_name, "__new__") and std.mem.eql(u8, parent_name, "type")) {
                if (call.args.len >= 4) {
                    // type.__new__(cls, name, bases, dict)
                    // cls is the metaclass, name is class name, bases is tuple, dict is namespace
                    try self.emit("(try runtime.typeNew(__global_allocator, ");
                    try self.genExpr(call.args[0]); // cls/metaclass
                    try self.emit(", ");
                    try self.genExpr(call.args[1]); // name
                    try self.emit(", ");
                    try self.genExpr(call.args[2]); // bases
                    try self.emit(", ");
                    try self.genExpr(call.args[3]); // dict
                    try self.emit("))");
                    return true;
                } else if (call.args.len == 1) {
                    // type.__new__(cls) - create empty type for metaclass
                    try self.emit("(try runtime.typeNew(__global_allocator, ");
                    try self.genExpr(call.args[0]); // cls
                    try self.emit(", \"\", &[_]*runtime.PyType{}, runtime.hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator)))");
                    return true;
                }
            }

            // For builtin types (str, int, float, bool), __new__ creates an instance with a value
            const is_builtin_new = std.mem.eql(u8, method_name, "__new__") and BuiltinNewTypes.has(parent_name);

            if (is_builtin_new) {
                if (call.args.len >= 2) {
                    // Return the value argument (second arg after cls)
                    // e.g., bool.__new__(bool, 1) -> true, bool.__new__(bool, 0) -> false
                    if (std.mem.eql(u8, parent_name, "bool")) {
                        try emitToBool(self, call.args[1]);
                    } else {
                        try self.genExpr(call.args[1]);
                    }
                    return true;
                } else {
                    // No value argument - return default for the type
                    try self.emit(BuiltinTypeDefaults.get(parent_name) orelse "{}");
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

    // Infer object type for type-aware dispatch
    const obj_type = self.type_inferrer.inferExpr(obj) catch .unknown;

    // If object is an imported module (stdlib or local), don't dispatch to method handlers
    // Let calls.zig handle module function calls properly
    if (obj == .name) {
        const var_name = obj.name.id;
        if (self.imported_modules.contains(var_name) or self.module_registry.hasModule(var_name)) {
            return false;
        }
    }

    // CDLL methods are NOT string/list/dict methods - skip all standard methods
    // ctypes FFI calls are handled separately in calls.zig
    if (obj_type == .cdll or obj_type == .c_func) {
        return false;
    }

    // Check if object comes from a C extension module (numpy, pandas, etc.)
    // These objects are PyObject* and method calls go through Python C API
    if (obj_type == .pyobject) {
        // Generate: c_interop.callMethod(obj, "method", .{args...})
        try genCExtensionMethodCall(self, obj, method_name, call.args);
        return true;
    }

    // Check if object is a variable assigned from a C extension module call
    if (obj == .name) {
        const var_name = obj.name.id;
        // Check if this var was assigned from a c_extension module
        if (self.getSymbolType(var_name)) |var_type| {
            if (var_type == .pyobject) {
                try genCExtensionMethodCall(self, obj, method_name, call.args);
                return true;
            }
        }
    }

    // Special handling for str.format() - needs keyword args
    if (std.mem.eql(u8, method_name, "format")) {
        try methods.genStrFormat(self, obj, call.args, call.keyword_args);
        return true;
    }

    // Try string methods - but only for string-typed objects
    // This prevents collisions with thread.join(), file.read(), etc.
    // Two-Flow: Skip string dispatch for PyValue/unknown to let them fall through to runtime
    if (StringMethods.get(method_name)) |handler| {
        // Only dispatch string methods for certain string-like types
        // Skip uncertain types (pyvalue/unknown) - they need runtime dispatch
        if (string_traits.isStringLike(obj_type) and
            obj_type != .pyvalue and
            !type_traits.isUnknown(obj_type))
        {
            handler(self, obj, call.args) catch |err| {
                if (err == error.UnsupportedSyntax) return false;
                return err;
            };
            return true;
        }
        // Two-Flow: For PyValue/unknown types, use PyValue string methods instead of eval fallback
        // Must check BEFORE unique string method dispatch since unknown types need PyValue methods
        if (obj_type == .pyvalue or type_traits.isUnknown(obj_type)) {
            if (try genPyValueStringMethod(self, obj, method_name, call.args)) {
                return true;
            }
        }
        // Fallback: For unknown types that aren't PyValue, dispatch unique string methods
        // These methods are unique to strings - no other Python type has them
        // Zig type checking will catch misuse at compile time
        if (type_traits.isUnknown(obj_type) and obj_type != .pyvalue and isUniqueStringMethod(method_name)) {
            handler(self, obj, call.args) catch |err| {
                if (err == error.UnsupportedSyntax) return false;
                return err;
            };
            return true;
        }
        // Not a string type or uncertain - fall through to other handlers
    }

    // Try defaultdict methods first - IntDefaultDict has native copy() method
    if (DefaultdictMethods.get(method_name)) |handler| {
        if (obj_type == .defaultdict) {
            handler(self, obj, call.args) catch |err| {
                if (err == error.UnsupportedSyntax) return false;
                return err;
            };
            return true;
        }
    }

    // Try dict methods BEFORE list - dict and list share some method names (pop, clear, copy)
    // We need type-aware dispatch to avoid list.pop() being called on dicts
    if (DictMethods.get(method_name)) |handler| {
        // Only dispatch dict methods for dict-like types
        if (container_traits.isDict(obj_type) or obj_type == .counter) {
            handler(self, obj, call.args) catch |err| {
                if (err == error.UnsupportedSyntax) return false;
                return err;
            };
            return true;
        }
    }

    // Try list methods - but NOT if we know it's a dict, set, or uncertain type
    // Two-Flow: Skip list dispatch for PyValue/unknown to let them fall through to runtime
    if (ListMethods.get(method_name)) |handler| {
        // Skip list dispatch for dict/set types to avoid list.pop() on dicts
        // Keep unknown types - they may be empty list literals like [] which need list methods
        if (!container_traits.isDict(obj_type) and !container_traits.isSet(obj_type) and
            obj_type != .counter and obj_type != .pyvalue)
        {
            handler(self, obj, call.args) catch |err| {
                if (err == error.UnsupportedSyntax) return false;
                return err;
            };
            return true;
        }
    }

    // Try dict methods for unknown/PyValue types (fallback for untyped dicts)
    // Two-Flow: Include .pyvalue for uncertain container method dispatch
    if (DictMethods.get(method_name)) |handler| {
        if ((type_traits.isUnknown(obj_type) or obj_type == .pyvalue) and !SetMethods.has(method_name)) {
            handler(self, obj, call.args) catch |err| {
                if (err == error.UnsupportedSyntax) return false;
                return err;
            };
            return true;
        }
    }

    // Try set methods (for set types)
    // Set method names are unique enough (update, discard, intersection_update, etc.)
    // that we can safely dispatch on unknown, pyvalue, and class_instance types too
    // Two-Flow: Include .pyvalue for uncertain container method dispatch
    if (SetMethods.get(method_name)) |handler| {
        if (container_traits.isSet(obj_type) or type_traits.isUnknown(obj_type) or
            obj_type == .pyvalue or type_traits.isClassInstance(obj_type))
        {
            handler(self, obj, call.args) catch |err| {
                if (err == error.UnsupportedSyntax) return false;
                return err;
            };
            return true;
        }
    }

    // Try float methods (is_integer, as_integer_ratio, hex, conjugate)
    // These methods exist on float objects but also on user-defined classes inheriting from numbers ABC.
    // Only dispatch to float handlers for known float/int types to avoid stealing method calls from class instances.
    if (FloatMethods.get(method_name)) |handler| {
        // Only dispatch for primitive float/int types, not class instances
        // Class instances (MyReal, MyComplex) have their own conjugate() methods
        if (type_traits.isFloating(obj_type) or type_traits.isIntegral(obj_type) or
            type_traits.isComplex(obj_type))
        {
            handler(self, obj, call.args) catch |err| {
                if (err == error.UnsupportedSyntax) return false;
                return err;
            };
            return true;
        }
        // For class instances or unknown types, don't dispatch - let genCall handle it
    }

    // Try primitive int methods (__index__, __int__, __hash__, etc.)
    // These methods are called on int literals (6).__index__() or int variables x.__index__()
    // Zig primitive types don't have methods, so we emit the equivalent expression directly
    if (type_traits.isIntegral(obj_type) or type_traits.isBoolean(obj_type) or
        type_traits.isUnknown(obj_type))
    {
        if (std.mem.eql(u8, method_name, "__index__")) {
            // int.__index__() returns self - just emit the value
            // For bool: True.__index__() -> 1, False.__index__() -> 0
            if (type_traits.isBoolean(obj_type)) {
                try emitBoolToInt(self, obj);
            } else {
                try self.genExpr(obj);
            }
            return true;
        }
        if (std.mem.eql(u8, method_name, "__int__")) {
            // int.__int__() returns self
            if (type_traits.isBoolean(obj_type)) {
                try emitBoolToInt(self, obj);
            } else {
                try self.genExpr(obj);
            }
            return true;
        }
        if (std.mem.eql(u8, method_name, "__hash__")) {
            // int.__hash__() returns self for integers
            try self.genExpr(obj);
            return true;
        }
    }

    // Try file/stream methods with type-aware dispatch
    if (FileMethods.has(method_name) or StreamMethods.has(method_name)) {
        // Use already-inferred object type
        if (obj_type == .stringio or obj_type == .bytesio) {
            // StringIO/BytesIO stream methods
            if (try handleStreamMethod(self, method_name, obj, call.args)) {
                return true;
            }
        } else if (obj_type == .file or type_traits.isUnknown(obj_type)) {
            // File methods (PyFile) - only for actual file objects or unknown types
            // Skip if it's a known non-file type like sqlite_connection
            if (FileMethods.get(method_name)) |handler| {
                handler(self, obj, call.args) catch |err| {
                    if (err == error.UnsupportedSyntax) return false;
                    return err;
                };
                return true;
            }
        }
    }

    // HashObject methods (hashlib hash objects)
    if (HashMethods.has(method_name)) {
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

    // unittest assertion methods (self.assertEqual, etc.)
    // Check if obj is 'self' - unittest methods called on self
    // Also check for renamed self (e.g., test_self -> self via var_renames)
    // Also check if obj is the current method's first param (Python allows any name for self)
    const is_self_obj = if (obj == .name) blk: {
        const obj_name = obj.name.id;
        // Direct check for "self"
        if (std.mem.eql(u8, obj_name, "self")) break :blk true;
        // Check if obj_name is renamed to "self" or "__self"
        if (self.var_renames.get(obj_name)) |renamed| {
            if (std.mem.eql(u8, renamed, "self") or std.mem.eql(u8, renamed, "__self")) {
                break :blk true;
            }
        }
        // Check if obj_name is the current method's first param (e.g., "test_self")
        // Python allows any name for the first param of a method
        if (self.current_method_first_param) |first_param| {
            if (std.mem.eql(u8, obj_name, first_param)) {
                break :blk true;
            }
        }
        break :blk false;
    } else false;

    if (is_self_obj) {
        // Only apply unittest method dispatch if we're inside a unittest TestCase subclass
        // This prevents treating any self.addCleanup() call as a unittest no-op
        const is_unittest_class = if (self.current_class_name) |class_name|
            self.isTestCaseSubclass(class_name)
        else
            false;

        if (is_unittest_class) {
            // Special handling for subTest which needs keyword arguments
            if (std.mem.eql(u8, method_name, "subTest")) {
                try unittest_mod.genSubTest(self, obj, call.args, call.keyword_args);
                return true;
            }
            if (UnittestMethods.get(method_name)) |handler| {
                handler(self, obj, call.args) catch |err| {
                    if (err == error.UnsupportedSyntax) return false;
                    return err;
                };
                return true;
            }
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
                        break :blk container_traits.isList(var_type);
                    }
                }
                // Infer from type_inferrer
                const obj_type_inferred = self.type_inferrer.inferExpr(obj) catch .unknown;
                break :blk container_traits.isList(obj_type_inferred);
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
                        break :blk container_traits.isList(var_type);
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
            // get - only dict.get(key) with args, NOT module.get()
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

/// Generate method call on C extension module object (PyObject*)
/// Example: arr.sum() -> runtime.PyValue.from(c_interop.callMethod(arr.toPtr(), "sum", .{}) orelse @panic("..."))
fn genCExtensionMethodCall(self: *NativeCodegen, obj: ast.Node, method_name: []const u8, args: []ast.Node) CodegenError!void {
    const expressions = @import("../expressions.zig");

    // Use runtime.PyValue.from() for proper type conversion from *PyObject to PyValue
    // The obj might be a PyValue, so use toPtr() to get the underlying *anyopaque
    // Use orelse @panic instead of .? for safer null handling with clear error message
    // NOTE: toPtr() returns ?*anyopaque, must unwrap before alignment cast
    try self.emit("runtime.PyValue.from((c_interop.callMethod(@ptrCast(@alignCast(");
    try expressions.genExpr(self, obj);
    try self.emit(".toPtr() orelse @panic(\"Object has no pointer representation\"))), \"");
    try self.emit(method_name);
    try self.emit("\", .{");

    // Generate arguments as tuple
    for (args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try expressions.genExpr(self, arg);
    }

    try self.emitFmt("}}) orelse @panic(\"C extension method call '{s}()' returned null\")))", .{method_name});
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

    const parent = @import("../expressions.zig");

    // Check if this is a metaclass (inherits from type)
    const is_metaclass = self.isClassMetaclass(current_class);

    // Handle super().__new__() in metaclass context
    // Pattern: super().__new__(cls, name, bases, dict) -> runtime.typeNew(cls, name, bases, dict)
    if (is_metaclass and std.mem.eql(u8, method_name, "__new__")) {
        if (call.args.len >= 4) {
            // super().__new__(cls, name, bases, dict)
            try self.emit("(try runtime.typeNew(__global_allocator, ");
            try parent.genExpr(self, call.args[0]); // cls
            try self.emit(", ");
            try parent.genExpr(self, call.args[1]); // name
            try self.emit(", ");
            try parent.genExpr(self, call.args[2]); // bases
            try self.emit(", ");
            try parent.genExpr(self, call.args[3]); // dict
            try self.emit("))");
            return true;
        } else if (call.args.len == 1) {
            // super().__new__(cls) - create empty type
            try self.emit("(try runtime.typeNew(__global_allocator, ");
            try parent.genExpr(self, call.args[0]); // cls
            try self.emit(", \"\", &[_]*runtime.PyType{}, runtime.hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator)))");
            return true;
        }
    }

    const parent_class = self.getParentClassName(current_class) orelse {
        // No parent class found (e.g., inheriting from external module like unittest.TestCase)
        // For metaclasses, return empty PyValue
        if (is_metaclass) {
            try self.emit("runtime.PyValue{ .none = {} }");
            return true;
        }
        // Generate a no-op {} since we can't call the actual parent method
        // This is safe because test methods in unittest typically don't need parent return values
        try self.emit("{}");
        return true;
    };

    // Generate: ParentClass.method(@ptrCast(@constCast(self)), args)
    // Need @constCast because self is *const Child, and parent method may expect mutable pointer
    // Need @ptrCast because self is *Child but parent method expects *Parent
    // Escape method name if it's a Zig keyword (e.g., "test" -> @"test")
    // Use var_renames to handle cases where self is renamed (e.g., __self in init)
    const self_var = self.var_renames.get("self") orelse "self";
    try self.emit(parent_class);
    try self.emit(".");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method_name);
    try self.emit("(@ptrCast(@constCast(");
    try self.emit(self_var);
    try self.emit("))");

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
    const fnv = @import("utils.fnv_hash");
    const WRITE = comptime fnv.hash("write");
    const READ = comptime fnv.hash("read");
    const READLINE = comptime fnv.hash("readline");
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
        if (args.len > 0) {
            try self.emit(".readSize(");
            try parent.genExpr(self, args[0]);
            try self.emit(")");
        } else {
            try self.emit(".read()");
        }
    } else if (method_hash == READLINE) {
        try self.emit(receiver);
        if (args.len > 0) {
            try self.emit(".readlineSize(");
            try parent.genExpr(self, args[0]);
            try self.emit(")");
        } else {
            try self.emit(".readline()");
        }
    } else if (method_hash == GETVALUE) {
        try self.emit(receiver);
        try self.emit(".getvalue()");
    } else if (method_hash == SEEK) {
        try self.emit(receiver);
        if (args.len > 1) {
            try self.emit(".seekWhence(");
            try parent.genExpr(self, args[0]);
            try self.emit(", ");
            try parent.genExpr(self, args[1]);
            try self.emit(")");
        } else {
            try self.emit(".seek(");
            if (args.len > 0) try parent.genExpr(self, args[0]) else try self.emit("0");
            try self.emit(")");
        }
    } else if (method_hash == TELL) {
        try self.emit(receiver);
        try self.emit(".tell()");
    } else if (method_hash == TRUNCATE) {
        try self.emit(receiver);
        if (args.len > 0) {
            try self.emit(".truncateSize(");
            try parent.genExpr(self, args[0]);
            try self.emit(")");
        } else {
            try self.emit(".truncate()");
        }
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

    const fnv = @import("utils.fnv_hash");
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
        const alloc_name = "__global_allocator";
        try self.emit("try ");
        try self.emit(receiver);
        try self.emitFmt(".digest({s})", .{alloc_name});
    } else if (method_hash == HEXDIGEST) {
        // h.hexdigest(allocator) - returns hex string
        // Use scope-aware allocator: __global_allocator in functions, allocator in main()
        const alloc_name = "__global_allocator";
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
