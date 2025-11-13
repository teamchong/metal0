const std = @import("std");
const ast = @import("ast.zig");
const operators = @import("codegen/operators.zig");
const classes = @import("codegen/classes.zig");
const builtins = @import("codegen/builtins.zig");

/// Codegen errors
pub const CodegenError = error{
    ExpectedModule,
    UnsupportedExpression,
    UnsupportedStatement,
    UnsupportedTarget,
    InvalidAssignment,
    InvalidCompare,
    EmptyTargets,
    UnsupportedFunction,
    UnsupportedCall,
    UnsupportedMethod,
    InvalidArguments,
    UnsupportedForLoop,
    InvalidLoopVariable,
    InvalidRangeArgs,
    InvalidEnumerateArgs,
    InvalidEnumerateTarget,
    InvalidZipArgs,
    InvalidZipTarget,
    MissingLenArg,
    NotImplemented,
    OutOfMemory,
};

/// Generate Zig code from AST
pub fn generate(allocator: std.mem.Allocator, tree: ast.Node) ![]const u8 {
    // Initialize code generator
    var generator = try ZigCodeGenerator.init(allocator);
    defer generator.deinit();

    // Generate code from AST
    switch (tree) {
        .module => |module| try generator.generate(module),
        else => return error.ExpectedModule,
    }

    return try generator.output.toOwnedSlice(allocator);
}

/// Expression evaluation result
pub const ExprResult = struct {
    code: []const u8,
    needs_try: bool,
};

