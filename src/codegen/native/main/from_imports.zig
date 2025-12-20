const std = @import("std");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const CodegenError = core.CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const import_resolver = @import("../../../import_resolver.zig");
const zig_keywords = @import("utils.zig_keywords");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}



/// Check if operator function name is known
fn isKnownOperatorFunc(name: []const u8) bool {
    const known = std.StaticStringMap(void).initComptime(.{
        .{ "eq", {} },
        .{ "ne", {} },
        .{ "lt", {} },
        .{ "le", {} },
        .{ "gt", {} },
        .{ "ge", {} },
        .{ "add", {} },
        .{ "sub", {} },
        .{ "mul", {} },
        .{ "truediv", {} },
        .{ "floordiv", {} },
        .{ "mod", {} },
        .{ "pow", {} },
        .{ "neg", {} },
        .{ "pos", {} },
        .{ "abs", {} },
        .{ "invert", {} },
        .{ "lshift", {} },
        .{ "rshift", {} },
        .{ "and_", {} },
        .{ "or_", {} },
        .{ "xor", {} },
        .{ "not_", {} },
        .{ "truth", {} },
        .{ "concat", {} },
        .{ "contains", {} },
        .{ "getitem", {} },
        .{ "setitem", {} },
        .{ "delitem", {} },
        .{ "is_", {} },
        .{ "is_not", {} },
    });
    return known.has(name);
}

/// Operator wrappers route to Lib.operator functions for proper Python comparison semantics.
/// These functions implement the full rich comparison protocol with NotImplemented handling.
const OperatorWrappers = std.StaticStringMap([]const u8).initComptime(.{
    .{ "eq", "(a: anytype, b: anytype) bool { return runtime.Lib.operator.eq(a, b); }\n" },
    .{ "ne", "(a: anytype, b: anytype) bool { return runtime.Lib.operator.ne(a, b); }\n" },
    .{ "lt", "(a: anytype, b: anytype) bool { return runtime.Lib.operator.lt(a, b); }\n" },
    .{ "le", "(a: anytype, b: anytype) bool { return runtime.Lib.operator.le(a, b); }\n" },
    .{ "gt", "(a: anytype, b: anytype) bool { return runtime.Lib.operator.gt(a, b); }\n" },
    .{ "ge", "(a: anytype, b: anytype) bool { return runtime.Lib.operator.ge(a, b); }\n" },
    .{ "add", "(a: anytype, b: anytype) runtime.PyValue { return runtime.PyValue.from(a).add(runtime.PyValue.from(b)); }\n" },
    .{ "sub", "(a: anytype, b: anytype) runtime.PyValue { return runtime.PyValue.from(a).sub(runtime.PyValue.from(b)); }\n" },
    .{ "mul", "(a: anytype, b: anytype) runtime.PyValue { return runtime.PyValue.from(a).mul(runtime.PyValue.from(b)); }\n" },
    .{ "truediv", "(a: anytype, b: anytype) runtime.PyValue { return runtime.PyValue.from(a).div(runtime.PyValue.from(b)); }\n" },
    .{ "floordiv", "(a: anytype, b: anytype) runtime.PyValue { return runtime.PyValue.from(a).floordiv(runtime.PyValue.from(b)); }\n" },
    .{ "mod", "(a: anytype, b: anytype) runtime.PyValue { return runtime.PyValue.from(a).mod(runtime.PyValue.from(b)); }\n" },
    .{ "neg", "(a: anytype) runtime.PyValue { return runtime.PyValue.from(a).neg(); }\n" },
    .{ "not_", "(a: anytype) bool { return !runtime.toBool(a); }\n" },
    .{ "truth", "(a: anytype) bool { return runtime.toBool(a); }\n" },
});

