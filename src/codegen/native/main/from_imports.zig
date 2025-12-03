const std = @import("std");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const hashmap_helper = @import("hashmap_helper");
const import_resolver = @import("../../../import_resolver.zig");
const zig_keywords = @import("zig_keywords");

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

const OperatorWrappers = std.StaticStringMap([]const u8).initComptime(.{
    .{ "eq", "(a: anytype, b: anytype) bool { return runtime.operatorEq(a, b); }\n" },
    .{ "ne", "(a: anytype, b: anytype) bool { return runtime.operatorNe(a, b); }\n" },
    .{ "lt", "(a: anytype, b: anytype) bool { return runtime.operatorLt(a, b); }\n" },
    .{ "le", "(a: anytype, b: anytype) bool { return runtime.operatorLe(a, b); }\n" },
    .{ "gt", "(a: anytype, b: anytype) bool { return runtime.operatorGt(a, b); }\n" },
    .{ "ge", "(a: anytype, b: anytype) bool { return runtime.operatorGe(a, b); }\n" },
    .{ "add", "(a: anytype, b: anytype) @TypeOf(a) { return a + b; }\n" },
    .{ "sub", "(a: anytype, b: anytype) @TypeOf(a) { return a - b; }\n" },
    .{ "mul", "(a: anytype, b: anytype) @TypeOf(a) { return a * b; }\n" },
    .{ "truediv", "(a: anytype, b: anytype) f64 { return @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b)); }\n" },
    .{ "floordiv", "(a: anytype, b: anytype) @TypeOf(a) { return @divFloor(a, b); }\n" },
    .{ "mod", "(a: anytype, b: anytype) @TypeOf(a) { return @rem(a, b); }\n" },
    .{ "neg", "(a: anytype) @TypeOf(a) { return -a; }\n" },
    .{ "not_", "(a: anytype) bool { return !runtime.toBool(a); }\n" },
    .{ "truth", "(a: anytype) bool { return runtime.toBool(a); }\n" },
});

/// Generate wrapper function for operator module function
fn generateOperatorWrapper(self: *NativeCodegen, name: []const u8, symbol_name: []const u8) !void {
    try self.emit("fn ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
    try self.emit(OperatorWrappers.get(name) orelse "(a: anytype, b: anytype) @TypeOf(a) { _ = b; return a; }\n");
}

/// Generate from-import symbol re-exports with deduplication
/// For "from json import loads", generates: const loads = json.loads;
pub fn generateFromImports(self: *NativeCodegen) !void {
    // Track generated symbols to avoid duplicates
    var generated_symbols = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer generated_symbols.deinit();

    for (self.from_imports.items) |from_imp| {
        // Skip relative imports (starting with .) - these are internal package imports
        // that don't make sense in standalone compiled modules
        if (from_imp.module.len > 0 and from_imp.module[0] == '.') {
            continue;
        }

        // Skip builtin modules (they're not compiled, so can't reference them)
        if (import_resolver.isBuiltinModule(from_imp.module)) {
            continue;
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
                        try self.emit("const ");
                        try self.emit(exp.name);
                        try self.emit(" = ");
                        try self.emit(exp.value);
                        try self.emit(";\n");
                        try generated_symbols.put(exp.name, {});
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
                    try self.emit("fn ");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
                    try self.emit("() runtime.FeatureMacros {\n");
                    try self.emit("    return runtime.FeatureMacros{};\n");
                    try self.emit("}\n");
                    try generated_symbols.put(symbol_name, {});
                } else {
                    // Other _testcapi functions - register for dispatch
                    try self.local_from_imports.put(symbol_name, from_imp.module);
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
                try self.emit("const ");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
                try self.emit(": ?*anyopaque = null;\n");
                try generated_symbols.put(symbol_name, {});
            }
            continue;
        }

        // Check if this is a Tier 1 runtime module (functions need allocator)
        const is_runtime_module = self.import_registry.lookup(from_imp.module) != null and
            (std.mem.eql(u8, from_imp.module, "json") or
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
                    try self.emit("fn ");
                    try self.emit(symbol_name);
                    try self.emit("(json_str: []const u8, allocator: std.mem.Allocator) !*runtime.PyObject {\n");
                    try self.emit("    const json_str_obj = try runtime.PyString.create(__global_allocator, json_str);\n");
                    try self.emit("    defer runtime.decref(json_str_obj, allocator);\n");
                    try self.emit("    return try runtime.json.loads(json_str_obj, allocator);\n");
                    try self.emit("}\n");
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
                // Skip - module already declared with same name, code like `copy(x)` will call copy.copy
                // which is the correct behavior. No need for redundant const copy = std.copy;
                continue;
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

            try self.emit("const ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
            try self.emit(" = ");

            // Normal case: use module const reference
            try zig_keywords.writeEscapedDottedIdent(self.output.writer(self.allocator), from_imp.module);
            try self.emit(".");
            try self.emit(name);
            try self.emit(";\n");
            try generated_symbols.put(symbol_name, {});
        }
    }

    if (self.from_imports.items.len > 0) {
        try self.emit("\n");
    }
}
