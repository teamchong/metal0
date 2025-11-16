/// Native Zig code generation - No PyObject overhead
/// Generates stack-allocated native types based on type inference
/// Core module - delegates to json/http/builtins/methods/async
const std = @import("std");
const ast = @import("../../ast.zig");
const native_types = @import("../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const TypeInferrer = native_types.TypeInferrer;

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
    indent_level: usize,

    // Variable scope tracking - stack of scopes (innermost = last)
    scopes: std.ArrayList(std.StringHashMap(void)),

    pub fn init(allocator: std.mem.Allocator, type_inferrer: *TypeInferrer) !*NativeCodegen {
        const self = try allocator.create(NativeCodegen);
        var scopes = std.ArrayList(std.StringHashMap(void)){};

        // Initialize with global scope
        const global_scope = std.StringHashMap(void).init(allocator);
        try scopes.append(allocator, global_scope);

        self.* = .{
            .allocator = allocator,
            .output = std.ArrayList(u8){},
            .type_inferrer = type_inferrer,
            .indent_level = 0,
            .scopes = scopes,
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

    /// Generate native Zig code for module
    pub fn generate(self: *NativeCodegen, module: ast.Node.Module) ![]const u8 {
        // PHASE 1: Analyze module to determine requirements
        const analysis = try analyzer.analyzeModule(module, self.allocator);

        // PHASE 2: Generate imports based on analysis
        try self.emit("const std = @import(\"std\");\n");
        if (analysis.needs_runtime) {
            // Use relative import since runtime.zig is in /tmp with generated file
            try self.emit("const runtime = @import(\"./runtime.zig\");\n");
        }
        if (analysis.needs_string_utils) {
            try self.emit("const string_utils = @import(\"string_utils.zig\");\n");
        }
        try self.emit("\n");

        // PHASE 3: Generate function definitions (before main)
        for (module.body) |stmt| {
            if (stmt == .function_def) {
                try statements.genFunctionDef(self, stmt.function_def);
                try self.emit("\n");
            }
        }

        // PHASE 4: Generate main function
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

        // PHASE 5: Generate statements (skip function defs - already handled)
        for (module.body) |stmt| {
            if (stmt != .function_def) {
                try self.generateStmt(stmt);
            }
        }

        self.dedent();
        try self.emit("}\n");

        return self.output.toOwnedSlice(self.allocator);
    }

    pub fn generateStmt(self: *NativeCodegen, node: ast.Node) CodegenError!void {
        switch (node) {
            .assign => |assign| try statements.genAssign(self, assign),
            .expr_stmt => |expr| try statements.genExprStmt(self, expr.value.*),
            .if_stmt => |if_stmt| try statements.genIf(self, if_stmt),
            .while_stmt => |while_stmt| try statements.genWhile(self, while_stmt),
            .for_stmt => |for_stmt| try statements.genFor(self, for_stmt),
            .return_stmt => |ret| try statements.genReturn(self, ret),
            .import_stmt => {}, // Native modules - no import needed
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
};
