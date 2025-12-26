/// Import statement code generation (import, from-import)
const std = @import("std");
const ast = @import("analysis.ast");
const zig_keywords = @import("utils.zig_keywords");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;

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
        const output = b.getBodyAndClear();
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
    if (self.indent_level == 0) return;
    if (self.mode == .module and self.indent_level == 1) return;

    // Look up in registry
    if (self.import_registry.lookup(module_name)) |info| {
        // Skip generating local import if the module is a well-known module
        // that's typically imported at module level - Python allows redundant imports
        // but Zig doesn't allow shadowing
        // Note: This is a heuristic - we skip stdlib modules since they're usually
        // imported at module level and would cause shadowing errors
        if (info.strategy == .zig_runtime) {
            return;
        }

        // Prefer direct_import for DCE-friendly imports, fallback to zig_import
        const import_path = info.direct_import orelse info.zig_import;
        if (import_path) |path| {
            const b = try self.getBuilder();
            try b.writeIndent();
            try b.write("const ");
            try zig_keywords.writeEscapedIdent(b.body.writer(self.allocator), alias);
            try b.write(" = ");
            try b.write(path);
            try b.write(";\n");

            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        // Module not in registry - use VM fallback for dynamic import
        // This handles frozen modules (__phello__, etc.) and other dynamic imports
        // import foo.bar.baz as spam -> spam = eval("import foo.bar.baz; foo.bar.baz")
        const b = try self.getBuilder();
        try b.writeIndent();
        // Check if variable was hoisted (e.g., for imports inside with blocks)
        // Hoisted variables use assignment, non-hoisted use const declaration
        const was_hoisted = self.hoisted_vars.contains(alias);
        if (!was_hoisted) {
            try b.write("const ");
        }
        try zig_keywords.writeEscapedIdent(b.body.writer(self.allocator), alias);
        // Generate eval that imports and returns the module
        // Use the last part of the module path as the value to return
        try b.writeFmt(" = runtime.PyValue.from(try runtime.eval(__global_allocator, \"import {s}; {s}\"));\n", .{ module_name, module_name });
        // Emit discard to suppress "unused local constant" warning for non-hoisted imports
        // Hoisted variables are used elsewhere (outside the block), so no discard needed
        if (!was_hoisted) {
            try b.writeIndent();
            try b.write("_ = &");
            try zig_keywords.writeEscapedIdent(b.body.writer(self.allocator), alias);
            try b.write(";\n");
        }

        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate from-import statement: from module import names
/// Module-level imports are handled in PHASE 3 of generator.zig
/// Local imports (inside functions) need to generate const bindings
pub fn genImportFrom(self: *NativeCodegen, import: ast.Node.ImportFrom) CodegenError!void {
    const module_name = import.module;

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

                // Skip if already declared at module level (avoids shadowing error)
                // This happens when the same import appears both at module level and locally
                if (self.isDeclared(alias) or self.module_level_from_imports.contains(alias)) {
                    continue;
                }

                try b.writeIndent();
                try b.write("const ");
                try b.write(alias);
                try b.write(" = ");
                try b.write(path);
                try b.write(".");
                try b.write(name);
                try b.write(";\n");
                // Emit discard immediately to suppress "unused constant" error
                // Local from-imports may not be used if they're only for type hints
                try b.writeIndent();
                try b.write("_ = &");
                try b.write(alias);
                try b.write(";\n");
            }

            const output = b.getBodyAndClear();
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
    }
}
