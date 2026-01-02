const std = @import("std");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const CodegenError = core.CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const import_resolver = @import("../../../import_resolver.zig");
const zig_keywords = @import("utils.zig_keywords");
const build_dirs = @import("../../../build_dirs.zig");

/// Parse __all__ list from a Python source file
/// Returns a list of exported symbol names, or null if __all__ not found
pub fn parseAllList(allocator: std.mem.Allocator, py_path: []const u8) ?std.ArrayList([]const u8) {
    const file = std.fs.cwd().openFile(py_path, .{}) catch return null;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch return null;
    defer allocator.free(content);

    // Find __all__ = [ or __all__: list = [
    var start_idx: ?usize = null;
    var search_start: usize = 0;
    while (search_start < content.len) {
        const all_pos = std.mem.indexOf(u8, content[search_start..], "__all__") orelse break;
        const pos = search_start + all_pos;

        // Find the [ after __all__
        var i = pos + 7; // Skip "__all__"
        while (i < content.len and (content[i] == ' ' or content[i] == ':' or content[i] == '=' or
            (content[i] >= 'a' and content[i] <= 'z'))) : (i += 1)
        {}
        if (i < content.len) {
            // Skip whitespace
            while (i < content.len and (content[i] == ' ' or content[i] == '\n' or content[i] == '\t')) : (i += 1) {}
            if (i < content.len and content[i] == '[') {
                start_idx = i;
                break;
            }
        }
        search_start = pos + 7;
    }
    const list_start = start_idx orelse return null;

    // Find matching ]
    var depth: usize = 0;
    var end_idx: ?usize = null;
    var j = list_start;
    while (j < content.len) : (j += 1) {
        if (content[j] == '[') depth += 1;
        if (content[j] == ']') {
            depth -= 1;
            if (depth == 0) {
                end_idx = j;
                break;
            }
        }
    }
    const list_end = end_idx orelse return null;

    // Parse the list content
    var result: std.ArrayList([]const u8) = .{};
    const list_content = content[list_start + 1 .. list_end];

    // Extract quoted strings
    var in_string = false;
    var quote_char: u8 = 0;
    var string_start: usize = 0;
    for (list_content, 0..) |c, idx| {
        if (!in_string and (c == '\'' or c == '"')) {
            in_string = true;
            quote_char = c;
            string_start = idx + 1;
        } else if (in_string and c == quote_char) {
            const symbol = list_content[string_start..idx];
            // Skip keywords and reserved names
            if (!zig_keywords.isZigKeyword(symbol) and !zig_keywords.wouldShadowModule(symbol)) {
                const duped = allocator.dupe(u8, symbol) catch continue;
                result.append(allocator, duped) catch continue;
            }
            in_string = false;
        }
    }

    if (result.items.len == 0) {
        result.deinit(allocator);
        return null;
    }
    return result;
}

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

    // CHECK: Skip generating relative @import for files inside a package that's imported as a module
    // This prevents Zig 0.15 "file exists in multiple modules" errors
    // e.g., When numpy/_core/numeric.py imports numpy as a module, don't generate
    // @import("./multiarray.zig") because numpy._core.__init__.zig already imports it
    // Instead, generate: const multiarray = numpy._core.multiarray;
    var skip_relative_imports = false;
    var parent_package_name: ?[]const u8 = null;
    var relative_package_path: ?[]const u8 = null;

    if (self.source_file_path) |sfp| {
        // Only applies to files inside site-packages (external packages)
        if (std.mem.indexOf(u8, sfp, "site-packages") != null) {
            // Check if any imported module is an ancestor package of this file
            // e.g., file is numpy/_core/numeric.py and "numpy" is imported
            for (self.imported_modules.keys()) |mod_name| {
                // Check if module name appears in the source path
                // e.g., "numpy" in ".../numpy/_core/numeric.py"
                if (std.mem.indexOf(u8, sfp, mod_name) != null) {
                    // Verify it's actually a directory component, not just a substring
                    const mod_in_path = std.fmt.allocPrint(self.allocator, "/{s}/", .{mod_name}) catch continue;
                    defer self.allocator.free(mod_in_path);
                    if (std.mem.indexOf(u8, sfp, mod_in_path)) |start_idx| {
                        // Don't skip for __init__.py - it IS the package root and should generate imports
                        // e.g., numpy/__init__.py should generate @import("./version.zig"), not skip
                        if (std.mem.endsWith(u8, sfp, "__init__.py")) continue;
                        skip_relative_imports = true;
                        parent_package_name = mod_name;
                        // Extract relative path: everything after the package name up to the file
                        // e.g., for ".../numpy/_core/numeric.py" with package "numpy", get "_core"
                        const after_pkg = sfp[start_idx + mod_in_path.len ..];
                        if (std.fs.path.dirname(after_pkg)) |rel_dir| {
                            if (rel_dir.len > 0) {
                                relative_package_path = rel_dir;
                            }
                        }
                        break;
                    }
                }
            }
        }
    }

    // PHASE 0.4: Generate package-qualified aliases when skip_relative_imports is true
    // Instead of @import("./multiarray.zig"), generate: const multiarray = numpy._core.multiarray;
    if (skip_relative_imports and parent_package_name != null) {
        const pkg_name = parent_package_name.?;

        for (self.from_imports.items) |from_imp| {
            if (from_imp.module.len == 0) continue;
            if (from_imp.module[0] != '.') continue; // Only handle relative imports

            // Count leading dots
            var dots: usize = 0;
            while (dots < from_imp.module.len and from_imp.module[dots] == '.') : (dots += 1) {}
            const submodule_name = from_imp.module[dots..];

            // Build the package-qualified prefix
            // For "from . import X" in numpy/_core/numeric.py: prefix = numpy._core
            // For "from .submod import X": prefix = numpy._core.submod
            var prefix_buf: [512]u8 = undefined;
            var prefix_fbs = std.io.fixedBufferStream(&prefix_buf);
            const prefix_writer = prefix_fbs.writer();
            prefix_writer.writeAll(pkg_name) catch continue;

            // Add relative_package_path if present (e.g., "_core")
            if (relative_package_path) |rel_path| {
                // Convert path separators to dots
                prefix_writer.writeAll(".") catch continue;
                for (rel_path) |c| {
                    if (c == '/' or c == '\\') {
                        prefix_writer.writeAll(".") catch continue;
                    } else {
                        prefix_writer.writeByte(c) catch continue;
                    }
                }
            }

            // For "from .submod import X", add the submodule
            if (submodule_name.len > 0) {
                prefix_writer.writeAll(".") catch continue;
                // Replace dots in submodule name with double underscores for nested
                for (submodule_name) |c| {
                    if (c == '.') {
                        prefix_writer.writeAll("__") catch continue;
                    } else {
                        prefix_writer.writeByte(c) catch continue;
                    }
                }
            }

            const prefix = prefix_fbs.getWritten();

            // Build actual dotted module name for C extension checking (not Zig identifiers)
            // e.g., "numpy._core.multiarray" (keeps dots, not __ replacements)
            var abs_module_buf: [512]u8 = undefined;
            var abs_module_fbs = std.io.fixedBufferStream(&abs_module_buf);
            const abs_module_writer = abs_module_fbs.writer();
            abs_module_writer.writeAll(pkg_name) catch continue;
            if (relative_package_path) |rel_path| {
                abs_module_writer.writeAll(".") catch continue;
                for (rel_path) |c| {
                    if (c == '/' or c == '\\') {
                        abs_module_writer.writeAll(".") catch continue;
                    } else {
                        abs_module_writer.writeByte(c) catch continue;
                    }
                }
            }
            if (submodule_name.len > 0) {
                abs_module_writer.writeAll(".") catch continue;
                abs_module_writer.writeAll(submodule_name) catch continue;
            }
            const abs_module_name = abs_module_fbs.getWritten();
            const is_c_ext_import = self.isCExtensionModule(abs_module_name);

            // Generate aliases for each imported name
            for (from_imp.names, 0..) |name, i| {
                // Handle star imports
                if (std.mem.eql(u8, name, "*")) {
                    if (is_c_ext_import) {
                        // C extension star import - use current source file's __all__
                        if (self.source_file_path) |sfp| {
                            var current_all = parseAllList(self.allocator, sfp) orelse continue;
                            defer {
                                for (current_all.items) |item| {
                                    self.allocator.free(item);
                                }
                                current_all.deinit(self.allocator);
                            }

                            for (current_all.items) |symbol| {
                                if (generated_symbols.contains(symbol)) continue;
                                if (zig_keywords.wouldShadowModule(symbol)) continue;
                                if (zig_keywords.isZigKeyword(symbol)) continue;

                                // Generate: pub var symbol: ?*c_interop.PyObject = null;
                                if (self.mode == .module) try self.emit("pub ");
                                try self.emit("var ");
                                try self.emitIdent(symbol);
                                try self.emit(": ?*c_interop.PyObject = null;\n");
                                try generated_symbols.put(symbol, {});
                                try self.module_level_from_imports.put(symbol, {});
                                const name_copy = try self.arena.allocator().dupe(u8, symbol);
                                const module_copy = try self.arena.allocator().dupe(u8, abs_module_name);
                                try self.c_extension_from_imports.put(symbol, .{ .module = module_copy, .attr = name_copy });
                            }
                        }
                    } else if (submodule_name.len > 0) {
                        // Python module star import - parse submodule's __all__ and generate re-exports
                        if (source_dir) |dir| {
                            // Try {dir}/{submodule}.py first
                            const py_file = std.fmt.allocPrint(self.allocator, "{s}/{s}.py", .{ dir, submodule_name }) catch continue;
                            defer self.allocator.free(py_file);

                            var all_list = parseAllList(self.allocator, py_file);

                            // If not found, try {dir}/{submodule}/__init__.py
                            if (all_list == null) {
                                const init_file = std.fmt.allocPrint(self.allocator, "{s}/{s}/__init__.py", .{ dir, submodule_name }) catch continue;
                                defer self.allocator.free(init_file);
                                all_list = parseAllList(self.allocator, init_file);
                            }

                            if (all_list) |*list| {
                                defer {
                                    for (list.items) |item| {
                                        self.allocator.free(item);
                                    }
                                    list.deinit(self.allocator);
                                }

                                // Generate re-exports for each symbol in __all__
                                for (list.items) |symbol| {
                                    if (generated_symbols.contains(symbol)) continue;
                                    if (zig_keywords.wouldShadowModule(symbol)) continue;
                                    if (zig_keywords.isZigKeyword(symbol)) continue;

                                    // Skip if symbol name matches the module name
                                    if (std.mem.eql(u8, symbol, submodule_name)) continue;

                                    // Generate: pub const symbol = prefix.symbol;
                                    try self.emitFmt("pub const {s} = {s}.{s};\n", .{ symbol, prefix, symbol });
                                    try generated_symbols.put(symbol, {});
                                    try self.module_level_from_imports.put(symbol, {});
                                }
                            }
                        }
                    }
                    continue;
                }

                const has_alias = i < from_imp.asnames.len and from_imp.asnames[i] != null;
                const symbol_name = if (has_alias) from_imp.asnames[i].? else name;

                // Skip reserved names
                if (zig_keywords.wouldShadowModule(symbol_name)) continue;
                if (zig_keywords.isZigKeyword(symbol_name)) continue;
                if (generated_symbols.contains(symbol_name)) continue;

                // Check if this is a C extension import
                if (is_c_ext_import) {
                    // C extension - generate runtime binding
                    // pub var dtype: ?*c_interop.PyObject = null;
                    if (self.mode == .module) try self.emit("pub ");
                    try self.emit("var ");
                    try self.emitIdent(symbol_name);
                    try self.emit(": ?*c_interop.PyObject = null;\n");
                    try generated_symbols.put(symbol_name, {});
                    try self.module_level_from_imports.put(symbol_name, {});
                    // Track for main() initialization
                    const name_copy = try self.arena.allocator().dupe(u8, name);
                    const module_copy = try self.arena.allocator().dupe(u8, abs_module_name);
                    try self.c_extension_from_imports.put(symbol_name, .{ .module = module_copy, .attr = name_copy });
                    continue;
                }

                // For "from . import X", X is the submodule name itself
                // Generate: const X = numpy._core.X;
                if (submodule_name.len == 0) {
                    // "from . import X" pattern
                    try self.emitFmt("pub const {s} = {s}.{s};\n", .{ symbol_name, prefix, name });
                } else {
                    // "from .module import symbol" pattern
                    // Generate: const symbol = numpy._core.module.symbol;
                    try self.emitFmt("pub const {s} = {s}.{s};\n", .{ symbol_name, prefix, name });
                }

                try generated_symbols.put(symbol_name, {});
                try self.module_level_from_imports.put(symbol_name, {});
            }
        }
    }

    // PHASE 0.5: Handle "from . import X" pattern (dots-only module)
    // When module is just dots (e.g., "."), the names list contains submodule names
    // Skip if inside a package that's imported as a module (prevents Zig module conflicts)
    if (!skip_relative_imports) {
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
                // Track this import so local variables don't shadow it
                const name_copy = try self.arena.allocator().dupe(u8, name);
                try self.imported_modules.put(name_copy, {});
                // If aliased, create an alias constant
                if (has_alias) {
                    try self.emitFmt("pub const {s} = {s};\n", .{ alias_name.?, name });
                    const alias_copy = try self.arena.allocator().dupe(u8, alias_name.?);
                    try self.imported_modules.put(alias_copy, {});
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
                // Track this import so local variables don't shadow it
                const name_copy = try self.arena.allocator().dupe(u8, name);
                try self.imported_modules.put(name_copy, {});
                // If aliased, create an alias constant
                if (has_alias) {
                    try self.emitFmt("pub const {s} = {s};\n", .{ alias_name.?, name });
                    const alias_copy = try self.arena.allocator().dupe(u8, alias_name.?);
                    try self.imported_modules.put(alias_copy, {});
                }
            }

            try imported_submodules.put(name, {});
        }
        }
    }

    // PHASE 1: Handle "from .module import X" pattern
    // Skip if inside a package that's imported as a module (prevents Zig module conflicts)
    if (!skip_relative_imports) {
        for (self.from_imports.items) |from_imp| {
        if (from_imp.module.len > 0 and from_imp.module[0] == '.') {
            if (self.mode != .module) continue;

            var dots: usize = 0;
            while (dots < from_imp.module.len and from_imp.module[dots] == '.') : (dots += 1) {}
            const submodule_name = from_imp.module[dots..];
            if (submodule_name.len == 0) continue;

            // Sanitize identifier: replace dots with double underscores
            // e.g., "lib._arraypad_impl" -> "lib___arraypad_impl"
            var ident_name = std.mem.replaceOwned(u8, self.allocator, submodule_name, ".", "__") catch continue;
            defer self.allocator.free(ident_name);

            // Check if module name conflicts with a function/class defined in this module
            // e.g., "from .printoptions import format_options" + "def printoptions(): ..."
            // In this case, rename the module import to "{module}_module"
            if (self.module_level_funcs.contains(ident_name)) {
                const suffixed = std.fmt.allocPrint(self.allocator, "{s}_module", .{ident_name}) catch continue;
                self.allocator.free(ident_name);
                ident_name = suffixed;
            }

            if (imported_submodules.contains(submodule_name)) continue;

            // Skip if would shadow reserved names
            if (zig_keywords.wouldShadowModule(ident_name)) continue;
            if (zig_keywords.isZigKeyword(ident_name)) continue;

            // Determine correct import path by checking what exists in Python source
            // Check for: {source_dir}/{submodule}.py or {source_dir}/{submodule}/__init__.py
            // NOTE: Check Python source (not generated Zig) because parallel codegen may not have
            // generated the .zig file yet. If Python source exists, .zig will be generated.
            const import_suffix: ?[]const u8 = suffix_check: {
                if (source_dir) |dir| {
                    // Check for single-file module first: {dir}/{submodule}.py
                    const file_path = std.fmt.allocPrint(self.allocator, "{s}/{s}.py", .{ dir, submodule_name }) catch break :suffix_check null;
                    defer self.allocator.free(file_path);
                    if (std.fs.cwd().access(file_path, .{})) |_| {
                        break :suffix_check ".zig"; // Python module -> .zig
                    } else |_| {}

                    // Check for package directory: {dir}/{submodule}/__init__.py
                    const dir_path = std.fmt.allocPrint(self.allocator, "{s}/{s}/__init__.py", .{ dir, submodule_name }) catch break :suffix_check null;
                    defer self.allocator.free(dir_path);
                    if (std.fs.cwd().access(dir_path, .{})) |_| {
                        break :suffix_check "/__init__.zig"; // Python package -> __init__.zig
                    } else |_| {}
                }
                break :suffix_check null;
            };

            // Skip if the submodule doesn't exist (C extension or not found)
            if (import_suffix == null) continue;

            // Generate import statement using emitFmt
            try self.emitFmt("const {s} = @import(\"./{s}{s}\");\n", .{
                ident_name, submodule_name, import_suffix.?,
            });
            try imported_submodules.put(submodule_name, {});
            // Track this import so local variables don't shadow it
            const ident_copy = try self.arena.allocator().dupe(u8, ident_name);
            try self.imported_modules.put(ident_copy, {});
        }
        }
    }

    // PHASE 2: Generate re-exports for relative imports
    for (self.from_imports.items) |from_imp| {
        // Handle relative imports (starting with .) - these are package-internal imports
        // For packages like numpy, from .version import __version__ needs to re-export
        if (from_imp.module.len > 0 and from_imp.module[0] == '.') {
            // Skip for scripts (mode != .module)
            if (self.mode != .module) continue;
            // Skip if inside a package that's imported as a module (prevents Zig module conflicts)
            if (skip_relative_imports) continue;

            // Get module name without leading dots (e.g., ".version" -> "version")
            var dots: usize = 0;
            while (dots < from_imp.module.len and from_imp.module[dots] == '.') : (dots += 1) {}
            const submodule_name = from_imp.module[dots..];

            // Skip if empty (from . import X has no module name)
            if (submodule_name.len == 0) continue;

            // Check if submodule was already imported in Phase 1
            const submodule_imported = imported_submodules.contains(submodule_name);

            // Sanitize identifier: replace dots with double underscores (same as PHASE 1)
            var ident_name = std.mem.replaceOwned(u8, self.allocator, submodule_name, ".", "__") catch continue;
            defer self.allocator.free(ident_name);

            // Apply same suffix as PHASE 1 if module name conflicts with function/class
            if (self.module_level_funcs.contains(ident_name)) {
                const suffixed = std.fmt.allocPrint(self.allocator, "{s}_module", .{ident_name}) catch continue;
                self.allocator.free(ident_name);
                ident_name = suffixed;
            }

            // Determine import path suffix for direct imports
            // Build the relative import path based on number of dots
            var import_path_buf: [512]u8 = undefined;
            var import_path_fbs = std.io.fixedBufferStream(&import_path_buf);
            const import_path_writer = import_path_fbs.writer();
            for (0..dots - 1) |_| {
                import_path_writer.writeAll("../") catch break;
            }
            import_path_writer.writeAll(submodule_name) catch {};
            import_path_writer.writeAll(".zig") catch {};
            const import_path = import_path_fbs.getWritten();

            // Check if Python source exists (not generated .zig) to determine if it's a Python module
            // NOTE: Check Python source because parallel codegen may not have generated the .zig yet.
            // If Python source exists, .zig will eventually be generated.
            const submodule_is_python: bool = exists_check: {
                if (source_dir) |dir| {
                    // Check for single-file module: {dir}/{submodule}.py
                    const file_path = std.fmt.allocPrint(self.allocator, "{s}/{s}.py", .{ dir, submodule_name }) catch break :exists_check false;
                    defer self.allocator.free(file_path);
                    if (std.fs.cwd().access(file_path, .{})) |_| {
                        break :exists_check true;
                    } else |_| {}

                    // Check for package directory: {dir}/{submodule}/__init__.py
                    const dir_path = std.fmt.allocPrint(self.allocator, "{s}/{s}/__init__.py", .{ dir, submodule_name }) catch break :exists_check false;
                    defer self.allocator.free(dir_path);
                    if (std.fs.cwd().access(dir_path, .{})) |_| {
                        break :exists_check true;
                    } else |_| {}
                }
                break :exists_check false;
            };

            // Generate re-exports for each imported symbol
            // from .version import __version__ -> pub const __version__ = version.__version__;
            for (from_imp.names, 0..) |name, i| {
                // Handle star imports by expanding __all__ from the submodule
                if (std.mem.eql(u8, name, "*")) {
                    // Find the Python source file for this submodule
                    if (source_dir) |dir| {
                        // Try {dir}/{submodule}.py first
                        const py_file = std.fmt.allocPrint(self.allocator, "{s}/{s}.py", .{ dir, submodule_name }) catch continue;
                        defer self.allocator.free(py_file);

                        var all_list = parseAllList(self.allocator, py_file);

                        // If not found, try {dir}/{submodule}/__init__.py
                        if (all_list == null) {
                            const init_file = std.fmt.allocPrint(self.allocator, "{s}/{s}/__init__.py", .{ dir, submodule_name }) catch continue;
                            defer self.allocator.free(init_file);
                            all_list = parseAllList(self.allocator, init_file);
                        }

                        if (all_list) |*list| {
                            defer {
                                for (list.items) |item| {
                                    self.allocator.free(item);
                                }
                                list.deinit(self.allocator);
                            }

                            // Generate re-exports for each symbol in __all__
                            for (list.items) |symbol| {
                                // Skip if already generated
                                if (generated_symbols.contains(symbol)) continue;

                                // Skip if symbol name matches the module name
                                // e.g., "from .memmap import *" where memmap exports 'memmap'
                                // The module is already imported as 'const memmap = @import(...)'
                                if (std.mem.eql(u8, symbol, submodule_name)) continue;

                                if (submodule_imported) {
                                    // Generate: pub const symbol = submodule.symbol;
                                    try self.emitFmt("pub const {s} = {s}.{s};\n", .{ symbol, ident_name, symbol });
                                } else if (submodule_is_python) {
                                    // Generate direct import: pub const symbol = @import("./submodule.zig").symbol;
                                    try self.emitFmt("pub const {s} = @import(\"{s}\").{s};\n", .{ symbol, import_path, symbol });
                                } else {
                                    // Submodule is C extension - derive absolute module name and generate runtime binding
                                    const abs_mod: ?[]const u8 = abs_blk: {
                                        const sdir = source_dir orelse break :abs_blk null;
                                        if (std.mem.indexOf(u8, sdir, "site-packages/")) |sp_idx| {
                                            const pkg_path = sdir[sp_idx + "site-packages/".len ..];
                                            var abs_buf: [512]u8 = undefined;
                                            var abs_fbs = std.io.fixedBufferStream(&abs_buf);
                                            const abs_writer = abs_fbs.writer();
                                            var prev_was_sep = false;
                                            for (pkg_path) |c| {
                                                if (c == '/' or c == '\\') {
                                                    if (!prev_was_sep) {
                                                        abs_writer.writeByte('.') catch break :abs_blk null;
                                                        prev_was_sep = true;
                                                    }
                                                } else {
                                                    abs_writer.writeByte(c) catch break :abs_blk null;
                                                    prev_was_sep = false;
                                                }
                                            }
                                            var written = abs_fbs.getWritten();
                                            if (written.len > 0 and written[written.len - 1] == '.') {
                                                written = written[0 .. written.len - 1];
                                            }
                                            abs_writer.writeByte('.') catch break :abs_blk null;
                                            abs_writer.writeAll(submodule_name) catch break :abs_blk null;
                                            break :abs_blk abs_fbs.getWritten();
                                        }
                                        break :abs_blk null;
                                    };

                                    if (abs_mod) |abs_module| {
                                        if (self.isCExtensionModule(abs_module)) {
                                            // C extension - generate runtime binding
                                            if (self.mode == .module) try self.emit("pub ");
                                            try self.emit("var ");
                                            try self.emitIdent(symbol);
                                            try self.emit(": ?*c_interop.PyObject = null;\n");
                                            try generated_symbols.put(symbol, {});
                                            try self.module_level_from_imports.put(symbol, {});
                                            const name_copy = try self.arena.allocator().dupe(u8, symbol);
                                            const module_copy = try self.arena.allocator().dupe(u8, abs_module);
                                            try self.c_extension_from_imports.put(symbol, .{ .module = module_copy, .attr = name_copy });
                                            continue;
                                        }
                                    }
                                    // Unknown C extension - skip
                                    continue;
                                }
                                try generated_symbols.put(symbol, {});
                                // Track for local variable shadowing prevention
                                try self.module_level_from_imports.put(symbol, {});
                            }
                        } else if (!submodule_is_python) {
                            // C extension with no __all__ in .py file
                            // Try to use the CURRENT source file's __all__ as fallback
                            // This handles cases like: from ._multiarray_umath import *
                            // where multiarray.py has its own __all__ listing what it exports
                            const abs_mod: ?[]const u8 = abs_blk: {
                                const sdir = source_dir orelse break :abs_blk null;
                                if (std.mem.indexOf(u8, sdir, "site-packages/")) |sp_idx| {
                                    const pkg_path = sdir[sp_idx + "site-packages/".len ..];
                                    var abs_buf: [512]u8 = undefined;
                                    var abs_fbs = std.io.fixedBufferStream(&abs_buf);
                                    const abs_writer = abs_fbs.writer();
                                    var prev_was_sep = false;
                                    for (pkg_path) |c| {
                                        if (c == '/' or c == '\\') {
                                            if (!prev_was_sep) {
                                                abs_writer.writeByte('.') catch break :abs_blk null;
                                                prev_was_sep = true;
                                            }
                                        } else {
                                            abs_writer.writeByte(c) catch break :abs_blk null;
                                            prev_was_sep = false;
                                        }
                                    }
                                    var written = abs_fbs.getWritten();
                                    if (written.len > 0 and written[written.len - 1] == '.') {
                                        written = written[0 .. written.len - 1];
                                    }
                                    abs_writer.writeByte('.') catch break :abs_blk null;
                                    abs_writer.writeAll(submodule_name) catch break :abs_blk null;
                                    break :abs_blk abs_fbs.getWritten();
                                }
                                break :abs_blk null;
                            };

                            if (abs_mod) |abs_module| {
                                if (self.isCExtensionModule(abs_module)) {
                                    // Try to read the current source file's __all__
                                    if (self.source_file_path) |sfp| {
                                        var current_all = parseAllList(self.allocator, sfp) orelse continue;
                                        defer {
                                            for (current_all.items) |item| {
                                                self.allocator.free(item);
                                            }
                                            current_all.deinit(self.allocator);
                                        }

                                        // For each symbol in current module's __all__, generate C extension binding
                                        for (current_all.items) |symbol| {
                                            if (generated_symbols.contains(symbol)) continue;
                                            if (zig_keywords.wouldShadowModule(symbol)) continue;
                                            if (zig_keywords.isZigKeyword(symbol)) continue;

                                            // Generate: pub var symbol: ?*c_interop.PyObject = null;
                                            if (self.mode == .module) try self.emit("pub ");
                                            try self.emit("var ");
                                            try self.emitIdent(symbol);
                                            try self.emit(": ?*c_interop.PyObject = null;\n");
                                            try generated_symbols.put(symbol, {});
                                            try self.module_level_from_imports.put(symbol, {});
                                            const name_copy = try self.arena.allocator().dupe(u8, symbol);
                                            const module_copy = try self.arena.allocator().dupe(u8, abs_module);
                                            try self.c_extension_from_imports.put(symbol, .{ .module = module_copy, .attr = name_copy });
                                        }
                                    }
                                }
                            }
                        }
                    }
                    continue;
                }

                const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                    from_imp.asnames[i].?
                else
                    name;

                // Skip if would shadow reserved names or is a keyword
                if (zig_keywords.wouldShadowModule(symbol_name)) continue;
                if (zig_keywords.isZigKeyword(symbol_name)) continue;

                // Skip if already generated
                if (generated_symbols.contains(symbol_name)) continue;

                // Skip if symbol name matches the module name
                // e.g., "from .memmap import memmap" - module already imported as 'memmap'
                if (std.mem.eql(u8, symbol_name, submodule_name)) continue;

                if (submodule_imported) {
                    // Generate: pub const symbol_name = submodule.symbol;
                    // Use sanitized ident_name for the module reference
                    try self.emitFmt("pub const {s} = {s}.{s};\n", .{ symbol_name, ident_name, name });
                } else if (submodule_is_python) {
                    // Submodule is Python source - generate direct import
                    // from ._ufunc_config import errstate -> const errstate = @import("./_ufunc_config.zig").errstate;
                    try self.emitFmt("pub const {s} = @import(\"{s}\").{s};\n", .{ symbol_name, import_path, name });
                } else {
                    // Submodule is not Python - check if it's a C extension (.so file)
                    // Try to derive absolute module name from source_dir
                    const abs_module: ?[]const u8 = abs_blk: {
                        const sdir = source_dir orelse break :abs_blk null;
                        // Extract package path from site-packages
                        // e.g., ".venv/.../site-packages/numpy/_core/" -> "numpy._core.multiarray"
                        if (std.mem.indexOf(u8, sdir, "site-packages/")) |sp_idx| {
                            const pkg_path = sdir[sp_idx + "site-packages/".len ..];
                            // pkg_path = "numpy/_core/" -> we want "numpy._core"
                            var abs_buf: [512]u8 = undefined;
                            var abs_fbs = std.io.fixedBufferStream(&abs_buf);
                            const abs_writer = abs_fbs.writer();
                            var prev_was_sep = false;
                            for (pkg_path) |c| {
                                if (c == '/' or c == '\\') {
                                    if (!prev_was_sep) {
                                        abs_writer.writeByte('.') catch break :abs_blk null;
                                        prev_was_sep = true;
                                    }
                                } else {
                                    abs_writer.writeByte(c) catch break :abs_blk null;
                                    prev_was_sep = false;
                                }
                            }
                            // Remove trailing dot if present
                            var written = abs_fbs.getWritten();
                            if (written.len > 0 and written[written.len - 1] == '.') {
                                written = written[0 .. written.len - 1];
                            }
                            // Append submodule name
                            abs_writer.writeByte('.') catch break :abs_blk null;
                            abs_writer.writeAll(submodule_name) catch break :abs_blk null;
                            break :abs_blk abs_fbs.getWritten();
                        }
                        break :abs_blk null;
                    };

                    if (abs_module) |abs_mod| {
                        if (self.isCExtensionModule(abs_mod)) {
                            // C extension - generate runtime binding
                            if (self.mode == .module) try self.emit("pub ");
                            try self.emit("var ");
                            try self.emitIdent(symbol_name);
                            try self.emit(": ?*c_interop.PyObject = null;\n");
                            try generated_symbols.put(symbol_name, {});
                            try self.module_level_from_imports.put(symbol_name, {});
                            // Track for main() initialization
                            const name_copy = try self.arena.allocator().dupe(u8, name);
                            const module_copy = try self.arena.allocator().dupe(u8, abs_mod);
                            try self.c_extension_from_imports.put(symbol_name, .{ .module = module_copy, .attr = name_copy });
                            continue;
                        }
                    }
                    // Unknown submodule - skip
                    continue;
                }
                try generated_symbols.put(symbol_name, {});
                // Track for local variable shadowing prevention
                try self.module_level_from_imports.put(symbol_name, {});
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

        // Handle test.test_grammar module - export underscore literal constants
        if (std.mem.eql(u8, from_imp.module, "test.test_grammar")) {
            for (from_imp.names) |name| {
                if (std.mem.eql(u8, name, "VALID_UNDERSCORE_LITERALS")) {
                    if (!generated_symbols.contains("VALID_UNDERSCORE_LITERALS")) {
                        // Use the slice directly (it's already []const []const u8)
                        try self.emit("const VALID_UNDERSCORE_LITERALS = runtime.test_support.numbers.VALID_UNDERSCORE_LITERALS;\n");
                        try generated_symbols.put("VALID_UNDERSCORE_LITERALS", {});
                    }
                } else if (std.mem.eql(u8, name, "INVALID_UNDERSCORE_LITERALS")) {
                    if (!generated_symbols.contains("INVALID_UNDERSCORE_LITERALS")) {
                        try self.emit("const INVALID_UNDERSCORE_LITERALS = runtime.test_support.numbers.INVALID_UNDERSCORE_LITERALS;\n");
                        try generated_symbols.put("INVALID_UNDERSCORE_LITERALS", {});
                    }
                }
            }
            continue;
        }

        // Handle collections.abc module - expand "from collections.abc import X" or "import *"
        if (std.mem.eql(u8, from_imp.module, "collections.abc")) {
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
                "Buffer",
            };
            for (from_imp.names) |name| {
                if (std.mem.eql(u8, name, "*")) {
                    // Import all ABC types
                    for (abc_exports) |exp_name| {
                        if (generated_symbols.contains(exp_name)) continue;
                        try self.emit("const ");
                        try self.emit(exp_name);
                        try self.emit(" = collections.abc.");
                        try self.emit(exp_name);
                        try self.emit(";\n");
                        try generated_symbols.put(exp_name, {});
                    }
                } else {
                    // Import specific ABC type (e.g., from collections.abc import Coroutine)
                    // Check if name is a known ABC export
                    var is_abc_type = false;
                    for (abc_exports) |exp_name| {
                        if (std.mem.eql(u8, name, exp_name)) {
                            is_abc_type = true;
                            break;
                        }
                    }
                    if (is_abc_type) {
                        if (!generated_symbols.contains(name)) {
                            try self.emit("const ");
                            try self.emit(name);
                            try self.emit(" = collections.abc.");
                            try self.emit(name);
                            try self.emit(";\n");
                            try generated_symbols.put(name, {});
                        }
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

            // Check if root module is already @imported (compiled Python package)
            // e.g., from numpy._core.numerictypes import sctypes
            // If numpy is @imported, we can reference numpy._core.numerictypes.sctypes directly
            const is_imported_submodule = blk: {
                var iter = std.mem.splitScalar(u8, from_imp.module, '.');
                if (iter.next()) |root_module| {
                    // Check if root is in imported_modules (compiled and @imported)
                    if (self.imported_modules.contains(root_module)) {
                        break :blk true;
                    }
                    // Also check import_aliases (e.g., np -> numpy)
                    if (self.import_aliases.contains(root_module)) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            if (is_imported_submodule) {
                // Root module is @imported - generate const symbol = module.path.symbol;
                // e.g., const sctypes = numpy._core.numerictypes.sctypes;

                // First, ensure the full dotted module path is imported
                // emitDottedIdent converts "numpy._core.numerictypes" to @"numpy__core_numerictypes"
                // but this identifier must be imported first
                if (std.mem.indexOfScalar(u8, from_imp.module, '.') != null) {
                    // Convert module path to escaped Zig identifier
                    var escaped_buf: [512]u8 = undefined;
                    var esc_len: usize = 0;
                    for (from_imp.module) |c| {
                        escaped_buf[esc_len] = if (c == '.') '_' else c;
                        esc_len += 1;
                    }
                    const escaped_name = escaped_buf[0..esc_len];

                    // Check if module is in import_registry (uses runtime.Lib.X) or already imported
                    const is_registry_mod = self.import_registry.lookup(from_imp.module) != null;
                    if (!is_registry_mod and !self.imported_modules.contains(escaped_name)) {
                        // Generate @import for the submodule using absolute path
                        // Convert dots to slashes: numpy._core.numerictypes -> numpy/_core/numerictypes.zig
                        var rel_path_buf: [512]u8 = undefined;
                        var rel_len: usize = 0;
                        for (from_imp.module) |c| {
                            rel_path_buf[rel_len] = if (c == '.') '/' else c;
                            rel_len += 1;
                        }
                        const zig_suffix = ".zig";
                        @memcpy(rel_path_buf[rel_len..][0..zig_suffix.len], zig_suffix);
                        rel_len += zig_suffix.len;
                        const rel_path = rel_path_buf[0..rel_len];

                        // Get the gen path: .metal0/gen/{rel_path}
                        const gen_path = build_dirs.zigPathFromRelative(self.allocator, rel_path) catch continue;
                        defer self.allocator.free(gen_path);

                        // Convert to absolute path for reliable imports
                        const abs_path = std.fs.cwd().realpathAlloc(self.allocator, gen_path) catch {
                            // File doesn't exist yet or path error - skip
                            continue;
                        };
                        defer self.allocator.free(abs_path);

                        try self.emit("const @\"");
                        try self.emit(escaped_name);
                        try self.emit("\" = @import(\"");
                        try self.emit(abs_path);
                        try self.emit("\");\n");

                        const esc_copy = try self.arena.allocator().dupe(u8, escaped_name);
                        try self.imported_modules.put(esc_copy, {});
                    }
                }

                for (from_imp.names, 0..) |name, i| {
                    if (std.mem.eql(u8, name, "*")) continue;
                    const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                        from_imp.asnames[i].?
                    else
                        name;
                    if (generated_symbols.contains(symbol_name)) continue;

                    // Convert Python module path to Zig path (dots to underscores for internal modules)
                    // numpy._core.numerictypes -> numpy._core.numerictypes
                    if (self.mode == .module) try self.emit("pub ");
                    try self.emit("const ");
                    try self.emitIdent(symbol_name);
                    try self.emit(" = ");
                    try self.emitDottedIdent(from_imp.module);
                    try self.emit(".");
                    try self.emitIdent(name);
                    try self.emit(";\n");
                    try generated_symbols.put(symbol_name, {});
                    try self.module_level_from_imports.put(symbol_name, {});
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

            // For dotted modules (e.g., numpy._core.numerictypes), we need to ensure the
            // full module path is imported before referencing it.
            // emitDottedIdent converts "numpy._core.numerictypes" to @"numpy__core_numerictypes"
            // but this escaped identifier is never imported - we must import it first.
            //
            // SKIP this for modules already handled by import_registry (they use runtime.Lib.X)
            // Also skip if the module is already in imported_modules
            if (std.mem.indexOfScalar(u8, from_imp.module, '.') != null) {
                // Convert module path to escaped Zig identifier: numpy._core.numerictypes -> numpy__core_numerictypes
                var escaped_name_buf: [512]u8 = undefined;
                var escaped_len: usize = 0;
                for (from_imp.module) |c| {
                    escaped_name_buf[escaped_len] = if (c == '.') '_' else c;
                    escaped_len += 1;
                }
                const escaped_module_name = escaped_name_buf[0..escaped_len];

                // Check if module is handled by import_registry (uses runtime.Lib.X)
                const is_registry_module = self.import_registry.lookup(from_imp.module) != null;

                // Check if this escaped module name is already imported
                if (!is_registry_module and !self.imported_modules.contains(escaped_module_name)) {
                    // Generate @import using absolute path for reliable imports
                    // Convert dots to slashes: numpy._core.numerictypes -> numpy/_core/numerictypes.zig
                    var rel_path_buf: [512]u8 = undefined;
                    var rel_len: usize = 0;
                    for (from_imp.module) |c| {
                        rel_path_buf[rel_len] = if (c == '.') '/' else c;
                        rel_len += 1;
                    }
                    const zig_suffix = ".zig";
                    @memcpy(rel_path_buf[rel_len..][0..zig_suffix.len], zig_suffix);
                    rel_len += zig_suffix.len;
                    const rel_path = rel_path_buf[0..rel_len];

                    // Get the gen path: .metal0/gen/{rel_path}
                    const gen_path = build_dirs.zigPathFromRelative(self.allocator, rel_path) catch continue;
                    defer self.allocator.free(gen_path);

                    // Convert to absolute path for reliable imports
                    const abs_path = std.fs.cwd().realpathAlloc(self.allocator, gen_path) catch {
                        // File doesn't exist yet or path error - skip
                        continue;
                    };
                    defer self.allocator.free(abs_path);

                    try self.emit("const @\"");
                    try self.emit(escaped_module_name);
                    try self.emit("\" = @import(\"");
                    try self.emit(abs_path);
                    try self.emit("\");\n");

                    // Track this module as imported to avoid duplicates
                    const escaped_copy = try self.arena.allocator().dupe(u8, escaped_module_name);
                    try self.imported_modules.put(escaped_copy, {});
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
