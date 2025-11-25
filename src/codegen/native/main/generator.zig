/// Main code generation functions
const std = @import("std");
const ast = @import("../../../ast.zig");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const CodegenError = core.CodegenError;
const imports = @import("imports.zig");
const from_imports_gen = @import("from_imports.zig");
const analyzer = @import("../analyzer.zig");
const statements = @import("../statements.zig");
const expressions = @import("../expressions.zig");
const import_resolver = @import("../../../import_resolver.zig");

// Comptime constants for code generation (zero runtime cost)
const BUILD_DIR = ".build";
const MODULE_EXT = ".zig";
const IMPORT_PREFIX = "./";
const MAIN_NAME = "__main__";

/// Generate native Zig code for module
pub fn generate(self: *NativeCodegen, module: ast.Node.Module) ![]const u8 {
    // PHASE 1: Analyze module to determine requirements
    const analysis = try analyzer.analyzeModule(module, self.allocator);
    defer if (analysis.global_vars.len > 0) self.allocator.free(analysis.global_vars);

    // PHASE 1.5: Get source file directory for import resolution
    const source_file_dir = if (self.source_file_path) |path|
        try import_resolver.getFileDirectory(path, self.allocator)
    else
        null;
    defer if (source_file_dir) |dir| self.allocator.free(dir);

    // PHASE 1.6: Collect imports and compile imported modules as inlined structs
    var imported_modules = try imports.collectImports(self, module, source_file_dir);
    defer imported_modules.deinit(self.allocator);

    // Store compiled module structs for later emission
    var inlined_modules = std.ArrayList([]const u8){};
    defer {
        for (inlined_modules.items) |code| self.allocator.free(code);
        inlined_modules.deinit(self.allocator);
    }

    // Generate @import() statements for compiled modules
    for (imported_modules.items) |mod_name| {
        // Skip if external module (no .build/ file)
        const import_path = try std.fmt.allocPrint(self.allocator, IMPORT_PREFIX ++ "{s}" ++ MODULE_EXT, .{mod_name});
        defer self.allocator.free(import_path);

        // Check if module was compiled to .build/ (uses comptime constants)
        const build_path = try std.fmt.allocPrint(self.allocator, BUILD_DIR ++ "/{s}" ++ MODULE_EXT, .{mod_name});
        defer self.allocator.free(build_path);

        std.fs.cwd().access(build_path, .{}) catch {
            // Module not in .build/, skip it
            continue;
        };

        // Generate import statement
        const import_stmt = try std.fmt.allocPrint(
            self.allocator,
            "const {s} = @import(\"{s}\");\n",
            .{ mod_name, import_path }
        );
        try inlined_modules.append(self.allocator, import_stmt);
    }

    // PHASE 2: Register all classes for inheritance support
    for (module.body) |stmt| {
        if (stmt == .class_def) {
            try self.class_registry.registerClass(stmt.class_def.name, stmt.class_def);
        }
    }

    // PHASE 2.1: Register async functions for comptime optimization analysis
    for (module.body) |stmt| {
        if (stmt == .function_def) {
            const func = stmt.function_def;
            if (func.is_async) {
                const func_name_copy = try self.allocator.dupe(u8, func.name);
                try self.async_function_defs.put(func_name_copy, func);
            }
        }
    }

    // PHASE 2.5: Analyze mutations for list ArrayList vs fixed array decision
    const mutation_analyzer = @import("../../../analysis/native_types/mutation_analyzer.zig");
    var mutations = try mutation_analyzer.analyzeMutations(module, self.allocator);
    defer {
        for (mutations.values()) |*info| {
            @constCast(info).mutation_types.deinit(self.allocator);
        }
        mutations.deinit();
    }
    self.mutation_info = &mutations;

    // PHASE 3: Generate imports based on analysis (minimal for smaller WASM)
    // Check if any imported modules require runtime
    var needs_runtime_for_imports = false;
    for (imported_modules.items) |mod_name| {
        if (self.import_registry.lookup(mod_name)) |info| {
            if (info.strategy == .zig_runtime) {
                needs_runtime_for_imports = true;
                break;
            }
        }
    }

    // Always import std and runtime - DCE removes if unused
    try self.emit("const std = @import(\"std\");\n");
    try self.emit("const runtime = @import(\"./runtime.zig\");\n");
    if (analysis.needs_string_utils) {
        try self.emit("const string_utils = @import(\"string_utils.zig\");\n");
    }
    if (analysis.needs_hashmap_helper) {
        try self.emit("const hashmap_helper = @import(\"./utils/hashmap_helper.zig\");\n");
    }
    if (analysis.needs_allocator) {
        try self.emit("const allocator_helper = @import(\"./utils/allocator_helper.zig\");\n");
    }

    // PHASE 3.5: Generate C library imports (if any detected)
    if (self.import_ctx) |ctx| {
        const c_import_block = try ctx.generateCImportBlock(self.allocator);
        defer self.allocator.free(c_import_block);
        if (c_import_block.len > 0) {
            try self.emit(c_import_block);
        }
    }

    // PHASE 3.7: Emit inlined module structs
    // For user modules and third-party packages, inline as structs
    // For PyAOT runtime modules, use registry imports
    for (imported_modules.items, 0..) |mod_name, i| {
        // Track this module name for call site handling
        const mod_copy = try self.allocator.dupe(u8, mod_name);
        try self.imported_modules.put(mod_copy, {});

        // Look up module in registry
        if (self.import_registry.lookup(mod_name)) |info| {
            switch (info.strategy) {
                .zig_runtime, .c_library => {
                    // Use Zig import from registry (not inlined)
                    try self.emit("const ");
                    try self.emit(mod_name);
                    try self.emit(" = ");
                    if (info.zig_import) |zig_import| {
                        try self.emit(zig_import);
                    } else {
                        try self.emit("struct {}; // TODO: ");
                        try self.emit(mod_name);
                        try self.emit(" not implemented");
                    }
                    try self.emit(";\n");
                },
                .compile_python, .unsupported => {
                    // Emit inlined struct code
                    if (i < inlined_modules.items.len) {
                        try self.emit(inlined_modules.items[i]);
                    }
                },
            }
        } else {
            // User module - emit inlined struct
            if (i < inlined_modules.items.len) {
                try self.emit(inlined_modules.items[i]);
            }
        }
    }

    try self.emit("\n");

    // PHASE 3.6: Generate from-import symbol re-exports
    try from_imports_gen.generateFromImports(self);

    // PHASE 4: Define __name__ constant (for if __name__ == "__main__" support)
    try self.emit("const __name__ = \"__main__\";\n\n");

    // PHASE 4.1: Emit source directory for runtime eval subprocess
    // This allows eval() to spawn pyaot subprocess with correct import paths
    if (source_file_dir) |dir| {
        try self.emit("// PyAOT metadata for runtime eval subprocess\n");
        try self.emit("pub const __pyaot_source_dir: []const u8 = \"");
        // Escape any special characters in the path
        for (dir) |c| {
            if (c == '\\') {
                try self.emit("\\\\");
            } else if (c == '"') {
                try self.emit("\\\"");
            } else {
                try self.output.append(self.allocator, c);
            }
        }
        try self.emit("\";\n\n");
    }

    // PHASE 5: Generate imports, class and function definitions (before main)
    // In module mode, wrap functions in pub struct
    if (self.mode == .module) {
        if (self.module_name) |mod_name| {
            try self.emit("pub const ");
            try self.emit(mod_name);
            try self.emit(" = struct {\n");
            self.indent();
        }
    }

    for (module.body) |stmt| {
        if (stmt == .import_stmt) {
            try statements.genImport(self, stmt.import_stmt);
        } else if (stmt == .import_from) {
            try statements.genImportFrom(self, stmt.import_from);
        } else if (stmt == .class_def) {
            try statements.genClassDef(self, stmt.class_def);
            try self.emit("\n");
        } else if (stmt == .function_def) {
            if (self.mode == .module) {
                // In module mode, make functions pub
                try self.emitIndent();
                try self.emit("pub ");
            }
            try statements.genFunctionDef(self, stmt.function_def);
            try self.emit("\n");
        } else if (stmt == .assign) {
            if (self.mode == .module) {
                // In module mode, export constants as pub const
                try self.emitIndent();
                try self.emit("pub const ");
                // Generate target name
                for (stmt.assign.targets, 0..) |target, i| {
                    if (target == .name) {
                        try self.emit(target.name.id);
                    }
                    if (i < stmt.assign.targets.len - 1) {
                        try self.emit(", ");
                    }
                }
                try self.emit(" = ");
                try expressions.genExpr(self, stmt.assign.value.*);
                try self.emit(";\n");
            }
        }
    }

    // Close module struct (only if we opened one)
    if (self.mode == .module) {
        if (self.module_name != null) {
            self.dedent();
            try self.emit("};\n");
        }
        // Module mode doesn't generate main, just return
        return self.output.toOwnedSlice(self.allocator);
    }

    // PHASE 5.5: Generate module-level allocator (only if needed)
    if (analysis.needs_allocator) {
        try self.emit("\n// Module-level allocator for async functions and f-strings\n");
        try self.emit("// Debug/WASM: GPA instance (release uses c_allocator, no instance needed)\n");
        try self.emit("var __gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};\n");
        try self.emit("var __global_allocator: std.mem.Allocator = undefined;\n");
        try self.emit("var __allocator_initialized: bool = false;\n\n");
    }

    // PHASE 5.6: Generate module-level global variables (for 'global' keyword support)
    if (analysis.global_vars.len > 0) {
        try self.emit("\n// Module-level variables declared with 'global' keyword\n");
        for (analysis.global_vars) |var_name| {
            // Get type from type inferrer, default to i64 for integers
            const var_type = self.type_inferrer.var_types.get(var_name);
            const zig_type = if (var_type) |vt| blk: {
                break :blk try self.nativeTypeToZigType(vt);
            } else "i64";
            defer if (var_type != null) self.allocator.free(zig_type);

            try self.emit("var ");
            try self.emit(var_name);
            try self.emit(": ");
            try self.emit(zig_type);
            try self.emit(" = undefined;\n");

            // Mark these as declared at module level (scope 0)
            try self.symbol_table.declare(var_name, var_type orelse .int, true);

            // Also track them as global vars in codegen for assignment handling
            try self.markGlobalVar(var_name);
        }
        try self.emit("\n");
    }

    // PHASE 6: Generate main function (script mode only)
    // For WASM: Zig's std.start automatically exports _start if pub fn main exists
    try self.emit("pub fn main() ");
    // Main returns !void if allocator or runtime is used (runtime functions can fail)
    if (analysis.needs_allocator or analysis.needs_runtime) {
        try self.emit("!void {\n");
    } else {
        try self.emit("void {\n");
    }
    self.indent();

    // Setup allocator only if needed (skip for pure functions - smaller WASM)
    // Strategy: c_allocator in release (fast, OS cleanup), GPA in debug/WASM (safe)
    if (analysis.needs_allocator) {
        try self.emitIndent();
        try self.emit("const allocator = blk: {\n");
        try self.emitIndent();
        try self.emit("    if (comptime allocator_helper.useFastAllocator()) {\n");
        try self.emitIndent();
        try self.emit("        // Release mode: use c_allocator, OS reclaims at exit\n");
        try self.emitIndent();
        try self.emit("        break :blk std.heap.c_allocator;\n");
        try self.emitIndent();
        try self.emit("    } else {\n");
        try self.emitIndent();
        try self.emit("        // Debug/WASM: use GPA for leak detection\n");
        try self.emitIndent();
        try self.emit("        break :blk __gpa.allocator();\n");
        try self.emitIndent();
        try self.emit("    }\n");
        try self.emitIndent();
        try self.emit("};\n\n");

        // Initialize module-level allocator
        try self.emitIndent();
        try self.emit("__global_allocator = allocator;\n");
        try self.emitIndent();
        try self.emit("__allocator_initialized = true;\n");
        try self.emit("\n");
    }

    // PHASE 6.5: Apply decorators (after allocator, before other code)
    // This allows decorators to run after variables are defined but before main logic
    if (self.decorated_functions.items.len > 0) {
        try self.emitIndent();
        try self.emit("// Apply decorators\n");
        for (self.decorated_functions.items) |decorated_func| {
            for (decorated_func.decorators) |decorator| {
                try self.emitIndent();
                try self.emit("_ = ");
                try self.genExpr(decorator);
                try self.emit("(&");
                try self.emit(decorated_func.name);
                try self.emit(");\n");
            }
        }
        try self.emit("\n");
    }

    // PHASE 7: Generate statements (skip class/function defs and imports - already handled)
    // This will populate self.lambda_functions
    for (module.body) |stmt| {
        if (stmt != .function_def and stmt != .class_def and stmt != .import_stmt and stmt != .import_from) {
            try self.generateStmt(stmt);
        }
    }

    // If user defined main(), call it (but not for async main - user calls via asyncio.run)
    if (analysis.has_user_main and !analysis.has_async_user_main) {
        try self.emitIndent();
        try self.emit("__user_main();\n");
    }

    self.dedent();
    try self.emit("}\n");

    // PHASE 8: Prepend lambda functions if any were generated
    if (self.lambda_functions.items.len > 0) {
        // Get current output
        const current_output = try self.output.toOwnedSlice(self.allocator);
        defer self.allocator.free(current_output);

        // Rebuild output with lambdas first
        self.output = std.ArrayList(u8){};

        // Add imports
        try self.emit("const std = @import(\"std\");\n");
        try self.emit("const runtime = @import(\"./runtime.zig\");\n");
        if (analysis.needs_string_utils) {
            try self.emit("const string_utils = @import(\"string_utils.zig\");\n");
        }
        if (analysis.needs_hashmap_helper) {
            try self.emit("const hashmap_helper = @import(\"./utils/hashmap_helper.zig\");\n");
        }
        try self.emit("\n");

        // Add __name__ constant
        try self.emit("const __name__ = \"__main__\";\n\n");

        // Add lambda functions
        for (self.lambda_functions.items) |lambda_code| {
            try self.output.appendSlice(self.allocator, lambda_code);
        }

        // Find where class/function definitions start (after first two const declarations)
        // Parse current_output to extract everything after imports and __name__
        var lines = std.mem.splitScalar(u8, current_output, '\n');
        var skip_count: usize = 0;
        while (lines.next()) |line| {
            skip_count += 1;
            if (std.mem.indexOf(u8, line, "const __name__") != null) {
                // Skip this line and the blank line after
                _ = lines.next(); // blank line
                skip_count += 1;
                break;
            }
        }

        // Append the rest of the original output (class/func defs + main)
        var lines2 = std.mem.splitScalar(u8, current_output, '\n');
        var i: usize = 0;
        while (lines2.next()) |line| : (i += 1) {
            if (i >= skip_count) {
                try self.output.appendSlice(self.allocator, line);
                try self.output.appendSlice(self.allocator, "\n");
            }
        }
    }

    return self.output.toOwnedSlice(self.allocator);
}

