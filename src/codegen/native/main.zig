/// Native Zig code generation - No PyObject overhead
/// Generates stack-allocated native types based on type inference
/// Core module - delegates to json/http/builtins/methods/async
const std = @import("std");
const ast = @import("../../ast.zig");
const native_types = @import("../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const TypeInferrer = native_types.TypeInferrer;
const SemanticInfo = @import("../../analysis/types.zig").SemanticInfo;

// Import specialized modules
const json = @import("json.zig");
const http = @import("http.zig");
const async_mod = @import("async.zig");
const builtins = @import("builtins.zig");
const methods = @import("methods.zig");
const analyzer = @import("analyzer.zig");
const dispatch = @import("dispatch.zig");
const statements = @import("statements.zig");
const expressions = @import("expressions.zig");

/// Error set for code generation
pub const CodegenError = error{
    OutOfMemory,
} || native_types.InferError;

pub const NativeCodegen = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    type_inferrer: *TypeInferrer,
    semantic_info: *SemanticInfo,
    indent_level: usize,

    // Variable scope tracking - stack of scopes (innermost = last)
    scopes: std.ArrayList(std.StringHashMap(void)),

    // Class registry for inheritance support - maps class name to ClassDef
    classes: std.StringHashMap(ast.Node.ClassDef),

    // Counter for unique tuple unpacking temporary variables
    unpack_counter: usize,

    // Lambda support - counter for unique names, storage for lambda function definitions
    lambda_counter: usize,
    lambda_functions: std.ArrayList([]const u8),

    // Track which variables hold closures (for .call() generation)
    closure_vars: std.StringHashMap(void),

    // Track which variables are closure factories (return closures)
    closure_factories: std.StringHashMap(void),

    // Track which variables hold simple lambdas (function pointers)
    lambda_vars: std.StringHashMap(void),

    // Variable renames for exception handling (maps original name -> renamed name)
    var_renames: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, type_inferrer: *TypeInferrer, semantic_info: *SemanticInfo) !*NativeCodegen {
        const self = try allocator.create(NativeCodegen);
        var scopes = std.ArrayList(std.StringHashMap(void)){};

        // Initialize with global scope
        const global_scope = std.StringHashMap(void).init(allocator);
        try scopes.append(allocator, global_scope);

        self.* = .{
            .allocator = allocator,
            .output = std.ArrayList(u8){},
            .type_inferrer = type_inferrer,
            .semantic_info = semantic_info,
            .indent_level = 0,
            .scopes = scopes,
            .classes = std.StringHashMap(ast.Node.ClassDef).init(allocator),
            .unpack_counter = 0,
            .lambda_counter = 0,
            .lambda_functions = std.ArrayList([]const u8){},
            .closure_vars = std.StringHashMap(void).init(allocator),
            .closure_factories = std.StringHashMap(void).init(allocator),
            .lambda_vars = std.StringHashMap(void).init(allocator),
            .var_renames = std.StringHashMap([]const u8).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *NativeCodegen) void {
        self.output.deinit(self.allocator);
        // Clean up all scopes
        for (self.scopes.items) |*scope| {
            scope.deinit();
        }
        self.scopes.deinit(self.allocator);
        self.classes.deinit();
        // Clean up lambda functions
        for (self.lambda_functions.items) |lambda_code| {
            self.allocator.free(lambda_code);
        }
        self.lambda_functions.deinit(self.allocator);

        // Clean up closure tracking HashMaps (free keys)
        var closure_iter = self.closure_vars.keyIterator();
        while (closure_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.closure_vars.deinit();

        var factory_iter = self.closure_factories.keyIterator();
        while (factory_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.closure_factories.deinit();

        var lambda_iter = self.lambda_vars.keyIterator();
        while (lambda_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.lambda_vars.deinit();

        // Clean up variable renames
        self.var_renames.deinit();

        self.allocator.destroy(self);
    }

    /// Push new scope (call when entering loop/function/block)
    pub fn pushScope(self: *NativeCodegen) !void {
        const new_scope = std.StringHashMap(void).init(self.allocator);
        try self.scopes.append(self.allocator, new_scope);
    }

    /// Pop scope (call when exiting loop/function/block)
    pub fn popScope(self: *NativeCodegen) void {
        if (self.scopes.items.len > 0) {
            const idx = self.scopes.items.len - 1;
            self.scopes.items[idx].deinit();
            _ = self.scopes.pop();
        }
    }

    /// Check if variable declared in any scope (innermost to outermost)
    pub fn isDeclared(self: *NativeCodegen, name: []const u8) bool {
        var i: usize = self.scopes.items.len;
        while (i > 0) {
            i -= 1;
            if (self.scopes.items[i].contains(name)) return true;
        }
        return false;
    }

    /// Declare variable in current (innermost) scope
    pub fn declareVar(self: *NativeCodegen, name: []const u8) !void {
        if (self.scopes.items.len > 0) {
            const current_scope = &self.scopes.items[self.scopes.items.len - 1];
            try current_scope.put(name, {});
        }
    }

    /// Compile a Python module to a Zig module file
    fn compileModuleToZig(module_name: []const u8, allocator: std.mem.Allocator) !void {
        // Find the .py file (in same directory or examples/)
        var py_path_buf: [1024]u8 = undefined;
        const py_path = blk: {
            // Try current directory
            const path1 = std.fmt.bufPrint(&py_path_buf, "{s}.py", .{module_name}) catch return;
            std.fs.cwd().access(path1, .{}) catch {
                // Try examples directory
                const path2 = std.fmt.bufPrint(&py_path_buf, "examples/{s}.py", .{module_name}) catch return;
                std.fs.cwd().access(path2, .{}) catch return; // Module not found
                break :blk path2;
            };
            break :blk path1;
        };

        // Read source
        const source = try std.fs.cwd().readFileAlloc(allocator, py_path, 10 * 1024 * 1024);
        defer allocator.free(source);

        // Lex, parse, analyze
        const lexer_mod = @import("../../lexer.zig");
        const parser_mod = @import("../../parser.zig");
        const semantic_types_mod = @import("../../analysis/types.zig");
        const lifetime_analysis_mod = @import("../../analysis/lifetime.zig");
        const native_types_mod = @import("../../analysis/native_types.zig");

        var lex = try lexer_mod.Lexer.init(allocator, source);
        defer lex.deinit();
        const tokens = try lex.tokenize();
        defer allocator.free(tokens);

        var p = parser_mod.Parser.init(allocator, tokens);
        var tree = try p.parse();
        defer tree.deinit(allocator);

        if (tree != .module) return error.InvalidAST;

        var semantic_info = semantic_types_mod.SemanticInfo.init(allocator);
        defer semantic_info.deinit();
        _ = try lifetime_analysis_mod.analyzeLifetimes(&semantic_info, tree, 1);

        var type_inferrer = try native_types_mod.TypeInferrer.init(allocator);
        defer type_inferrer.deinit();
        try type_inferrer.analyze(tree.module);

        // Use full codegen to generate proper module code
        var codegen = try NativeCodegen.init(allocator, &type_inferrer, &semantic_info);
        defer codegen.deinit();

        // Generate imports
        try codegen.emit("const std = @import(\"std\");\n");
        try codegen.emit("const runtime = @import(\"./runtime.zig\");\n\n");

        // Generate only function and class definitions (make all functions pub)
        for (tree.module.body) |stmt| {
            if (stmt == .function_def or stmt == .class_def) {
                // For functions, we need to make them pub
                if (stmt == .function_def) {
                    const func = stmt.function_def;
                    try codegen.emit("pub ");

                    // Generate async keyword if needed
                    if (func.is_async) {
                        try codegen.emit("async ");
                    }

                    try codegen.emit("fn ");
                    try codegen.emit(func.name);
                    try codegen.emit("(");

                    // Parameters with type inference
                    for (func.args, 0..) |arg, i| {
                        if (i > 0) try codegen.emit(", ");
                        try codegen.emit(arg.name);
                        try codegen.emit(": ");

                        // Try to infer parameter type
                        const param_type = type_inferrer.var_types.get(arg.name) orelse native_types_mod.NativeType.int;
                        const type_str = switch (param_type) {
                            .int => "i64",
                            .float => "f64",
                            .bool => "bool",
                            .string => "[]const u8",
                            else => "i64",
                        };
                        try codegen.emit(type_str);
                    }

                    // Add allocator parameter for module functions
                    if (func.args.len > 0) try codegen.emit(", ");
                    try codegen.emit("allocator: std.mem.Allocator");

                    try codegen.emit(") ");

                    // Return type - default to i64
                    try codegen.emit("i64");
                    try codegen.emit(" {\n");

                    codegen.indent();

                    // Generate function body using full codegen
                    for (func.body) |body_stmt| {
                        try codegen.generateStmt(body_stmt);
                    }

                    codegen.dedent();
                    try codegen.emit("}\n\n");
                } else {
                    // For classes, use the full codegen
                    try statements.genClassDef(codegen, stmt.class_def);
                }
            }
        }

        const zig_code = try codegen.output.toOwnedSlice(allocator);
        defer allocator.free(zig_code);

        // Write to .build/module_name.zig
        const zig_path = try std.fmt.allocPrint(allocator, ".build/{s}.zig", .{module_name});
        defer allocator.free(zig_path);

        const file = try std.fs.cwd().createFile(zig_path, .{});
        defer file.close();
        try file.writeAll(zig_code);
    }

    /// Scan AST for import statements and collect module names
    fn collectImports(module: ast.Node.Module, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var imports = std.ArrayList([]const u8){};

        const stdlib = [_][]const u8{
            "pytest", "unittest", "sys", "os", "math", "json",
            "re", "itertools", "functools", "collections",
            "typing", "abc", "enum", "dataclasses", "asyncio",
        };

        for (module.body) |stmt| {
            if (stmt == .import_stmt) {
                const module_name = stmt.import_stmt.module;

                // Skip stdlib modules
                var is_stdlib = false;
                for (stdlib) |mod| {
                    if (std.mem.eql(u8, module_name, mod)) {
                        is_stdlib = true;
                        break;
                    }
                }

                if (!is_stdlib) {
                    try imports.append(allocator, module_name);
                }
            }
        }

        return imports;
    }

    /// Generate native Zig code for module
    pub fn generate(self: *NativeCodegen, module: ast.Node.Module) ![]const u8 {
        // PHASE 1: Analyze module to determine requirements
        const analysis = try analyzer.analyzeModule(module, self.allocator);

        // PHASE 1.5: Collect imports and compile imported modules
        var imported_modules = try collectImports(module, self.allocator);
        defer imported_modules.deinit(self.allocator);

        // Compile each imported module to .zig file
        for (imported_modules.items) |mod_name| {
            try compileModuleToZig(mod_name, self.allocator);
        }

        // PHASE 2: Register all classes for inheritance support
        for (module.body) |stmt| {
            if (stmt == .class_def) {
                try self.classes.put(stmt.class_def.name, stmt.class_def);
            }
        }

        // PHASE 3: Generate imports based on analysis
        try self.emit("const std = @import(\"std\");\n");
        // Always import runtime for formatAny() and other utilities
        try self.emit("const runtime = @import(\"./runtime.zig\");\n");
        if (analysis.needs_string_utils) {
            try self.emit("const string_utils = @import(\"string_utils.zig\");\n");
        }

        // Add user module imports
        for (imported_modules.items) |mod_name| {
            try self.emit("const ");
            try self.emit(mod_name);
            try self.emit(" = @import(\"");
            try self.emit(mod_name);
            try self.emit(".zig\");\n");
        }

        try self.emit("\n");

        // PHASE 4: Define __name__ constant (for if __name__ == "__main__" support)
        try self.emit("const __name__ = \"__main__\";\n\n");

        // PHASE 5: Generate class and function definitions (before main)
        for (module.body) |stmt| {
            if (stmt == .class_def) {
                try statements.genClassDef(self, stmt.class_def);
                try self.emit("\n");
            } else if (stmt == .function_def) {
                try statements.genFunctionDef(self, stmt.function_def);
                try self.emit("\n");
            }
        }

        // PHASE 6: Generate main function
        try self.emit("pub fn main() !void {\n");
        self.indent();

        // Setup allocator (only if needed)
        if (analysis.needs_allocator) {
            try self.emitIndent();
            try self.emit("var gpa = std.heap.GeneralPurposeAllocator(.{}){};\n");
            try self.emitIndent();
            try self.emit("defer _ = gpa.deinit();\n");
            try self.emitIndent();
            try self.emit("const allocator = gpa.allocator();\n\n");
        }

        // PHASE 7: Generate statements (skip class/function defs - already handled)
        // This will populate self.lambda_functions
        for (module.body) |stmt| {
            if (stmt != .function_def and stmt != .class_def) {
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
            .import_stmt => {}, // Native modules - no import needed
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

    // Helper functions - public for use by statements.zig and expressions.zig
    pub fn emit(self: *NativeCodegen, s: []const u8) CodegenError!void {
        try self.output.appendSlice(self.allocator, s);
    }

    pub fn emitIndent(self: *NativeCodegen) CodegenError!void {
        var i: usize = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.output.appendSlice(self.allocator, "    ");
        }
    }

    pub fn indent(self: *NativeCodegen) void {
        self.indent_level += 1;
    }

    pub fn dedent(self: *NativeCodegen) void {
        self.indent_level -= 1;
    }

    /// Convert NativeType to Zig type string for code generation
    /// Uses type inference results to get concrete types
    pub fn nativeTypeToZigType(self: *NativeCodegen, native_type: NativeType) ![]const u8 {
        var buf = std.ArrayList(u8){};
        try native_type.toZigType(self.allocator, &buf);
        return buf.toOwnedSlice(self.allocator);
    }

    /// Get the inferred type of a variable from type inference
    pub fn getVarType(self: *NativeCodegen, var_name: []const u8) ?NativeType {
        return self.type_inferrer.var_types.get(var_name);
    }
};
