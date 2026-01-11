/// Import statement code generation (import, from-import)
const std = @import("std");
const ast = @import("analysis.ast");
const zig_keywords = @import("utils.zig_keywords");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;

/// Known runtime class types that need .init() instantiation instead of .call()
/// Maps module name -> class name -> true
const KNOWN_CLASS_TYPES = .{
    .{ "fractions", &[_][]const u8{"Fraction"} },
    .{ "decimal", &[_][]const u8{"Decimal"} },
    .{ "datetime", &[_][]const u8{ "datetime", "date", "time", "timedelta" } },
    .{ "pathlib", &[_][]const u8{ "Path", "PurePath", "PosixPath", "WindowsPath" } },
    .{ "collections", &[_][]const u8{ "Counter", "OrderedDict", "ChainMap", "defaultdict" } },
    .{ "re", &[_][]const u8{"Pattern"} },
};

/// Check if a module.name combination is a known class type needing .init()
pub fn isKnownClassType(module_name: []const u8, name: []const u8) bool {
    inline for (KNOWN_CLASS_TYPES) |entry| {
        if (std.mem.eql(u8, module_name, entry[0])) {
            const class_names: []const []const u8 = entry[1];
            for (class_names) |class_name| {
                if (std.mem.eql(u8, name, class_name)) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Generate import statement: import module
/// For module-level imports, this is handled in PHASE 3
/// For local imports (inside functions), we need to generate const bindings
pub fn genImport(self: *NativeCodegen, import: ast.Node.Import) CodegenError!void {
    const module_name = import.module;
    const alias = import.asname orelse module_name;

    // Special handling for 'builtins' module
    // Python's builtins module provides access to built-in functions (len, str, int, etc.)
    // These are available via runtime.builtins - generate const binding for value access
    // Dispatch handles builtins.func() calls directly, but code may also access builtins.__dict__ etc.
    // Module-level builtins import is handled in generator.zig Phase 3
    if (std.mem.eql(u8, module_name, "builtins")) {
        // Skip module-level imports (handled in Phase 3)
        if (self.indent_level == 0) return;
        if (self.mode == .module and self.indent_level == 1) return;
        // For local imports inside functions, generate the const binding
        const b = try self.getBuilder();
        try b.writeIndent();
        try b.writeFmt("const {s} = runtime.builtins;\n", .{alias});
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Check if module was marked as unavailable (e.g., winreg on Mac)
    // Use VM fallback to import at runtime - drop-in CPython replacement
    // dispatch.zig handles calls to skipped modules via VM fallback
    if (self.isSkippedModule(module_name)) {
        // Skip import generation - dispatch.zig will use VM fallback for any access
        // Track the alias so dispatch knows it maps to the skipped module
        if (!std.mem.eql(u8, alias, module_name)) {
            const alias_copy = try self.allocator.dupe(u8, alias);
            try self.import_aliases.put(alias_copy, module_name);
        }
        return;
    }

    // Only generate for local imports (inside functions)
    // Module-level imports are handled in PHASE 3 of generator.zig
    // In module mode, indent_level == 1 means we're at struct level (still module-level)
    // UNLESS we're inside a function (current_function_name is set)
    if (self.indent_level == 0) return;
    if (self.mode == .module and self.indent_level == 1 and self.current_function_name == null) return;

    // Look up in registry
    if (self.import_registry.lookup(module_name)) |info| {
        // Check if already imported at module level before we add it again
        // This avoids shadowing errors when the same import appears both at module level and locally
        const already_imported = self.imported_modules.contains(alias);

        // Prefer direct_import for DCE-friendly imports, fallback to zig_import
        const import_path = info.direct_import orelse info.zig_import;
        if (import_path) |path| {
            // Check if already declared at module level (avoids shadowing error)
            // This happens when the same import appears both at module level and locally
            // Check all possible sources of module-level declarations:
            // - isDeclared: hoisted_vars, var_renames, symbol_table
            // - module_level_from_imports: from X import Y symbols
            // - already_imported: import X statements (e.g., import ctypes)
            if (self.isDeclared(alias) or self.module_level_from_imports.contains(alias) or already_imported) {
                return;
            }

            // Track as imported ONLY if we're actually emitting code
            // (moved from before skip check to avoid adding to map when skipping)
            const alias_copy = try self.allocator.dupe(u8, alias);
            try self.imported_modules.put(alias_copy, {});

            const b = try self.getBuilder();
            try b.writeIndent();
            try b.emitRaw("const ");
            try zig_keywords.writeEscapedIdent(b.body.writer(self.allocator), alias);
            try b.emitRaw(" = ");
            try b.emitRaw(path);
            try b.emitRaw(";\n");
            // Emit discard to suppress "unused local constant" warning
            try b.writeIndent();
            try b.emitRaw("_ = &");
            try zig_keywords.writeEscapedIdent(b.body.writer(self.allocator), alias);
            try b.emitRaw(";\n");

            // Register in symbol table so subsequent shadowing checks work
            try self.declareVar(alias);

            const output = try b.getBodyDupe();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        // Module not in registry - use VM fallback for dynamic import
        // This handles frozen modules (__phello__, etc.) and other dynamic imports
        // import foo.bar.baz as spam -> spam = eval("import foo.bar.baz; foo.bar.baz")

        // Check if already declared at module level (avoids shadowing error)
        // This happens when numpy is @imported at module level, then code does:
        // numpy = eval("import numpy; numpy") inside a function
        const already_imported = self.imported_modules.contains(alias);
        if (self.isDeclared(alias) or self.module_level_from_imports.contains(alias) or already_imported) {
            return;
        }

        const b = try self.getBuilder();
        try b.writeIndent();
        // Check if variable was hoisted (e.g., for imports inside with blocks)
        // Hoisted variables use assignment, non-hoisted use const declaration
        const was_hoisted = self.hoisted_vars.contains(alias);
        if (!was_hoisted) {
            try b.emitRaw("const ");
        }
        try zig_keywords.writeEscapedIdent(b.body.writer(self.allocator), alias);
        // Generate eval that imports and returns the module
        // Use the last part of the module path as the value to return
        // At module level, can't use try - must use catch unreachable
        const at_mod_level = self.current_function_name == null;
        if (at_mod_level) {
            try b.writeFmt(" = (runtime.PyValue.from(runtime.eval(__global_allocator, \"import {s}; {s}\") catch unreachable));\n", .{ module_name, module_name });
        } else {
            try b.writeFmt(" = runtime.PyValue.from(try runtime.eval(__global_allocator, \"import {s}; {s}\"));\n", .{ module_name, module_name });
        }
        // Emit discard to suppress "unused local constant" warning for non-hoisted imports
        // Hoisted variables are used elsewhere (outside the block), so no discard needed
        // But NOT at module level - statements can't be at struct level
        if (!was_hoisted and !at_mod_level) {
            try b.writeIndent();
            try b.emitRaw("_ = &");
            try zig_keywords.writeEscapedIdent(b.body.writer(self.allocator), alias);
            try b.emitRaw(";\n");
        }

        // Register in symbol table so subsequent shadowing checks work
        if (!was_hoisted) {
            try self.declareVar(alias);
        }

        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate from-import statement: from module import names
/// Module-level imports are handled in PHASE 3 of generator.zig
/// Local imports (inside functions) need to generate const bindings
pub fn genImportFrom(self: *NativeCodegen, import: ast.Node.ImportFrom) CodegenError!void {
    const module_name = import.module;

    // Track known class types that need .init() instantiation
    // This must happen for ALL imports (module-level and local)
    for (import.names, 0..) |name, i| {
        const name_alias = if (i < import.asnames.len and import.asnames[i] != null)
            import.asnames[i].?
        else
            name;

        if (isKnownClassType(module_name, name_alias) or isKnownClassType(module_name, name)) {
            try self.imported_class_types.put(name_alias, {});
        }
    }

    // Check if module was marked as unavailable (e.g., winreg on Mac)
    // Use VM fallback to import at runtime - drop-in CPython replacement
    // Track imported names for dispatch.zig to handle via VM fallback
    if (self.isSkippedModule(module_name)) {
        // Track each imported name as coming from the skipped module
        // dispatch.zig will use VM fallback for any access
        for (import.names, 0..) |name, i| {
            const name_alias = if (i < import.asnames.len and import.asnames[i] != null)
                import.asnames[i].?
            else
                name;

            // Track as local from-import so dispatch can route to VM fallback
            try self.local_from_imports.put(name_alias, module_name);
        }
        return;
    }

    // Only generate for local imports (inside functions)
    // Module-level imports are handled in PHASE 3
    if (self.indent_level == 0) return;
    if (self.mode == .module and self.indent_level == 1) return;

    // Look up in registry to get the Zig module path
    if (self.import_registry.lookup(module_name)) |info| {
        // Prefer direct_import for DCE-friendly imports, fallback to zig_import
        const import_path = info.direct_import orelse info.zig_import;
        if (import_path) |path| {
            const b = try self.getBuilder();

            // Generate const bindings for each imported name
            // from random import getrandbits -> const getrandbits = runtime.random.getrandbits;
            for (import.names, 0..) |name, i| {
                const alias = if (i < import.asnames.len and import.asnames[i] != null)
                    import.asnames[i].?
                else
                    name;

                // Check if this variable was hoisted due to scope escape
                // (e.g., import inside if/else that's used after the block)
                const is_hoisted = self.varResolutionIsHoisted(alias);

                // Skip if already declared (but not hoisted) in current scope (avoids shadowing error)
                // Check:
                // 1. isDeclared - hoisted vars, symbol table
                // 2. module_level_from_imports - module-level from X import Y bindings
                // For local imports inside functions that duplicate module-level imports
                // (e.g., "from test.support import import_helper" in both module and function),
                // skip generating the local const to avoid shadowing.
                // BUT: if the variable is hoisted, we need to generate an assignment to it
                if (!is_hoisted and (self.isDeclared(alias) or self.module_level_from_imports.contains(alias))) {
                    continue;
                }

                // Escape Zig keywords like c_int, c_char, etc.
                const escaped_alias = try zig_keywords.escapeIfKeyword(self.allocator, alias);
                try b.writeIndent();

                if (is_hoisted) {
                    // For hoisted variables, generate assignment not declaration
                    // func = runtime.math.sqrt;
                    try b.emitRaw(escaped_alias);
                    try b.emitRaw(" = runtime.PyValue.from(");
                    try b.emitRaw(path);
                    try b.emitRaw(".");
                    try b.emitRaw(name);
                    try b.emitRaw(");\n");
                } else {
                    // Normal case: generate const declaration
                    try b.emitRaw("const ");
                    try b.emitRaw(escaped_alias);
                    try b.emitRaw(" = ");
                    try b.emitRaw(path);
                    try b.emitRaw(".");
                    try b.emitRaw(name);
                    try b.emitRaw(";\n");
                    // Emit discard immediately to suppress "unused constant" error
                    // Local from-imports may not be used if they're only for type hints
                    try b.writeIndent();
                    try b.emitRaw("_ = &");
                    try b.emitRaw(escaped_alias);
                    try b.emitRaw(";\n");

                    // Register in symbol table so subsequent shadowing checks work
                    try self.declareVar(alias);
                }
            }

            const output = try b.getBodyDupe();
            try self.output.appendSlice(self.allocator, output);
        } else {
            // Module uses inline codegen (e.g., random) - track symbols for dispatch
            // from random import getrandbits -> record "getrandbits" -> "random"
            for (import.names, 0..) |name, i| {
                const alias = if (i < import.asnames.len and import.asnames[i] != null)
                    import.asnames[i].?
                else
                    name;

                try self.local_from_imports.put(alias, module_name);
            }
        }
    } else {
        // Module not in registry - use VM fallback for dynamic import
        // This handles external packages like numpy submodules (numpy.lib._stride_tricks_impl)
        // Generate: const name = runtime.PyValue.from(try runtime.eval("from module import name; name"))
        const b = try self.getBuilder();

        for (import.names, 0..) |name, i| {
            // Skip star imports - they can't be represented as a single const
            if (std.mem.eql(u8, name, "*")) {
                continue;
            }

            const alias = if (i < import.asnames.len and import.asnames[i] != null)
                import.asnames[i].?
            else
                name;

            // Check if variable was hoisted (e.g., for imports inside if/else or try blocks)
            const was_hoisted = self.hoisted_vars.contains(alias);

            // Skip if already declared (but not hoisted) in current scope or at module level
            // If hoisted, we need to generate an assignment to the hoisted variable
            // Also check imported_modules for shadowing against @imported modules
            if (!was_hoisted and (self.isDeclared(alias) or self.module_level_from_imports.contains(alias) or self.imported_modules.contains(alias))) {
                continue;
            }
            try b.writeIndent();
            if (!was_hoisted) {
                try b.emitRaw("const ");
            }
            try zig_keywords.writeEscapedIdent(b.body.writer(self.allocator), alias);
            // At module level, can't use try - must use catch unreachable
            const at_mod_level = self.current_function_name == null;
            if (at_mod_level) {
                try b.writeFmt(" = (runtime.PyValue.from(runtime.eval(__global_allocator, \"from {s} import {s}; {s}\") catch unreachable));\n", .{ module_name, name, name });
            } else {
                try b.writeFmt(" = runtime.PyValue.from(try runtime.eval(__global_allocator, \"from {s} import {s}; {s}\"));\n", .{ module_name, name, name });
            }

            // Emit discard to suppress "unused local constant" warning
            // But NOT at module level - statements can't be at struct level
            if (!was_hoisted and !at_mod_level) {
                try b.writeIndent();
                try b.emitRaw("_ = &");
                try zig_keywords.writeEscapedIdent(b.body.writer(self.allocator), alias);
                try b.emitRaw(";\n");
            }

            // Register in symbol table so subsequent shadowing checks work
            // (e.g., for loop variables with same name as import alias)
            if (!was_hoisted) {
                try self.declareVar(alias);
            }

            // Track as local from-import for dispatch
            try self.local_from_imports.put(alias, module_name);
        }

        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
    }
}