pub fn generateStmt(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    switch (node) {
        .assign => |assign| try statements.genAssign(self, assign),
        .ann_assign => |ann_assign| try statements.genAnnAssign(self, ann_assign),
        .aug_assign => |aug| try statements.genAugAssign(self, aug),
        .expr_stmt => |expr| try statements.genExprStmt(self, expr.value.*),
        .if_stmt => |if_stmt| try statements.genIf(self, if_stmt),
        .while_stmt => |while_stmt| try statements.genWhile(self, while_stmt),
        .for_stmt => |for_stmt| try statements.genFor(self, for_stmt),
        .return_stmt => |ret| try statements.genReturn(self, ret),
        .assert_stmt => |assert_node| try statements.genAssert(self, assert_node),
        .try_stmt => |try_node| try statements.genTry(self, try_node),
        .raise_stmt => |raise_node| try statements.genRaise(self, raise_node),
        .class_def => |class| try statements.genClassDef(self, class),
        .function_def => |func| {
            // Only use nested function generation for truly nested functions
            if (func.is_nested) {
                try statements.genNestedFunctionDef(self, func);
            } else {
                // Top-level functions use regular generation
                try statements.genFunctionDef(self, func);
            }
        },
        .import_stmt => |import| try statements.genImport(self, import),
        .import_from => |import| try statements.genImportFrom(self, import),
        .pass => try statements.genPass(self),
        .break_stmt => try statements.genBreak(self),
        .continue_stmt => try statements.genContinue(self),
        .global_stmt => |global| try statements.genGlobal(self, global),
        .del_stmt => |del| try statements.genDel(self, del),
        else => {},
    }
}

// Expression generation delegated to expressions.zig
pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    try expressions.genExpr(self, node);
}