/// Zig code generator - ports Python ZigCodeGenerator class
pub const ZigCodeGenerator = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    indent_level: usize,

    // State tracking (matching Python codegen)
    var_types: std.StringHashMap([]const u8),
    declared_vars: std.StringHashMap(void),
    reassigned_vars: std.StringHashMap(void),
    list_element_types: std.StringHashMap([]const u8),
    tuple_element_types: std.StringHashMap([]const u8),
    function_names: std.StringHashMap(void),
    class_names: std.StringHashMap(void),

    needs_runtime: bool,
    needs_allocator: bool,
    temp_var_counter: usize,

    pub fn init(allocator: std.mem.Allocator) !*ZigCodeGenerator {
        const self = try allocator.create(ZigCodeGenerator);
        self.* = ZigCodeGenerator{
            .allocator = allocator,
            .output = std.ArrayList(u8){},
            .indent_level = 0,
            .var_types = std.StringHashMap([]const u8).init(allocator),
            .declared_vars = std.StringHashMap(void).init(allocator),
            .reassigned_vars = std.StringHashMap(void).init(allocator),
            .list_element_types = std.StringHashMap([]const u8).init(allocator),
            .tuple_element_types = std.StringHashMap([]const u8).init(allocator),
            .function_names = std.StringHashMap(void).init(allocator),
            .class_names = std.StringHashMap(void).init(allocator),
            .needs_runtime = false,
            .needs_allocator = false,
            .temp_var_counter = 0,
        };
        return self;
    }

    pub fn deinit(self: *ZigCodeGenerator) void {
        self.output.deinit(self.allocator);
        self.var_types.deinit();
        self.declared_vars.deinit();
        self.reassigned_vars.deinit();
        self.list_element_types.deinit();
        self.tuple_element_types.deinit();
        self.function_names.deinit();
        self.class_names.deinit();
        self.allocator.destroy(self);
    }

    /// Emit a line of code with proper indentation
    pub fn emit(self: *ZigCodeGenerator, code: []const u8) CodegenError!void {
        // Add indentation
        for (0..self.indent_level) |_| {
            try self.output.appendSlice(self.allocator, "    ");
        }
        try self.output.appendSlice(self.allocator, code);
        try self.output.append(self.allocator, '\n');
    }

    /// Increase indentation level
    pub fn indent(self: *ZigCodeGenerator) void {
        self.indent_level += 1;
    }

    /// Decrease indentation level
    pub fn dedent(self: *ZigCodeGenerator) void {
        if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
    }

    /// Generate code from parsed AST
    pub fn generate(self: *ZigCodeGenerator, module: ast.Node.Module) CodegenError!void {
        // Phase 1: Detect runtime needs, collect declarations, and collect function names
        for (module.body) |node| {
            try self.detectRuntimeNeeds(node);
            try self.collectDeclarations(node);

            // Collect function names
            if (node == .function_def) {
                try self.function_names.put(node.function_def.name, {});
            }

            // Collect class names
            if (node == .class_def) {
                try self.class_names.put(node.class_def.name, {});
            }
        }

        // Phase 2: Detect reassignments
        var assignments_seen = std.StringHashMap(void).init(self.allocator);
        defer assignments_seen.deinit();

        for (module.body) |node| {
            try self.detectReassignments(node, &assignments_seen);
        }

        // Reset declared_vars for code generation
        self.declared_vars.clearRetainingCapacity();

        // Phase 3: Generate imports
        try self.emit("const std = @import(\"std\");");
        if (self.needs_runtime) {
            try self.emit("const runtime = @import(\"runtime.zig\");");
        }
        try self.emit("");

        // Phase 4: Generate class and function definitions (before main)
        for (module.body) |node| {
            if (node == .class_def) {
                try classes.visitClassDef(self, node.class_def);
                try self.emit("");
            }
        }

        for (module.body) |node| {
            if (node == .function_def) {
                try self.visitFunctionDef(node.function_def);
                try self.emit("");
            }
        }

        // Phase 5: Generate main function
        try self.emit("pub fn main() !void {");
        self.indent();

        if (self.needs_allocator) {
            try self.emit("var gpa = std.heap.GeneralPurposeAllocator(.{}){};");
            try self.emit("defer _ = gpa.deinit();");
            try self.emit("const allocator = gpa.allocator();");
            try self.emit("");
        }

        // Only visit non-function/class nodes in main
        for (module.body) |node| {
            if (node != .function_def and node != .class_def) {
                try self.visitNode(node);
            }
        }

        self.dedent();
        try self.emit("}");
    }

    /// Detect if node requires PyObject runtime
    fn detectRuntimeNeeds(self: *ZigCodeGenerator, node: ast.Node) CodegenError!void {
        switch (node) {
            .constant => |constant| {
                if (constant.value == .string) {
                    self.needs_runtime = true;
                    self.needs_allocator = true;
                }
            },
            .list => {
                self.needs_runtime = true;
                self.needs_allocator = true;
            },
            .expr_stmt => |expr_stmt| {
                // Skip docstrings (same as in visitNode)
                const is_docstring = switch (expr_stmt.value.*) {
                    .constant => |c| c.value == .string,
                    else => false,
                };

                if (!is_docstring) {
                    try self.detectRuntimeNeedsExpr(expr_stmt.value.*);
                }
            },
            .assign => |assign| {
                try self.detectRuntimeNeedsExpr(assign.value.*);
            },
            .if_stmt => |if_stmt| {
                // Check condition
                try self.detectRuntimeNeedsExpr(if_stmt.condition.*);
                // Check body
                for (if_stmt.body) |stmt| {
                    try self.detectRuntimeNeeds(stmt);
                }
                // Check else body
                for (if_stmt.else_body) |stmt| {
                    try self.detectRuntimeNeeds(stmt);
                }
            },
            .while_stmt => |while_stmt| {
                try self.detectRuntimeNeedsExpr(while_stmt.condition.*);
                for (while_stmt.body) |stmt| {
                    try self.detectRuntimeNeeds(stmt);
                }
            },
            .for_stmt => |for_stmt| {
                try self.detectRuntimeNeedsExpr(for_stmt.iter.*);
                for (for_stmt.body) |stmt| {
                    try self.detectRuntimeNeeds(stmt);
                }
            },
            else => {},
        }
    }

    /// Detect if expression requires PyObject runtime
    fn detectRuntimeNeedsExpr(self: *ZigCodeGenerator, node: ast.Node) CodegenError!void {
        switch (node) {
            .constant => |constant| {
                if (constant.value == .string) {
                    self.needs_runtime = true;
                    self.needs_allocator = true;
                }
            },
            .list => {
                self.needs_runtime = true;
                self.needs_allocator = true;
            },
            .call => |call| {
                // Check if this is a runtime function call
                // Note: abs, min, max work on primitives and don't need runtime
                // len, sum, all, any work on PyObjects and need runtime
                switch (call.func.*) {
                    .name => |func_name| {
                        if (std.mem.eql(u8, func_name.id, "sum") or
                            std.mem.eql(u8, func_name.id, "all") or
                            std.mem.eql(u8, func_name.id, "any") or
                            std.mem.eql(u8, func_name.id, "len"))
                        {
                            self.needs_runtime = true;
                        }
                    },
                    else => {},
                }
                // Recursively check arguments
                for (call.args) |arg| {
                    try self.detectRuntimeNeedsExpr(arg);
                }
            },
            .binop => |binop| {
                try self.detectRuntimeNeedsExpr(binop.left.*);
                try self.detectRuntimeNeedsExpr(binop.right.*);
            },
            .compare => |compare| {
                // Check if 'in' or 'not in' operator is used
                for (compare.ops) |op| {
                    if (op == .In or op == .NotIn) {
                        self.needs_runtime = true;
                        break;
                    }
                }
                // Recursively check left and comparators
                try self.detectRuntimeNeedsExpr(compare.left.*);
                for (compare.comparators) |comp| {
                    try self.detectRuntimeNeedsExpr(comp);
                }
            },
            else => {},
        }
    }

    /// Collect all variable declarations
    fn collectDeclarations(self: *ZigCodeGenerator, node: ast.Node) CodegenError!void {
        switch (node) {
            .assign => |assign| {
                for (assign.targets) |target| {
                    switch (target) {
                        .name => |name| {
                            try self.declared_vars.put(name.id, {});
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    /// Detect variables that are reassigned
    fn detectReassignments(self: *ZigCodeGenerator, node: ast.Node, assignments_seen: *std.StringHashMap(void)) CodegenError!void {
        switch (node) {
            .assign => |assign| {
                for (assign.targets) |target| {
                    switch (target) {
                        .name => |name| {
                            if (assignments_seen.contains(name.id)) {
                                try self.reassigned_vars.put(name.id, {});
                            } else {
                                try assignments_seen.put(name.id, {});
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    /// Visit a node and generate code
    pub fn visitNode(self: *ZigCodeGenerator, node: ast.Node) CodegenError!void {
        switch (node) {
            .assign => |assign| try self.visitAssign(assign),
            .expr_stmt => |expr_stmt| {
                // Skip docstrings (standalone string constants)
                const is_docstring = switch (expr_stmt.value.*) {
                    .constant => |c| c.value == .string,
                    else => false,
                };

                if (!is_docstring) {
                    const result = try self.visitExpr(expr_stmt.value.*);
                    // Expression statement - emit it with semicolon
                    if (result.code.len > 0) {
                        var buf = std.ArrayList(u8){};
                        try buf.writer(self.allocator).print("{s};", .{result.code});
                        try self.emit(try buf.toOwnedSlice(self.allocator));
                    }
                }
            },
            .if_stmt => |if_node| try self.visitIf(if_node),
            .for_stmt => |for_node| try self.visitFor(for_node),
            .while_stmt => |while_node| try self.visitWhile(while_node),
            .function_def => |func| try self.visitFunctionDef(func),
            .return_stmt => |ret| try self.visitReturn(ret),
            else => {}, // Ignore other node types for now
        }
    }

    // Visitor methods
    fn visitAssign(self: *ZigCodeGenerator, assign: ast.Node.Assign) CodegenError!void {
        if (assign.targets.len == 0) return error.EmptyTargets;

        // For now, handle single target
        const target = assign.targets[0];

        switch (target) {
            .name => |name| {
                const var_name = name.id;

                // Determine if this is first assignment or reassignment
                const is_first_assignment = !self.declared_vars.contains(var_name);

                if (is_first_assignment) {
                    try self.declared_vars.put(var_name, {});
                }

                // Evaluate the value expression
                const value_result = try self.visitExpr(assign.value.*);

                // Infer type from value and check if it's a class instance
                var is_class_instance = false;
                switch (assign.value.*) {
                    .constant => |constant| {
                        switch (constant.value) {
                            .string => try self.var_types.put(var_name, "string"),
                            .int => try self.var_types.put(var_name, "int"),
                            else => {},
                        }
                    },
                    .binop => {
                        // Binary operation - assume int for now
                        try self.var_types.put(var_name, "int");
                    },
                    .name => |source_name| {
                        // Assigning from another variable - copy its type
                        const source_type = self.var_types.get(source_name.id);
                        if (source_type) |stype| {
                            try self.var_types.put(var_name, stype);
                            is_class_instance = std.mem.eql(u8, stype, "class");
                        }
                    },
                    .list => {
                        try self.var_types.put(var_name, "list");
                    },
                    .call => |call| {
                        // Check if this is a class instantiation
                        switch (call.func.*) {
                            .name => |func_name| {
                                if (self.class_names.contains(func_name.id)) {
                                    try self.var_types.put(var_name, "class");
                                    is_class_instance = true;
                                }
                            },
                            else => {},
                        }
                    },
                    else => {},
                }

                // Use 'var' for reassigned vars, 'const' otherwise
                // Note: Class instances use 'const' unless reassigned - field mutations don't require 'var' in Zig
                const var_keyword = if (self.reassigned_vars.contains(var_name)) "var" else "const";

                // Generate assignment code
                var buf = std.ArrayList(u8){};

                if (is_first_assignment) {
                    if (value_result.needs_try) {
                        try buf.writer(self.allocator).print("{s} {s} = try {s};", .{ var_keyword, var_name, value_result.code });
                        try self.emit(try buf.toOwnedSlice(self.allocator));

                        // Add defer for strings
                        const var_type = self.var_types.get(var_name);
                        if (var_type != null and std.mem.eql(u8, var_type.?, "string")) {
                            var defer_buf = std.ArrayList(u8){};
                            try defer_buf.writer(self.allocator).print("defer runtime.decref({s}, allocator);", .{var_name});
                            try self.emit(try defer_buf.toOwnedSlice(self.allocator));
                        }
                    } else {
                        try buf.writer(self.allocator).print("{s} {s} = {s};", .{ var_keyword, var_name, value_result.code });
                        try self.emit(try buf.toOwnedSlice(self.allocator));
                    }
                } else {
                    // Reassignment
                    const var_type = self.var_types.get(var_name);
                    if (var_type != null and std.mem.eql(u8, var_type.?, "string")) {
                        var decref_buf = std.ArrayList(u8){};
                        try decref_buf.writer(self.allocator).print("runtime.decref({s}, allocator);", .{var_name});
                        try self.emit(try decref_buf.toOwnedSlice(self.allocator));
                    }

                    if (value_result.needs_try) {
                        try buf.writer(self.allocator).print("{s} = try {s};", .{ var_name, value_result.code });
                    } else {
                        try buf.writer(self.allocator).print("{s} = {s};", .{ var_name, value_result.code });
                    }
                    try self.emit(try buf.toOwnedSlice(self.allocator));
                }
            },
            .attribute => |attr| {
                // Handle attribute assignment like self.value = expr
                // Generate the attribute expression (e.g., "self.value")
                const attr_result = try classes.visitAttribute(self, attr);

                // Evaluate the value expression
                const value_result = try self.visitExpr(assign.value.*);

                // Generate assignment code: attr = value;
                var buf = std.ArrayList(u8){};
                if (value_result.needs_try) {
                    try buf.writer(self.allocator).print("{s} = try {s};", .{ attr_result.code, value_result.code });
                } else {
                    try buf.writer(self.allocator).print("{s} = {s};", .{ attr_result.code, value_result.code });
                }
                try self.emit(try buf.toOwnedSlice(self.allocator));
            },
            else => return error.UnsupportedTarget,
        }
    }

    pub fn visitExpr(self: *ZigCodeGenerator, node: ast.Node) CodegenError!ExprResult {
        return switch (node) {
            .name => |name| ExprResult{
                .code = name.id,
                .needs_try = false,
            },

            .constant => |constant| self.visitConstant(constant),

            .binop => |binop| operators.visitBinOp(self, binop),

            .unaryop => |unaryop| operators.visitUnaryOp(self, unaryop),

            .boolop => |boolop| operators.visitBoolOp(self, boolop),

            .attribute => |attr| classes.visitAttribute(self, attr),

            .call => |call| self.visitCall(call),

            .compare => |compare| operators.visitCompare(self, compare),

            .list => |list| self.visitList(list),

            else => error.UnsupportedExpression,
        };
    }

    fn visitConstant(self: *ZigCodeGenerator, constant: ast.Node.Constant) CodegenError!ExprResult {
        switch (constant.value) {
            .string => |str| {
                var buf = std.ArrayList(u8){};

                // Strip Python quotes and extract content
                var content: []const u8 = str;

                // Handle triple quotes
                if (str.len >= 6 and std.mem.startsWith(u8, str, "\"\"\"")) {
                    content = str[3 .. str.len - 3];
                } else if (str.len >= 6 and std.mem.startsWith(u8, str, "'''")) {
                    content = str[3 .. str.len - 3];
                    // Handle single/double quotes
                } else if (str.len >= 2) {
                    content = str[1 .. str.len - 1];
                }

                // Generate Zig code with proper escaping
                try buf.writer(self.allocator).writeAll("runtime.PyString.create(allocator, \"");

                // Escape content for Zig string
                // Python escape sequences: already processed by Python lexer,
                // we just need to re-escape for Zig syntax
                var i: usize = 0;
                while (i < content.len) : (i += 1) {
                    const c = content[i];
                    switch (c) {
                        '\\' => {
                            // Check if this is an escape sequence
                            if (i + 1 < content.len) {
                                const next = content[i + 1];
                                switch (next) {
                                    'n', 'r', 't', '\\', '\"', '\'', '0', 'a', 'b', 'f', 'v' => {
                                        // Pass through escape sequences
                                        try buf.writer(self.allocator).writeByte('\\');
                                        i += 1;
                                        try buf.writer(self.allocator).writeByte(content[i]);
                                    },
                                    'x', 'u', 'U' => {
                                        // Hex/Unicode escapes - pass through for now
                                        try buf.writer(self.allocator).writeAll("\\\\");
                                    },
                                    else => {
                                        try buf.writer(self.allocator).writeAll("\\\\");
                                    },
                                }
                            } else {
                                try buf.writer(self.allocator).writeAll("\\\\");
                            }
                        },
                        '\"' => try buf.writer(self.allocator).writeAll("\\\""),
                        '\n' => try buf.writer(self.allocator).writeAll("\\n"),
                        '\r' => try buf.writer(self.allocator).writeAll("\\r"),
                        '\t' => try buf.writer(self.allocator).writeAll("\\t"),
                        else => {
                            if (c >= 32 and c <= 126) {
                                try buf.writer(self.allocator).writeByte(c);
                            } else {
                                // Non-printable - escape as hex
                                try buf.writer(self.allocator).print("\\x{X:0>2}", .{c});
                            }
                        },
                    }
                }

                try buf.writer(self.allocator).writeAll("\")");

                return ExprResult{
                    .code = try buf.toOwnedSlice(self.allocator),
                    .needs_try = true,
                };
            },
            .int => |num| {
                var buf = std.ArrayList(u8){};
                try buf.writer(self.allocator).print("{d}", .{num});
                return ExprResult{
                    .code = try buf.toOwnedSlice(self.allocator),
                    .needs_try = false,
                };
            },
            .bool => |b| {
                return ExprResult{
                    .code = if (b) "true" else "false",
                    .needs_try = false,
                };
            },
            .float => |f| {
                var buf = std.ArrayList(u8){};
                try buf.writer(self.allocator).print("{d}", .{f});
                return ExprResult{
                    .code = try buf.toOwnedSlice(self.allocator),
                    .needs_try = false,
                };
            },
        }
    }

    fn visitList(self: *ZigCodeGenerator, list: ast.Node.List) CodegenError!ExprResult {
        // Generate code to create a list literal
        // Strategy: Create empty list, then append each element
        self.needs_runtime = true;
        self.needs_allocator = true;

        // Unique variable name for the list
        const list_var = try std.fmt.allocPrint(self.allocator, "__list_{d}", .{self.temp_var_counter});
        self.temp_var_counter += 1;

        // Emit list creation as statements
        var create_buf = std.ArrayList(u8){};
        try create_buf.writer(self.allocator).print("const {s} = try runtime.PyList.create(allocator);", .{list_var});
        try self.emit(try create_buf.toOwnedSlice(self.allocator));

        // Append each element
        for (list.elts) |elt| {
            const elt_result = try self.visitExpr(elt);
            var append_buf = std.ArrayList(u8){};

            // Check if element needs wrapping (constants need to be wrapped in PyObject)
            const needs_wrapping = switch (elt) {
                .constant => |c| switch (c.value) {
                    .int, .float, .bool => true,
                    else => false,
                },
                else => false,
            };

            if (needs_wrapping) {
                // Wrap constant in appropriate PyObject type
                const wrapped_code = switch (elt) {
                    .constant => |c| switch (c.value) {
                        .int => try std.fmt.allocPrint(self.allocator, "try runtime.PyInt.create(allocator, {s})", .{elt_result.code}),
                        .float => try std.fmt.allocPrint(self.allocator, "try runtime.PyFloat.create(allocator, {s})", .{elt_result.code}),
                        .bool => try std.fmt.allocPrint(self.allocator, "try runtime.PyBool.create(allocator, {s})", .{elt_result.code}),
                        else => elt_result.code,
                    },
                    else => elt_result.code,
                };
                try append_buf.writer(self.allocator).print("try runtime.PyList.append({s}, {s});", .{ list_var, wrapped_code });
            } else if (elt_result.needs_try) {
                try append_buf.writer(self.allocator).print("try runtime.PyList.append({s}, try {s});", .{ list_var, elt_result.code });
            } else {
                try append_buf.writer(self.allocator).print("try runtime.PyList.append({s}, {s});", .{ list_var, elt_result.code });
            }
            try self.emit(try append_buf.toOwnedSlice(self.allocator));
        }

        // Return the list variable name
        return ExprResult{
            .code = list_var,
            .needs_try = false,
        };
    }

    fn visitCall(self: *ZigCodeGenerator, call: ast.Node.Call) CodegenError!ExprResult {
        switch (call.func.*) {
            .name => |func_name| {
                // Handle built-in functions
                if (std.mem.eql(u8, func_name.id, "print")) {
                    return builtins.visitPrintCall(self, call.args);
                } else if (std.mem.eql(u8, func_name.id, "len")) {
                    return builtins.visitLenCall(self, call.args);
                } else if (std.mem.eql(u8, func_name.id, "abs")) {
                    return builtins.visitAbsCall(self, call.args);
                } else if (std.mem.eql(u8, func_name.id, "round")) {
                    return builtins.visitRoundCall(self, call.args);
                } else if (std.mem.eql(u8, func_name.id, "min")) {
                    return builtins.visitMinCall(self, call.args);
                } else if (std.mem.eql(u8, func_name.id, "max")) {
                    return builtins.visitMaxCall(self, call.args);
                } else if (std.mem.eql(u8, func_name.id, "sum")) {
                    return builtins.visitSumCall(self, call.args);
                } else if (std.mem.eql(u8, func_name.id, "all")) {
                    return builtins.visitAllCall(self, call.args);
                } else if (std.mem.eql(u8, func_name.id, "any")) {
                    return builtins.visitAnyCall(self, call.args);
                } else {
                    // Check if this is a class instantiation
                    if (self.class_names.contains(func_name.id)) {
                        return classes.visitClassInstantiation(self, func_name.id, call.args);
                    }

                    // Check if this is a user-defined function
                    if (self.function_names.contains(func_name.id)) {
                        return self.visitUserFunctionCall(func_name.id, call.args);
                    }
                    return error.UnsupportedFunction;
                }
            },
            .attribute => |attr| {
                // Handle method calls like obj.method(args)
                return classes.visitMethodCall(self, attr, call.args);
            },
            else => return error.UnsupportedCall,
        }
    }

    fn visitUserFunctionCall(self: *ZigCodeGenerator, func_name: []const u8, args: []ast.Node) CodegenError!ExprResult {
        var buf = std.ArrayList(u8){};

        // Generate function call: func_name(arg1, arg2, ...)
        try buf.writer(self.allocator).print("{s}(", .{func_name});

        // Add arguments
        for (args, 0..) |arg, i| {
            if (i > 0) {
                try buf.writer(self.allocator).writeAll(", ");
            }
            const arg_result = try self.visitExpr(arg);
            try buf.writer(self.allocator).writeAll(arg_result.code);
        }

        // Add allocator if needed
        if (self.needs_allocator and args.len > 0) {
            try buf.writer(self.allocator).writeAll(", allocator");
        } else if (self.needs_allocator) {
            try buf.writer(self.allocator).writeAll("allocator");
        }

        try buf.writer(self.allocator).writeAll(")");

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitIf(self: *ZigCodeGenerator, if_node: ast.Node.If) CodegenError!void {
        const test_result = try self.visitExpr(if_node.condition.*);

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("if ({s}) {{", .{test_result.code});
        try self.emit(try buf.toOwnedSlice(self.allocator));

        self.indent();

        for (if_node.body) |stmt| {
            try self.visitNode(stmt);
        }

        self.dedent();

        if (if_node.else_body.len > 0) {
            try self.emit("} else {");
            self.indent();

            for (if_node.else_body) |stmt| {
                try self.visitNode(stmt);
            }

            self.dedent();
        }

        try self.emit("}");
    }

    fn visitFor(self: *ZigCodeGenerator, for_node: ast.Node.For) CodegenError!void {
        // Check if this is a special function call (range, enumerate, zip)
        switch (for_node.iter.*) {
            .call => |call| {
                switch (call.func.*) {
                    .name => |func_name| {
                        if (std.mem.eql(u8, func_name.id, "range")) {
                            return self.visitRangeFor(for_node, call.args);
                        } else if (std.mem.eql(u8, func_name.id, "enumerate")) {
                            return self.visitEnumerateFor(for_node, call.args);
                        } else if (std.mem.eql(u8, func_name.id, "zip")) {
                            return self.visitZipFor(for_node, call.args);
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }

        return error.UnsupportedForLoop;
    }

    fn visitRangeFor(self: *ZigCodeGenerator, for_node: ast.Node.For, args: []ast.Node) CodegenError!void {
        // Get loop variable name
        switch (for_node.target.*) {
            .name => |target_name| {
                const loop_var = target_name.id;
                try self.var_types.put(loop_var, "int");

                // Parse range arguments
                var start: []const u8 = "0";
                var end: []const u8 = undefined;
                var step: []const u8 = "1";

                if (args.len == 1) {
                    const end_result = try self.visitExpr(args[0]);
                    end = end_result.code;
                } else if (args.len == 2) {
                    const start_result = try self.visitExpr(args[0]);
                    const end_result = try self.visitExpr(args[1]);
                    start = start_result.code;
                    end = end_result.code;
                } else if (args.len == 3) {
                    const start_result = try self.visitExpr(args[0]);
                    const end_result = try self.visitExpr(args[1]);
                    const step_result = try self.visitExpr(args[2]);
                    start = start_result.code;
                    end = end_result.code;
                    step = step_result.code;
                } else {
                    return error.InvalidRangeArgs;
                }

                // Check if loop variable already declared
                const is_first_use = !self.declared_vars.contains(loop_var);

                var buf = std.ArrayList(u8){};

                if (is_first_use) {
                    try buf.writer(self.allocator).print("var {s}: i64 = {s};", .{ loop_var, start });
                    try self.emit(try buf.toOwnedSlice(self.allocator));
                    try self.declared_vars.put(loop_var, {});
                } else {
                    try buf.writer(self.allocator).print("{s} = {s};", .{ loop_var, start });
                    try self.emit(try buf.toOwnedSlice(self.allocator));
                }

                buf = std.ArrayList(u8){};
                try buf.writer(self.allocator).print("while ({s} < {s}) {{", .{ loop_var, end });
                try self.emit(try buf.toOwnedSlice(self.allocator));

                self.indent();

                for (for_node.body) |stmt| {
                    try self.visitNode(stmt);
                }

                buf = std.ArrayList(u8){};
                try buf.writer(self.allocator).print("{s} += {s};", .{ loop_var, step });
                try self.emit(try buf.toOwnedSlice(self.allocator));

                self.dedent();
                try self.emit("}");
            },
            else => return error.InvalidLoopVariable,
        }
    }

    fn visitEnumerateFor(self: *ZigCodeGenerator, for_node: ast.Node.For, args: []ast.Node) CodegenError!void {
        if (args.len != 1) return error.InvalidEnumerateArgs;

        // Get the iterable expression
        const iterable_result = try self.visitExpr(args[0]);

        // Extract target variables (should be tuple: index, value)
        switch (for_node.target.*) {
            .list => |target_list| {
                if (target_list.elts.len != 2) return error.InvalidEnumerateTarget;

                // Get index and value variable names
                const idx_name = switch (target_list.elts[0]) {
                    .name => |n| n.id,
                    else => return error.InvalidEnumerateTarget,
                };
                const val_name = switch (target_list.elts[1]) {
                    .name => |n| n.id,
                    else => return error.InvalidEnumerateTarget,
                };

                // Register variable types
                try self.var_types.put(idx_name, "int");
                try self.var_types.put(val_name, "auto");

                // Generate temporary variable to hold the casted list data
                const list_data_var = try std.fmt.allocPrint(self.allocator, "__enum_list_{d}", .{self.temp_var_counter});
                self.temp_var_counter += 1;

                // Cast PyObject to PyList to access items
                var cast_buf = std.ArrayList(u8){};
                try cast_buf.writer(self.allocator).print("const {s}: *runtime.PyList = @ptrCast(@alignCast({s}.data));", .{ list_data_var, iterable_result.code });
                try self.emit(try cast_buf.toOwnedSlice(self.allocator));

                // Generate: for (list_data.items.items, 0..) |val, idx| {
                var buf = std.ArrayList(u8){};
                try buf.writer(self.allocator).print("for ({s}.items.items, 0..) |{s}, {s}| {{", .{ list_data_var, val_name, idx_name });
                try self.emit(try buf.toOwnedSlice(self.allocator));

                // Mark variables as declared
                try self.declared_vars.put(idx_name, {});
                try self.declared_vars.put(val_name, {});

                self.indent();

                for (for_node.body) |stmt| {
                    try self.visitNode(stmt);
                }

                self.dedent();
                try self.emit("}");
            },
            else => return error.InvalidEnumerateTarget,
        }
    }

    fn visitZipFor(self: *ZigCodeGenerator, for_node: ast.Node.For, args: []ast.Node) CodegenError!void {
        if (args.len < 2) return error.InvalidZipArgs;

        // Get all iterable expressions
        var iterables = std.ArrayList([]const u8){};
        defer iterables.deinit(self.allocator);

        for (args) |arg| {
            const iterable_result = try self.visitExpr(arg);
            try iterables.append(self.allocator, iterable_result.code);
        }

        // Extract target variables (should be tuple)
        switch (for_node.target.*) {
            .list => |target_list| {
                if (target_list.elts.len != args.len) return error.InvalidZipTarget;

                // Get all variable names
                var var_names = std.ArrayList([]const u8){};
                defer var_names.deinit(self.allocator);

                for (target_list.elts) |elt| {
                    const var_name = switch (elt) {
                        .name => |n| n.id,
                        else => return error.InvalidZipTarget,
                    };
                    try var_names.append(self.allocator, var_name);
                    try self.var_types.put(var_name, "auto");
                    try self.declared_vars.put(var_name, {});
                }

                // Generate: for (list1.list.items.items, list2.list.items.items, ...) |var1, var2, ...| {
                var buf = std.ArrayList(u8){};
                try buf.writer(self.allocator).writeAll("for (");

                for (iterables.items, 0..) |iterable, i| {
                    if (i > 0) try buf.writer(self.allocator).writeAll(", ");
                    try buf.writer(self.allocator).print("{s}.list.items.items", .{iterable});
                }

                try buf.writer(self.allocator).writeAll(") |");

                for (var_names.items, 0..) |var_name, i| {
                    if (i > 0) try buf.writer(self.allocator).writeAll(", ");
                    try buf.writer(self.allocator).writeAll(var_name);
                }

                try buf.writer(self.allocator).writeAll("| {");
                try self.emit(try buf.toOwnedSlice(self.allocator));

                self.indent();

                for (for_node.body) |stmt| {
                    try self.visitNode(stmt);
                }

                self.dedent();
                try self.emit("}");
            },
            else => return error.InvalidZipTarget,
        }
    }

    fn visitWhile(self: *ZigCodeGenerator, while_node: ast.Node.While) CodegenError!void {
        const test_result = try self.visitExpr(while_node.condition.*);

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("while ({s}) {{", .{test_result.code});
        try self.emit(try buf.toOwnedSlice(self.allocator));

        self.indent();

        for (while_node.body) |stmt| {
            try self.visitNode(stmt);
        }

        self.dedent();
        try self.emit("}");
    }

    fn visitFunctionDef(self: *ZigCodeGenerator, func: ast.Node.FunctionDef) CodegenError!void {
        // For now, generate simple functions with i64 parameters and return type
        // This handles common cases like fibonacci(n: int) -> int

        var buf = std.ArrayList(u8){};

        // Start function signature
        try buf.writer(self.allocator).print("fn {s}(", .{func.name});

        // Add parameters - assume i64 for now
        for (func.args, 0..) |arg, i| {
            if (i > 0) {
                try buf.writer(self.allocator).writeAll(", ");
            }
            try buf.writer(self.allocator).print("{s}: i64", .{arg.name});
        }

        // Add allocator parameter if needed
        if (self.needs_allocator) {
            if (func.args.len > 0) {
                try buf.writer(self.allocator).writeAll(", ");
            }
            try buf.writer(self.allocator).writeAll("allocator: std.mem.Allocator");
        }

        // Close signature - assume i64 return type for now
        try buf.writer(self.allocator).writeAll(") i64 {");

        try self.emit(try buf.toOwnedSlice(self.allocator));
        self.indent();

        // Generate function body
        for (func.body) |stmt| {
            try self.visitNode(stmt);
        }

        self.dedent();
        try self.emit("}");
    }

    fn visitReturn(self: *ZigCodeGenerator, ret: ast.Node.Return) CodegenError!void {
        if (ret.value) |value| {
            const value_result = try self.visitExpr(value.*);
            var buf = std.ArrayList(u8){};

            if (value_result.needs_try) {
                try buf.writer(self.allocator).print("return try {s};", .{value_result.code});
            } else {
                try buf.writer(self.allocator).print("return {s};", .{value_result.code});
            }

            try self.emit(try buf.toOwnedSlice(self.allocator));
        } else {
            try self.emit("return;");
        }
    }
};
