/// Main code generation functions
const std = @import("std");
const ast = @import("../../../ast.zig");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const CodegenError = core.CodegenError;
const imports = @import("imports.zig");
const analyzer = @import("../analyzer.zig");
const statements = @import("../statements.zig");
const expressions = @import("../expressions.zig");
const import_resolver = @import("../../../import_resolver.zig");

/// Generate native Zig code for module
pub fn generate(self: *NativeCodegen, module: ast.Node.Module) ![]const u8 {
    // PHASE 1: Analyze module to determine requirements
    const analysis = try analyzer.analyzeModule(module, self.allocator);

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

    // Compile each imported module as struct
    for (imported_modules.items) |mod_name| {
        const struct_code: []const u8 = imports.compileModuleAsStruct(
            mod_name,
            source_file_dir,
            self.allocator,
            self.type_inferrer
        ) catch {
            // Module compilation failed - likely external package, skip it
            continue;
        };
        try inlined_modules.append(self.allocator, struct_code);
    }

    // PHASE 2: Register all classes for inheritance support
    for (module.body) |stmt| {
        if (stmt == .class_def) {
            try self.class_registry.registerClass(stmt.class_def.name, stmt.class_def);
        }
    }

    // PHASE 2.5: Analyze mutations for list ArrayList vs fixed array decision
    const mutation_analyzer = @import("../../../analysis/native_types/mutation_analyzer.zig");
    var mutations = try mutation_analyzer.analyzeMutations(module, self.allocator);
    defer {
        var iter = mutations.valueIterator();
        while (iter.next()) |info| {
            @constCast(info).mutation_types.deinit(self.allocator);
        }
        mutations.deinit();
    }
    self.mutation_info = &mutations;

    // PHASE 3: Generate imports based on analysis
    try self.emit("const std = @import(\"std\");\n");
    // Always import runtime for formatAny() and other utilities
    try self.emit("const runtime = @import(\"./runtime.zig\");\n");
    if (analysis.needs_string_utils) {
        try self.emit("const string_utils = @import(\"string_utils.zig\");\n");
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
    // For "from json import loads", generate: const loads = json.loads;
    for (self.from_imports.items) |from_imp| {
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
                std.debug.print("Warning: 'from {s} import *' not supported yet\n", .{from_imp.module});
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
                    try self.emit("    const json_str_obj = try runtime.PyString.create(allocator, json_str);\n");
                    try self.emit("    defer runtime.decref(json_str_obj, allocator);\n");
                    try self.emit("    return try runtime.json.loads(json_str_obj, allocator);\n");
                    try self.emit("}\n");
                    continue; // Skip const generation for this one
                }
            }

            // Generate: const symbol_name = module.name;
            try self.emit("const ");
            try self.emit(symbol_name);
            try self.emit(" = ");
            try self.emit(from_imp.module);
            try self.emit(".");
            try self.emit(name);
            try self.emit(";\n");
        }
    }

    if (self.from_imports.items.len > 0) {
        try self.emit("\n");
    }

    // PHASE 4: Define __name__ constant (for if __name__ == "__main__" support)
    try self.emit("const __name__ = \"__main__\";\n\n");

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

    // PHASE 6: Generate main function (script mode only)
    try self.emit("pub fn main() !void {\n");
    self.indent();

    // Setup allocator (always available for float formatting in print)
    try self.emitIndent();
    try self.emit("var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){};\n");
    try self.emitIndent();
    try self.emit("defer _ = gpa.deinit();\n");
    try self.emitIndent();
    try self.emit("var allocator = gpa.allocator();\n");  // var instead of const so we can take address
    try self.emitIndent();
    try self.emit("std.mem.doNotOptimizeAway(&allocator);\n");  // Suppress unused warning
    try self.emit("\n");

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
        .aug_assign => |aug| try statements.genAugAssign(self, aug),
        .expr_stmt => |expr| try statements.genExprStmt(self, expr.value.*),
        .if_stmt => |if_stmt| try statements.genIf(self, if_stmt),
        .while_stmt => |while_stmt| try statements.genWhile(self, while_stmt),
        .for_stmt => |for_stmt| try statements.genFor(self, for_stmt),
        .return_stmt => |ret| try statements.genReturn(self, ret),
        .assert_stmt => |assert_node| try statements.genAssert(self, assert_node),
        .try_stmt => |try_node| try statements.genTry(self, try_node),
        .class_def => |class| try statements.genClassDef(self, class),
        .import_stmt => |import| try statements.genImport(self, import),
        .import_from => |import| try statements.genImportFrom(self, import),
        .pass => try statements.genPass(self),
        .break_stmt => try statements.genBreak(self),
        .continue_stmt => try statements.genContinue(self),
        else => {},
    }
}

// Expression generation delegated to expressions.zig
pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    try expressions.genExpr(self, node);
}