/// Generate wrapper function for operator module function
fn generateOperatorWrapper(self: *NativeCodegen, name: []const u8, symbol_name: []const u8) !void {
    try emitConst(self, "fn ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
    try emitConst(self, OperatorWrappers.get(name) orelse "(a: anytype, b: anytype) @TypeOf(a) { _ = b; return a; }\n");
}

/// Generate from-import symbol re-exports with deduplication
/// For "from json import loads", generates: const loads = json.loads;
pub fn generateFromImports(self: *NativeCodegen) !void {
    // Track generated symbols to avoid duplicates
    var generated_symbols = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer generated_symbols.deinit();

    // Track const declarations that need discards (not function definitions)
    var const_symbols = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer const_symbols.deinit();

    for (self.from_imports.items) |from_imp| {
        // Skip relative imports (starting with .) - these are internal package imports
        // that don't make sense in standalone compiled modules
        if (from_imp.module.len > 0 and from_imp.module[0] == '.') {
            continue;
        }

        // Skip builtin modules UNLESS they have a Zig implementation in the import registry
        // This allows from-import symbols to be generated for modules like weakref that have runtime.Lib implementations
        if (import_resolver.isBuiltinModule(from_imp.module)) {
            if (self.import_registry.lookup(from_imp.module)) |info| {
                // Module has a Zig implementation - continue to generate from-import symbols
                if (info.zig_import != null or info.direct_import != null) {
                    // Fall through to generate symbols
                } else {
                    continue;
                }
            } else {
                continue;
            }
        }

        // Handle operator module specially - generate wrapper functions
        if (std.mem.eql(u8, from_imp.module, "operator")) {
            for (from_imp.names, 0..) |name, i| {
                // Skip import * for now
                if (std.mem.eql(u8, name, "*")) continue;

                const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                    from_imp.asnames[i].?
                else
                    name;

                // Skip if already generated
                if (generated_symbols.contains(symbol_name)) continue;

                // Generate wrapper function for known operator functions
                if (isKnownOperatorFunc(name)) {
                    try generateOperatorWrapper(self, name, symbol_name);
                    try generated_symbols.put(symbol_name, {});
                } else {
                    // Unknown operator function - register for inline dispatch
                    try self.local_from_imports.put(symbol_name, from_imp.module);
                }
            }
            continue;
        }

        // Handle copy module specially - route to runtime.copy_ops
        // Python: from copy import copy, deepcopy
        // Zig: These are handled via dispatch (copy_mod.zig), not as direct imports
        if (std.mem.eql(u8, from_imp.module, "copy")) {
            for (from_imp.names, 0..) |name, i| {
                if (std.mem.eql(u8, name, "*")) continue;

                const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                    from_imp.asnames[i].?
                else
                    name;

                // Skip if already generated
                if (generated_symbols.contains(symbol_name)) continue;

                // Register for inline dispatch routing (copy.copy() and copy.deepcopy() calls
                // are handled by copy_mod.zig dispatch, so we just register for local_from_imports)
                try self.local_from_imports.put(symbol_name, "copy");
                try generated_symbols.put(symbol_name, {});
            }
            continue;
        }

        // Handle metal0 native libraries (from metal0 import tokenizer)
        if (std.mem.eql(u8, from_imp.module, "metal0")) {
            for (from_imp.names, 0..) |name, i| {
                if (std.mem.eql(u8, name, "*")) continue;

                const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                    from_imp.asnames[i].?
                else
                    name;

                // Skip if already generated
                if (generated_symbols.contains(symbol_name)) continue;

                // Register for dispatch routing (tokenizer.encode -> metal0.tokenizer.encode)
                try self.local_from_imports.put(symbol_name, "metal0.tokenizer");
                try generated_symbols.put(symbol_name, {});
            }
            continue;
        }

        // Handle _testbuffer module specially - expand all constants for "from _testbuffer import *"
        if (std.mem.eql(u8, from_imp.module, "_testbuffer")) {
            for (from_imp.names, 0..) |name, i| {
                // Handle "import *" - expand all _testbuffer constants
                if (std.mem.eql(u8, name, "*")) {
                    // Expand all _testbuffer constants and classes
                    const testbuffer_exports = [_]struct { name: []const u8, value: []const u8 }{
                        // PyBUF_* constants
                        .{ .name = "PyBUF_SIMPLE", .value = "@as(i64, 0)" },
                        .{ .name = "PyBUF_WRITABLE", .value = "@as(i64, 0x0001)" },
                        .{ .name = "PyBUF_WRITE", .value = "@as(i64, 0x0001)" },
                        .{ .name = "PyBUF_READ", .value = "@as(i64, 0x100)" },
                        .{ .name = "PyBUF_FORMAT", .value = "@as(i64, 0x0004)" },
                        .{ .name = "PyBUF_ND", .value = "@as(i64, 0x0008)" },
                        .{ .name = "PyBUF_STRIDES", .value = "@as(i64, 0x0018)" },
                        .{ .name = "PyBUF_C_CONTIGUOUS", .value = "@as(i64, 0x0038)" },
                        .{ .name = "PyBUF_F_CONTIGUOUS", .value = "@as(i64, 0x0058)" },
                        .{ .name = "PyBUF_ANY_CONTIGUOUS", .value = "@as(i64, 0x0098)" },
                        .{ .name = "PyBUF_INDIRECT", .value = "@as(i64, 0x0118)" },
                        .{ .name = "PyBUF_CONTIG", .value = "@as(i64, 0x0009)" },
                        .{ .name = "PyBUF_CONTIG_RO", .value = "@as(i64, 0x0008)" },
                        .{ .name = "PyBUF_STRIDED", .value = "@as(i64, 0x0019)" },
                        .{ .name = "PyBUF_STRIDED_RO", .value = "@as(i64, 0x0018)" },
                        .{ .name = "PyBUF_RECORDS", .value = "@as(i64, 0x001d)" },
                        .{ .name = "PyBUF_RECORDS_RO", .value = "@as(i64, 0x001c)" },
                        .{ .name = "PyBUF_FULL", .value = "@as(i64, 0x011d)" },
                        .{ .name = "PyBUF_FULL_RO", .value = "@as(i64, 0x011c)" },
                        // ND_* constants
                        .{ .name = "ND_MAX_NDIM", .value = "@as(i64, 64)" },
                        .{ .name = "ND_WRITABLE", .value = "@as(i64, 0x001)" },
                        .{ .name = "ND_FORTRAN", .value = "@as(i64, 0x002)" },
                        .{ .name = "ND_PIL", .value = "@as(i64, 0x004)" },
                        .{ .name = "ND_REDIRECT", .value = "@as(i64, 0x008)" },
                        .{ .name = "ND_GETBUF_FAIL", .value = "@as(i64, 0x010)" },
                        .{ .name = "ND_GETBUF_UNDEFINED", .value = "@as(i64, 0x020)" },
                        .{ .name = "ND_VAREXPORT", .value = "@as(i64, 0x040)" },
                        // Classes
                        .{ .name = "ndarray", .value = "runtime.TestBuffer.ndarray" },
                        .{ .name = "staticarray", .value = "runtime.TestBuffer.staticarray" },
                        // Functions
                        .{ .name = "get_sizeof_void_p", .value = "@as(i64, @sizeOf(*anyopaque))" },
                        .{ .name = "slice_indices", .value = "runtime.TestBuffer.slice_indices" },
                        .{ .name = "get_pointer", .value = "runtime.TestBuffer.get_pointer" },
                        .{ .name = "get_contiguous", .value = "runtime.TestBuffer.get_contiguous" },
                        .{ .name = "py_buffer_to_contiguous", .value = "runtime.TestBuffer.py_buffer_to_contiguous" },
                        .{ .name = "cmp_contig", .value = "runtime.TestBuffer.cmp_contig" },
                        .{ .name = "is_contiguous", .value = "runtime.TestBuffer.is_contiguous" },
                        // Optional imports that may not be available (set to null)
                        .{ .name = "numpy_array", .value = "@as(?*anyopaque, null)" },
                    };
                    for (testbuffer_exports) |exp| {
                        if (generated_symbols.contains(exp.name)) continue;
                        try emitConst(self, "const ");
                        try emitConst(self, exp.name);
                        try emitConst(self, " = ");
                        try emitConst(self, exp.value);
                        try emitConst(self, ";\n");
                        try generated_symbols.put(exp.name, {});
                        // Register in module_level_funcs to prevent shadowing in try-except
                        try self.module_level_funcs.put(exp.name, {});
                    }
                    continue;
                }

                const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                    from_imp.asnames[i].?
                else
                    name;

                if (generated_symbols.contains(symbol_name)) continue;

                // Register for dispatch routing
                try self.local_from_imports.put(symbol_name, from_imp.module);
            }
            continue;
        }

        // Handle _testcapi module specially - generate wrapper functions
        if (std.mem.eql(u8, from_imp.module, "_testcapi")) {
            for (from_imp.names, 0..) |name, i| {
                if (std.mem.eql(u8, name, "*")) continue;

                const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                    from_imp.asnames[i].?
                else
                    name;

                if (generated_symbols.contains(symbol_name)) continue;

                // Generate get_feature_macros function - returns comptime struct for dead code elimination
                if (std.mem.eql(u8, name, "get_feature_macros")) {
                    try emitConst(self, "fn ");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
                    try emitConst(self, "() runtime.FeatureMacros {\n");
                    try emitConst(self, "    return runtime.FeatureMacros{};\n");
                    try emitConst(self, "}\n");
                    try generated_symbols.put(symbol_name, {});
                } else {
                    // Other _testcapi functions - register for dispatch
                    try self.local_from_imports.put(symbol_name, from_imp.module);
                }
            }
            continue;
        }

        // Handle stringprep module - expand "from stringprep import *"
        if (std.mem.eql(u8, from_imp.module, "stringprep")) {
            for (from_imp.names) |name| {
                if (std.mem.eql(u8, name, "*")) {
                    // Expand all stringprep table functions
                    const stringprep_exports = [_][]const u8{
                        "in_table_a1",
                        "in_table_b1",
                        "map_table_b2",
                        "map_table_b3",
                        "in_table_c11",
                        "in_table_c12",
                        "in_table_c11_c12",
                        "in_table_c21",
                        "in_table_c22",
                        "in_table_c21_c22",
                        "in_table_c3",
                        "in_table_c4",
                        "in_table_c5",
                        "in_table_c6",
                        "in_table_c7",
                        "in_table_c8",
                        "in_table_c9",
                        "in_table_d1",
                        "in_table_d2",
                    };
                    for (stringprep_exports) |exp_name| {
                        if (generated_symbols.contains(exp_name)) continue;
                        try emitConst(self, "const ");
                        try emitConst(self, exp_name);
                        try emitConst(self, " = stringprep.");
                        try emitConst(self, exp_name);
                        try emitConst(self, ";\n");
                        try generated_symbols.put(exp_name, {});
                    }
                }
            }
            continue;
        }

        // Handle contextlib module - expand imports (both * and named)
        if (std.mem.eql(u8, from_imp.module, "contextlib")) {
            const contextlib_exports = [_][]const u8{
                "contextmanager",
                "closing",
                "nullcontext",
                "suppress",
                "redirect_stdout",
                "redirect_stderr",
                "ExitStack",
                "AsyncExitStack",
                "aclosing",
                "asynccontextmanager",
                "AbstractContextManager",
                "AbstractAsyncContextManager",
                "chdir",
            };
            for (from_imp.names, 0..) |name, i| {
                if (std.mem.eql(u8, name, "*")) {
                    // Expand all contextlib exports for star import
                    for (contextlib_exports) |exp_name| {
                        if (generated_symbols.contains(exp_name)) continue;
                        try emitConst(self, "const ");
                        try emitConst(self, exp_name);
                        try emitConst(self, " = contextlib.");
                        try emitConst(self, exp_name);
                        try emitConst(self, ";\n");
                        try generated_symbols.put(exp_name, {});
                    }
                } else {
                    // Named import - generate const for this specific name
                    const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                        from_imp.asnames[i].?
                    else
                        name;
                    if (generated_symbols.contains(symbol_name)) continue;
                    // Check if name is a known contextlib export
                    var is_known = false;
                    for (contextlib_exports) |exp_name| {
                        if (std.mem.eql(u8, name, exp_name)) {
                            is_known = true;
                            break;
                        }
                    }
                    if (is_known) {
                        try emitConst(self, "const ");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
                        try emitConst(self, " = contextlib.");
                        try emitConst(self, name);
                        try emitConst(self, ";\n");
                        try generated_symbols.put(symbol_name, {});
                    }
                }
            }
            continue;
        }

        // Handle itertools module - expand imports (both * and named)
        if (std.mem.eql(u8, from_imp.module, "itertools")) {
            const itertools_exports = [_][]const u8{
                "count",
                "cycle",
                "repeat",
                "accumulate",
                "chain",
                "compress",
                "dropwhile",
                "filterfalse",
                "groupby",
                "islice",
                "pairwise",
                "starmap",
                "takewhile",
                "tee",
                "zip_longest",
                "product",
                "permutations",
                "combinations",
                "combinations_with_replacement",
            };
            for (from_imp.names, 0..) |name, i| {
                if (std.mem.eql(u8, name, "*")) {
                    // Expand all itertools exports for star import
                    for (itertools_exports) |exp_name| {
                        if (generated_symbols.contains(exp_name)) continue;
                        try emitConst(self, "const ");
                        try emitConst(self, exp_name);
                        try emitConst(self, " = itertools.");
                        try emitConst(self, exp_name);
                        try emitConst(self, ";\n");
                        try generated_symbols.put(exp_name, {});
                    }
                } else {
                    // Named import
                    const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                        from_imp.asnames[i].?
                    else
                        name;
                    if (generated_symbols.contains(symbol_name)) continue;
                    var is_known = false;
                    for (itertools_exports) |exp_name| {
                        if (std.mem.eql(u8, name, exp_name)) {
                            is_known = true;
                            break;
                        }
                    }
                    if (is_known) {
                        try emitConst(self, "const ");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
                        try emitConst(self, " = itertools.");
                        try emitConst(self, name);
                        try emitConst(self, ";\n");
                        try generated_symbols.put(symbol_name, {});
                    }
                }
            }
            continue;
        }

        // Handle sys module - expand "from sys import *"
        if (std.mem.eql(u8, from_imp.module, "sys")) {
            for (from_imp.names) |name| {
                if (std.mem.eql(u8, name, "*")) {
                    // Expand common sys module exports
                    const sys_exports = [_][]const u8{
                        "platform",
                        "version_info",
                        "version",
                        "implementation",
                        "byteorder",
                        "maxsize",
                        "float_info",
                        "int_info",
                        "hash_info",
                        "exit",
                        "getrecursionlimit",
                        "setrecursionlimit",
                        "get_int_max_str_digits",
                        "set_int_max_str_digits",
                        "stdin",
                        "stdout",
                        "stderr",
                        "getrefcount",
                        "getsizeof",
                        "executable",
                    };
                    for (sys_exports) |exp_name| {
                        if (generated_symbols.contains(exp_name)) continue;
                        try emitConst(self, "const ");
                        try emitConst(self, exp_name);
                        try emitConst(self, " = sys.");
                        try emitConst(self, exp_name);
                        try emitConst(self, ";\n");
                        try generated_symbols.put(exp_name, {});
                    }
                }
            }
            continue;
        }

        // Handle subprocess module - expand "from subprocess import *"
        if (std.mem.eql(u8, from_imp.module, "subprocess")) {
            for (from_imp.names) |name| {
                if (std.mem.eql(u8, name, "*")) {
                    const subprocess_exports = [_][]const u8{
                        "PIPE",
                        "STDOUT",
                        "DEVNULL",
                        "CompletedProcess",
                        "Popen",
                        "run",
                        "call",
                        "check_call",
                        "check_output",
                        "getoutput",
                        "getstatusoutput",
                    };
                    for (subprocess_exports) |exp_name| {
                        if (generated_symbols.contains(exp_name)) continue;
                        try emitConst(self, "const ");
                        try emitConst(self, exp_name);
                        try emitConst(self, " = subprocess.");
                        try emitConst(self, exp_name);
                        try emitConst(self, ";\n");
                        try generated_symbols.put(exp_name, {});
                    }
                }
            }
            continue;
        }

        // Handle collections.abc module - expand "from collections.abc import *"
        if (std.mem.eql(u8, from_imp.module, "collections.abc")) {
            for (from_imp.names) |name| {
                if (std.mem.eql(u8, name, "*")) {
                    const abc_exports = [_][]const u8{
                        "Hashable",
                        "Awaitable",
                        "Coroutine",
                        "AsyncIterable",
                        "AsyncIterator",
                        "AsyncGenerator",
                        "Iterable",
                        "Iterator",
                        "Reversible",
                        "Generator",
                        "Container",
                        "Sized",
                        "Callable",
                        "Collection",
                        "Sequence",
                        "MutableSequence",
                        "ByteString",
                        "Set",
                        "MutableSet",
                        "Mapping",
                        "MutableMapping",
                        "MappingView",
                        "KeysView",
                        "ValuesView",
                        "ItemsView",
                    };
                    for (abc_exports) |exp_name| {
                        if (generated_symbols.contains(exp_name)) continue;
                        try emitConst(self, "const ");
                        try emitConst(self, exp_name);
                        try emitConst(self, " = collections.abc.");
                        try emitConst(self, exp_name);
                        try emitConst(self, ";\n");
                        try generated_symbols.put(exp_name, {});
                    }
                }
            }
            continue;
        }

        // Handle inline-only modules (no zig_import, functions are generated inline)
        // These modules don't have a struct to reference - their functions are
        // directly generated at call sites via dispatch (e.g., from decimal import Decimal)
        if (self.import_registry.lookup(from_imp.module)) |info| {
            if (info.zig_import == null) {
                // Module is inline-only - register symbols for dispatch routing
                // This allows calls like Decimal(...) to be routed to decimal.Decimal dispatch
                for (from_imp.names, 0..) |name, i| {
                    // Skip import * for now
                    if (std.mem.eql(u8, name, "*")) continue;

                    const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                        from_imp.asnames[i].?
                    else
                        name;

                    try self.local_from_imports.put(symbol_name, from_imp.module);
                }
                continue;
            }
        } else {
            // Check if this is a stub module - generate empty array placeholders
            // These are safer than null because they can be iterated over without errors
            const module_aliases = @import("../module_aliases.zig");
            if (module_aliases.isStubModule(from_imp.module)) {
                for (from_imp.names, 0..) |name, i| {
                    if (std.mem.eql(u8, name, "*")) continue;
                    const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                        from_imp.asnames[i].?
                    else
                        name;
                    if (generated_symbols.contains(symbol_name)) continue;
                    // Generate: const symbol_name = &[_][]const u8{}; for stub module imports
                    // Empty array is safer than null - can be iterated without type errors
                    try emitConst(self, "const ");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
                    try emitConst(self, ": []const []const u8 = &[_][]const u8{};\n");
                    try generated_symbols.put(symbol_name, {});
                }
                continue;
            }

            // Module not in registry - generate null placeholders for optional imports
            // This handles try/except ImportError patterns like: from numpy import ndarray as numpy_array
            for (from_imp.names, 0..) |name, i| {
                if (std.mem.eql(u8, name, "*")) continue;
                const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                    from_imp.asnames[i].?
                else
                    name;
                if (generated_symbols.contains(symbol_name)) continue;
                // Generate: const symbol_name = null; for unavailable modules
                try emitConst(self, "const ");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
                try emitConst(self, ": ?*anyopaque = null;\n");
                try generated_symbols.put(symbol_name, {});
            }
            continue;
        }

        // Check if this is a Tier 1 runtime module (functions need allocator)
        const is_runtime_module = self.import_registry.lookup(from_imp.module) != null and
            (std.mem.eql(u8, from_imp.module, "json") or
            std.mem.eql(u8, from_imp.module, "pickle") or
            std.mem.eql(u8, from_imp.module, "http") or
            std.mem.eql(u8, from_imp.module, "asyncio"));

        for (from_imp.names, 0..) |name, i| {
            // Get the symbol name (use alias if provided)
            const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                from_imp.asnames[i].?
            else
                name;

            // Skip import * for now (complex to implement)
            if (std.mem.eql(u8, name, "*")) {
                continue;
            }

            // Skip if this symbol was already generated
            if (generated_symbols.contains(symbol_name)) {
                continue;
            }

            // Track if this symbol needs allocator (runtime module functions)
            if (is_runtime_module) {
                try self.from_import_needs_allocator.put(symbol_name, {});

                // For json.loads, generate a wrapper function that accepts string literals
                if (std.mem.eql(u8, from_imp.module, "json") and std.mem.eql(u8, name, "loads")) {
                    try emitConst(self, "fn ");
                    try emitConst(self, symbol_name);
                    try emitConst(self, "(json_str: []const u8, allocator: std.mem.Allocator) !*runtime.PyObject {\n");
                    try emitConst(self, "    const json_str_obj = try runtime.PyString.create(__global_allocator, json_str);\n");
                    try emitConst(self, "    defer runtime.decref(json_str_obj, allocator);\n");
                    try emitConst(self, "    return try runtime.json.loads(json_str_obj, allocator);\n");
                    try emitConst(self, "}\n");
                    try generated_symbols.put(symbol_name, {});
                    continue; // Skip const generation for this one
                }

                // For pickle.loads, generate a wrapper function that accepts bytes and allocator
                if (std.mem.eql(u8, from_imp.module, "pickle") and std.mem.eql(u8, name, "loads")) {
                    try emitConst(self, "fn ");
                    try emitConst(self, symbol_name);
                    try emitConst(self, "(data: []const u8, allocator: std.mem.Allocator) !*runtime.PyObject {\n");
                    try emitConst(self, "    return try runtime.pickle.loads(data, allocator);\n");
                    try emitConst(self, "}\n");
                    try generated_symbols.put(symbol_name, {});
                    continue; // Skip const generation for this one
                }

                // For pickle.dumps, generate a wrapper function
                if (std.mem.eql(u8, from_imp.module, "pickle") and std.mem.eql(u8, name, "dumps")) {
                    try emitConst(self, "fn ");
                    try emitConst(self, symbol_name);
                    try emitConst(self, "(obj: anytype, protocol: anytype) []const u8 {\n");
                    try emitConst(self, "    _ = protocol; // Protocol not used in simplified implementation\n");
                    try emitConst(self, "    return runtime.json.dumpsValue(obj, __global_allocator) catch \"\";\n");
                    try emitConst(self, "}\n");
                    try generated_symbols.put(symbol_name, {});
                    continue; // Skip const generation for this one
                }
            }

            // Generate: const symbol_name = module.name;
            // Special case: if symbol_name == module name (e.g., "from copy import copy"),
            // skip generating this declaration entirely since PHASE 3.7 emits "const copy = std;"
            // and copy.copy is what we want. The from-import symbol becomes identical to the module.
            const same_as_module = std.mem.eql(u8, symbol_name, from_imp.module);

            if (same_as_module) {
                // Skip const declaration - module already declared with same name.
                // But still register for dispatch routing so calls like datetime(...)
                // get routed to the datetime module's datetime constructor.
                try self.local_from_imports.put(symbol_name, from_imp.module);
                continue;
            }

            // Special case: datetime module classes (date, time, timedelta)
            // These are handled via dispatch to datetime.date.today(), etc.
            // Don't generate const aliases since they would be functions, not types
            if (std.mem.eql(u8, from_imp.module, "datetime")) {
                if (std.mem.eql(u8, name, "date") or
                    std.mem.eql(u8, name, "time") or
                    std.mem.eql(u8, name, "timedelta"))
                {
                    try self.local_from_imports.put(symbol_name, from_imp.module);
                    continue;
                }
            }

            // Skip 'main' - conflicts with Zig's auto-generated entry point `pub fn main()`
            if (std.mem.eql(u8, symbol_name, "main")) {
                continue;
            }

            // Skip single-letter type variables that conflict with generated code patterns
            // These are rarely used at runtime and cause shadowing with internal `const T = @TypeOf(...)`
            if (std.mem.eql(u8, from_imp.module, "typing")) {
                if (std.mem.eql(u8, symbol_name, "T") or
                    std.mem.eql(u8, symbol_name, "KT") or
                    std.mem.eql(u8, symbol_name, "VT"))
                {
                    continue;
                }
            }

            try emitConst(self, "const ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
            try emitConst(self, " = ");

            // Normal case: use module const reference
            // For simple module names (no dots), use writeLocalVarName to match module import generation
            // (e.g., `copy` becomes `copy_` to avoid shadowing struct methods)
            if (std.mem.indexOfScalar(u8, from_imp.module, '.') != null) {
                try zig_keywords.writeEscapedDottedIdent(self.output.writer(self.allocator), from_imp.module);
            } else {
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), from_imp.module);
            }
            try emitConst(self, ".");
            try emitConst(self, name);
            try emitConst(self, ";\n");
            try generated_symbols.put(symbol_name, {});
            // Track const for discard emission (prevents "unused constant" errors)
            try const_symbols.put(symbol_name, {});

            // Track for local import shadowing prevention
            try self.module_level_from_imports.put(symbol_name, {});

            // Register for dispatch routing (needed for typing.cast and similar)
            try self.local_from_imports.put(symbol_name, from_imp.module);
        }
    }

    if (self.from_imports.items.len > 0) {
        try emitConst(self, "\n");
    }

    // Emit discards for all const symbols to suppress "unused constant" errors
    // This is needed because from-imports may not be used if they're only for type hints
    // or the code path using them is conditionally compiled
    // Note: Must use comptime block since module-level doesn't allow bare statements
    if (const_symbols.count() > 0) {
        try emitConst(self, "comptime {\n");
        var const_iter = const_symbols.iterator();
        while (const_iter.next()) |entry| {
            try emitConst(self, "    _ = &");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), entry.key_ptr.*);
            try emitConst(self, ";\n");
        }
        try emitConst(self, "}\n");
    }
}
