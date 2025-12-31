const std = @import("std");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const CodegenError = core.CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const import_resolver = @import("../../../import_resolver.zig");
const zig_keywords = @import("utils.zig_keywords");
const build_dirs = @import("../../../build_dirs.zig");

// MIGRATED TO ZIGBUILDER

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
    try self.emit("fn ");
    try self.emitIdent(symbol_name);
    try self.emit(OperatorWrappers.get(name) orelse "(a: anytype, b: anytype) @TypeOf(a) { _ = b; return a; }\n");
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

    // PHASE 1: Collect and import submodules for relative imports
    // Track which submodules need to be imported for relative imports
    var imported_submodules = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer imported_submodules.deinit();

    // Get the source Python directory for checking submodule paths
    // (Check Python source, not generated Zig - submodules may not be generated yet)
    const source_dir: ?[]const u8 = if (self.source_file_path) |sfp| blk: {
        // Get directory containing the source Python file
        // e.g., .venv/lib/python3.12/site-packages/numpy/__init__.py -> .venv/.../numpy/
        if (std.fs.path.dirname(sfp)) |dir| {
            break :blk dir;
        }
        break :blk null;
    } else null;

    // PHASE 0.5: Handle "from . import X" pattern (dots-only module)
    // When module is just dots (e.g., "."), the names list contains submodule names
    for (self.from_imports.items) |from_imp| {
        // Check if module is dots-only (e.g., ".", "..", "...")
        if (from_imp.module.len == 0) continue;

        var is_dots_only = true;
        for (from_imp.module) |c| {
            if (c != '.') {
                is_dots_only = false;
                break;
            }
        }
        if (!is_dots_only) continue;

        // This is "from . import X" pattern
        if (self.mode != .module) continue;

        const dots = from_imp.module.len; // Number of parent levels
        if (source_dir == null) continue;

        // Compute base directory by going up 'dots-1' levels
        // dots=1 means current package, dots=2 means parent, etc.
        var base_dir_opt: ?[]const u8 = source_dir;
        var levels = dots;
        while (levels > 1 and base_dir_opt != null) : (levels -= 1) {
            base_dir_opt = std.fs.path.dirname(base_dir_opt.?);
        }
        if (base_dir_opt == null) continue;
        const base_dir = base_dir_opt.?;

        // For each name in the import list, check if it's a submodule
        for (from_imp.names, 0..) |name, i| {
            if (std.mem.eql(u8, name, "*")) continue;

            const has_alias = i < from_imp.asnames.len and from_imp.asnames[i] != null;
            const alias_name = if (has_alias) from_imp.asnames[i].? else null;

            // Skip reserved names (check both original name and alias)
            if (zig_keywords.wouldShadowModule(name)) continue;
            if (zig_keywords.isZigKeyword(name)) continue;
            if (has_alias) {
                if (zig_keywords.wouldShadowModule(alias_name.?)) continue;
                if (zig_keywords.isZigKeyword(alias_name.?)) continue;
            }
            if (imported_submodules.contains(name)) continue;

            // Check if Python source exists: {base_dir}/{name}.py or {base_dir}/{name}/__init__.py
            // This determines the import path suffix for the generated Zig code
            const import_suffix: ?[]const u8 = suffix_blk: {
                const file_path = std.fmt.allocPrint(self.allocator, "{s}/{s}.py", .{ base_dir, name }) catch break :suffix_blk null;
                defer self.allocator.free(file_path);
                if (std.fs.cwd().access(file_path, .{})) |_| {
                    break :suffix_blk ".zig"; // Python module -> .zig
                } else |_| {}

                const dir_path = std.fmt.allocPrint(self.allocator, "{s}/{s}/__init__.py", .{ base_dir, name }) catch break :suffix_blk null;
                defer self.allocator.free(dir_path);
                if (std.fs.cwd().access(dir_path, .{})) |_| {
                    break :suffix_blk "/__init__.zig"; // Python package -> __init__.zig
                } else |_| {}

                break :suffix_blk null;
            };

            if (import_suffix == null) continue; // Not a Python source submodule

            // Generate import with appropriate relative path
            // Always import under the original name first (for from .X import Y to work)
            if (dots == 1) {
                try self.emitFmt("pub const {s} = @import(\"./{s}{s}\");\n", .{
                    name, name, import_suffix.?,
                });
                // If aliased, create an alias constant
                if (has_alias) {
                    try self.emitFmt("pub const {s} = {s};\n", .{ alias_name.?, name });
                }
            } else {
                // Multi-level: from .. import X -> "../{name}{suffix}"
                var rel_path_buf: [512]u8 = undefined;
                var fbs = std.io.fixedBufferStream(&rel_path_buf);
                const writer = fbs.writer();
                for (0..dots - 1) |_| {
                    writer.writeAll("../") catch break;
                }
                writer.writeAll(name) catch {};
                writer.writeAll(import_suffix.?) catch {};

                try self.emitFmt("pub const {s} = @import(\"{s}\");\n", .{
                    name, fbs.getWritten(),
                });
                // If aliased, create an alias constant
                if (has_alias) {
                    try self.emitFmt("pub const {s} = {s};\n", .{ alias_name.?, name });
                }
            }

            try imported_submodules.put(name, {});
        }
    }

    // Get the generated zig directory for checking if submodules were compiled (for PHASE 1)
    const gen_dir: ?[]const u8 = if (self.source_file_path) |sfp| blk: {
        const zig_path = build_dirs.projectZigPath(self.allocator, ".", sfp) catch break :blk null;
        defer self.allocator.free(zig_path);
        if (std.mem.lastIndexOfScalar(u8, zig_path, '/')) |idx| {
            break :blk self.allocator.dupe(u8, zig_path[0..idx]) catch null;
        }
        break :blk null;
    } else null;
    defer if (gen_dir) |d| self.allocator.free(d);

    // PHASE 1: Handle "from .module import X" pattern
    for (self.from_imports.items) |from_imp| {
        if (from_imp.module.len > 0 and from_imp.module[0] == '.') {
            if (self.mode != .module) continue;

            var dots: usize = 0;
            while (dots < from_imp.module.len and from_imp.module[dots] == '.') : (dots += 1) {}
            const submodule_name = from_imp.module[dots..];
            if (submodule_name.len == 0) continue;

            // Sanitize identifier: replace dots with double underscores
            // e.g., "lib._arraypad_impl" -> "lib___arraypad_impl"
            const ident_name = std.mem.replaceOwned(u8, self.allocator, submodule_name, ".", "__") catch continue;
            defer self.allocator.free(ident_name);

            if (imported_submodules.contains(submodule_name)) continue;

            // Skip if would shadow reserved names
            if (zig_keywords.wouldShadowModule(ident_name)) continue;
            if (zig_keywords.isZigKeyword(ident_name)) continue;

            // Determine correct import path by checking what exists in generated output
            // Check for: {gen_dir}/{submodule}.zig or {gen_dir}/{submodule}/__init__.zig
            // Also check if the file/directory actually exists before emitting
            const import_info: ?struct { suffix: []const u8, exists: bool } = suffix_check: {
                if (gen_dir) |dir| {
                    // Check for single-file module first: {dir}/{submodule}.zig
                    const file_path = std.fmt.allocPrint(self.allocator, "{s}/{s}.zig", .{ dir, submodule_name }) catch break :suffix_check null;
                    defer self.allocator.free(file_path);
                    if (std.fs.cwd().access(file_path, .{})) |_| {
                        break :suffix_check .{ .suffix = ".zig", .exists = true };
                    } else |_| {}

                    // Check for package directory: {dir}/{submodule}/__init__.zig
                    const dir_path = std.fmt.allocPrint(self.allocator, "{s}/{s}/__init__.zig", .{ dir, submodule_name }) catch break :suffix_check null;
                    defer self.allocator.free(dir_path);
                    if (std.fs.cwd().access(dir_path, .{})) |_| {
                        break :suffix_check .{ .suffix = "/__init__.zig", .exists = true };
                    } else |_| {}
                }
                break :suffix_check null;
            };

            // Skip if the submodule doesn't exist (not compiled)
            if (import_info == null) continue;
            const import_suffix = import_info.?.suffix;

            // Generate import statement using emitFmt
            try self.emitFmt("const {s} = @import(\"./{s}{s}\");\n", .{
                ident_name, submodule_name, import_suffix,
            });
            try imported_submodules.put(submodule_name, {});
        }
    }

    // PHASE 2: Generate re-exports for relative imports
    for (self.from_imports.items) |from_imp| {
        // Handle relative imports (starting with .) - these are package-internal imports
        // For packages like numpy, from .version import __version__ needs to re-export
        if (from_imp.module.len > 0 and from_imp.module[0] == '.') {
            // Skip for scripts (mode != .module)
            if (self.mode != .module) continue;

            // Get module name without leading dots (e.g., ".version" -> "version")
            var dots: usize = 0;
            while (dots < from_imp.module.len and from_imp.module[dots] == '.') : (dots += 1) {}
            const submodule_name = from_imp.module[dots..];

            // Skip if empty (from . import X has no module name)
            if (submodule_name.len == 0) continue;

            // Skip if submodule was filtered out (reserved name or not compiled)
            if (!imported_submodules.contains(submodule_name)) continue;

            // Sanitize identifier: replace dots with double underscores (same as PHASE 1)
            const ident_name = std.mem.replaceOwned(u8, self.allocator, submodule_name, ".", "__") catch continue;
            defer self.allocator.free(ident_name);

            // Generate re-exports for each imported symbol
            // from .version import __version__ -> pub const __version__ = version.__version__;
            for (from_imp.names, 0..) |name, i| {
                if (std.mem.eql(u8, name, "*")) continue;

                const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                    from_imp.asnames[i].?
                else
                    name;

                // Skip if would shadow reserved names or is a keyword
                if (zig_keywords.wouldShadowModule(symbol_name)) continue;
                if (zig_keywords.isZigKeyword(symbol_name)) continue;

                // Skip if already generated
                if (generated_symbols.contains(symbol_name)) continue;

                // Generate: pub const symbol_name = submodule.symbol;
                // Use sanitized ident_name for the module reference
                try self.emitFmt("pub const {s} = {s}.{s};\n", .{ symbol_name, ident_name, name });
                try generated_symbols.put(symbol_name, {});
            }
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

        // Handle os.path submodule (from os.path import dirname, basename, join, etc.)
        // os.path functions are available as os.path.dirname, os.path.basename, etc. in the runtime
        if (std.mem.eql(u8, from_imp.module, "os.path")) {
            for (from_imp.names, 0..) |name, i| {
                if (std.mem.eql(u8, name, "*")) continue;

                const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                    from_imp.asnames[i].?
                else
                    name;

                // Skip if already generated
                if (generated_symbols.contains(symbol_name)) continue;

                // Generate: const symbol_name = os.path.function_name;
                try self.emit("const ");
                try self.emitIdent(symbol_name);
                try self.emit(" = os.path.");
                try self.emitIdent(name);
                try self.emit(";\n");
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
                    try self.emit("fn ");
                    try self.emitIdent(symbol_name);
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
                        try self.emit("const ");
                        try self.emit(exp_name);
                        try self.emit(" = stringprep.");
                        try self.emit(exp_name);
                        try self.emit(";\n");
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
                        try self.emit("const ");
                        try self.emit(exp_name);
                        try self.emit(" = contextlib.");
                        try self.emit(exp_name);
                        try self.emit(";\n");
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
                        try self.emit("const ");
                        try self.emitIdent(symbol_name);
                        try self.emit(" = contextlib.");
                        try self.emit(name);
                        try self.emit(";\n");
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
                "batched",
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
                        try self.emit("const ");
                        try self.emit(exp_name);
                        try self.emit(" = itertools.");
                        try self.emit(exp_name);
                        try self.emit(";\n");
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
                        try self.emit("const ");
                        try self.emitIdent(symbol_name);
                        try self.emit(" = itertools.");
                        try self.emit(name);
                        try self.emit(";\n");
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
                        try self.emit("const ");
                        try self.emit(exp_name);
                        try self.emit(" = sys.");
                        try self.emit(exp_name);
                        try self.emit(";\n");
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
                        try self.emit("const ");
                        try self.emit(exp_name);
                        try self.emit(" = subprocess.");
                        try self.emit(exp_name);
                        try self.emit(";\n");
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
                        try self.emit("const ");
                        try self.emit(exp_name);
                        try self.emit(" = collections.abc.");
                        try self.emit(exp_name);
                        try self.emit(";\n");
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
                    try self.emit("const ");
                    try self.emitIdent(symbol_name);
                    try self.emit(": []const []const u8 = &[_][]const u8{};\n");
                    try generated_symbols.put(symbol_name, {});
                    // Track for local variable shadowing prevention
                    try self.module_level_from_imports.put(symbol_name, {});
                }
                continue;
            }

            // Check if this is a C extension module (or submodule of one)
            // e.g., from numpy.testing import assert_ -> c_interop.getAttr(numpy.testing, "assert_")
            // These must be vars initialized in main() since they require runtime module loading
            if (self.isCExtensionModule(from_imp.module)) {
                for (from_imp.names, 0..) |name, i| {
                    if (std.mem.eql(u8, name, "*")) continue;
                    const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                        from_imp.asnames[i].?
                    else
                        name;
                    if (generated_symbols.contains(symbol_name)) continue;
                    // Generate: [pub] var symbol_name: ?*c_interop.PyObject = null;
                    // The actual initialization happens in main() after the module is loaded
                    // Use pub for module mode so symbols are accessible from importing modules
                    if (self.mode == .module) try self.emit("pub ");
                    try self.emit("var ");
                    try self.emitIdent(symbol_name);
                    try self.emit(": ?*c_interop.PyObject = null;\n");
                    try generated_symbols.put(symbol_name, {});
                    // Track for local variable shadowing prevention
                    try self.module_level_from_imports.put(symbol_name, {});
                    // Track for main() initialization
                    try self.c_extension_from_imports.put(symbol_name, .{ .module = from_imp.module, .attr = name });
                }
                continue;
            }

            // Module not in registry - check if it's a known pure Python subpackage
            // that needs runtime import (e.g., numpy.testing.NUMPY_ROOT is a Path)
            const is_known_subpackage = blk: {
                // Check if this is a subpackage of a known C extension parent
                // e.g., numpy.testing is under numpy (a C extension)
                var iter = std.mem.splitScalar(u8, from_imp.module, '.');
                if (iter.next()) |first_part| {
                    if (self.isCExtensionModule(first_part)) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            if (is_known_subpackage) {
                // Use c_interop to fetch at runtime, same as C extensions
                for (from_imp.names, 0..) |name, i| {
                    if (std.mem.eql(u8, name, "*")) continue;
                    const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                        from_imp.asnames[i].?
                    else
                        name;
                    if (generated_symbols.contains(symbol_name)) continue;
                    // Generate: [pub] var symbol_name: ?*c_interop.PyObject = null;
                    // Use pub for module mode so symbols are accessible from importing modules
                    if (self.mode == .module) try self.emit("pub ");
                    try self.emit("var ");
                    try self.emitIdent(symbol_name);
                    try self.emit(": ?*c_interop.PyObject = null;\n");
                    try generated_symbols.put(symbol_name, {});
                    try self.module_level_from_imports.put(symbol_name, {});
                    // Track for main() initialization
                    try self.c_extension_from_imports.put(symbol_name, .{ .module = from_imp.module, .attr = name });
                }
                continue;
            }

            // Unknown module - generate null placeholders for optional imports
            // This handles try/except ImportError patterns like: from foo import bar
            for (from_imp.names, 0..) |name, i| {
                if (std.mem.eql(u8, name, "*")) continue;
                const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                    from_imp.asnames[i].?
                else
                    name;
                if (generated_symbols.contains(symbol_name)) continue;
                // Generate: const symbol_name = null; for unavailable modules
                try self.emit("const ");
                try self.emitIdent(symbol_name);
                try self.emit(": ?*anyopaque = null;\n");
                try generated_symbols.put(symbol_name, {});
                // Track for local variable shadowing prevention
                try self.module_level_from_imports.put(symbol_name, {});
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

                // For pickle.loads, generate a wrapper function that accepts bytes and allocator
                if (std.mem.eql(u8, from_imp.module, "pickle") and std.mem.eql(u8, name, "loads")) {
                    try self.emit("fn ");
                    try self.emit(symbol_name);
                    try self.emit("(data: []const u8, allocator: std.mem.Allocator) !*runtime.PyObject {\n");
                    try self.emit("    return try runtime.pickle.loads(data, allocator);\n");
                    try self.emit("}\n");
                    try generated_symbols.put(symbol_name, {});
                    continue; // Skip const generation for this one
                }

                // For pickle.dumps, generate a wrapper function
                if (std.mem.eql(u8, from_imp.module, "pickle") and std.mem.eql(u8, name, "dumps")) {
                    try self.emit("fn ");
                    try self.emit(symbol_name);
                    try self.emit("(obj: anytype, protocol: anytype) []const u8 {\n");
                    try self.emit("    _ = protocol; // Protocol not used in simplified implementation\n");
                    try self.emit("    return runtime.json.dumpsValue(obj, __global_allocator) catch \"\";\n");
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

            try self.emit("const ");
            try self.emitIdent(symbol_name);
            try self.emit(" = ");

            // Normal case: use module const reference
            // Use emitIdent (not emitVarName) to match module import generation in generator.zig
            // Generator uses emitIdent, so module 'math' becomes 'const math = ...'
            // We must also use emitIdent so from-import 'const isinf = math.isinf' matches
            if (std.mem.indexOfScalar(u8, from_imp.module, '.') != null) {
                try self.emitDottedIdent(from_imp.module);
            } else {
                try self.emitIdent(from_imp.module);
            }
            try self.emit(".");
            try self.emit(name);
            try self.emit(";\n");
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
        try self.emit("\n");
    }

    // Emit discards for all const symbols to suppress "unused constant" errors
    // This is needed because from-imports may not be used if they're only for type hints
    // or the code path using them is conditionally compiled
    // Note: Must use comptime block since module-level doesn't allow bare statements
    if (const_symbols.count() > 0) {
        try self.emit("comptime {\n");
        var const_iter = const_symbols.iterator();
        while (const_iter.next()) |entry| {
            try self.emit("    _ = &");
            try self.emitIdent(entry.key_ptr.*);
            try self.emit(";\n");
        }
        try self.emit("}\n");
    }
}
