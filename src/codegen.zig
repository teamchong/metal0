const std = @import("std");
const ast = @import("ast.zig");

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
const ExprResult = struct {
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
                try self.visitClassDef(node.class_def);
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
    fn visitNode(self: *ZigCodeGenerator, node: ast.Node) CodegenError!void {
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

    // Helper methods
    fn visitCompareOp(self: *ZigCodeGenerator, op: ast.CompareOp) []const u8 {
        _ = self;
        return switch (op) {
            .Lt => "<",
            .LtEq => "<=",
            .Gt => ">",
            .GtEq => ">=",
            .Eq => "==",
            .NotEq => "!=",
            .In => "in", // Will need special handling
            .NotIn => "not in", // Will need special handling
        };
    }

    fn visitBinOpHelper(self: *ZigCodeGenerator, op: ast.Operator) []const u8 {
        _ = self;
        return switch (op) {
            .Add => "+",
            .Sub => "-",
            .Mult => "*",
            .Div => "/",
            .Mod => "%",
            .FloorDiv => "//", // Handled specially in visitBinOp
            .Pow => "**", // Handled specially in visitBinOp
            .BitAnd => "&",
            .BitOr => "|",
            .BitXor => "^",
        };
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

                // Use 'var' for class instances (to allow field mutations) or reassigned vars
                const var_keyword = if (is_class_instance or self.reassigned_vars.contains(var_name)) "var" else "const";

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
                const attr_result = try self.visitAttribute(attr);

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

    fn visitExpr(self: *ZigCodeGenerator, node: ast.Node) CodegenError!ExprResult {
        return switch (node) {
            .name => |name| ExprResult{
                .code = name.id,
                .needs_try = false,
            },

            .constant => |constant| self.visitConstant(constant),

            .binop => |binop| self.visitBinOp(binop),

            .unaryop => |unaryop| self.visitUnaryOp(unaryop),

            .boolop => |boolop| self.visitBoolOp(boolop),

            .attribute => |attr| self.visitAttribute(attr),

            .call => |call| self.visitCall(call),

            .compare => |compare| self.visitCompare(compare),

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

    fn visitBinOp(self: *ZigCodeGenerator, binop: ast.Node.BinOp) CodegenError!ExprResult {
        const left_result = try self.visitExpr(binop.left.*);
        const right_result = try self.visitExpr(binop.right.*);

        var buf = std.ArrayList(u8){};

        // Handle operators that need special Zig functions
        switch (binop.op) {
            .FloorDiv => {
                // Floor division: use @divFloor builtin
                try buf.writer(self.allocator).print("@divFloor({s}, {s})", .{ left_result.code, right_result.code });
            },
            .Pow => {
                // Exponentiation: use std.math.pow
                try buf.writer(self.allocator).print("std.math.pow(i64, {s}, {s})", .{ left_result.code, right_result.code });
            },
            else => {
                // Standard operators that map directly to Zig operators
                const op_str = self.visitBinOpHelper(binop.op);
                try buf.writer(self.allocator).print("{s} {s} {s}", .{ left_result.code, op_str, right_result.code });
            },
        }

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = left_result.needs_try or right_result.needs_try,
        };
    }

    fn visitCompare(self: *ZigCodeGenerator, compare: ast.Node.Compare) CodegenError!ExprResult {
        if (compare.ops.len == 0 or compare.comparators.len == 0) {
            return error.InvalidCompare;
        }

        const left_result = try self.visitExpr(compare.left.*);
        const right_result = try self.visitExpr(compare.comparators[0]);

        const op = compare.ops[0];
        var buf = std.ArrayList(u8){};

        // Handle 'in' and 'not in' operators specially
        if (op == .In or op == .NotIn) {
            self.needs_runtime = true;

            // Wrap left operand if it's a primitive constant
            var left_code = left_result.code;
            if (compare.left.* == .constant) {
                const constant = compare.left.*.constant;
                switch (constant.value) {
                    .int => {
                        left_code = try std.fmt.allocPrint(self.allocator, "try runtime.PyInt.create(allocator, {s})", .{left_result.code});
                    },
                    .string => {
                        // Strings are already wrapped by visitConstant
                    },
                    .bool => {
                        left_code = try std.fmt.allocPrint(self.allocator, "try runtime.PyBool.create(allocator, {s})", .{left_result.code});
                    },
                    .float => {
                        left_code = try std.fmt.allocPrint(self.allocator, "try runtime.PyFloat.create(allocator, {s})", .{left_result.code});
                    },
                }
            }

            if (op == .In) {
                try buf.writer(self.allocator).print("runtime.contains({s}, {s})", .{ left_code, right_result.code });
            } else {
                try buf.writer(self.allocator).print("!runtime.contains({s}, {s})", .{ left_code, right_result.code });
            }
        } else {
            const op_str = self.visitCompareOp(op);
            try buf.writer(self.allocator).print("{s} {s} {s}", .{ left_result.code, op_str, right_result.code });
        }

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
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
                    return self.visitPrintCall(call.args);
                } else if (std.mem.eql(u8, func_name.id, "len")) {
                    return self.visitLenCall(call.args);
                } else if (std.mem.eql(u8, func_name.id, "abs")) {
                    return self.visitAbsCall(call.args);
                } else if (std.mem.eql(u8, func_name.id, "round")) {
                    return self.visitRoundCall(call.args);
                } else if (std.mem.eql(u8, func_name.id, "min")) {
                    return self.visitMinCall(call.args);
                } else if (std.mem.eql(u8, func_name.id, "max")) {
                    return self.visitMaxCall(call.args);
                } else if (std.mem.eql(u8, func_name.id, "sum")) {
                    return self.visitSumCall(call.args);
                } else if (std.mem.eql(u8, func_name.id, "all")) {
                    return self.visitAllCall(call.args);
                } else if (std.mem.eql(u8, func_name.id, "any")) {
                    return self.visitAnyCall(call.args);
                } else {
                    // Check if this is a class instantiation
                    if (self.class_names.contains(func_name.id)) {
                        return self.visitClassInstantiation(func_name.id, call.args);
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
                return self.visitMethodCall(attr, call.args);
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

    fn visitMethodCall(self: *ZigCodeGenerator, attr: ast.Node.Attribute, args: []ast.Node) CodegenError!ExprResult {
        const obj_result = try self.visitExpr(attr.value.*);
        const method_name = attr.attr;
        var buf = std.ArrayList(u8){};

        // String methods
        if (std.mem.eql(u8, method_name, "upper")) {
            try buf.writer(self.allocator).print("runtime.PyString.upper(allocator, {s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "lower")) {
            try buf.writer(self.allocator).print("runtime.PyString.lower(allocator, {s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "strip")) {
            try buf.writer(self.allocator).print("runtime.PyString.strip(allocator, {s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "lstrip")) {
            try buf.writer(self.allocator).print("runtime.PyString.lstrip(allocator, {s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "rstrip")) {
            try buf.writer(self.allocator).print("runtime.PyString.rstrip(allocator, {s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "split")) {
            if (args.len != 1) return error.InvalidArguments;
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.PyString.split(allocator, {s}, {s})", .{ obj_result.code, arg_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "replace")) {
            if (args.len != 2) return error.InvalidArguments;
            const arg1_result = try self.visitExpr(args[0]);
            const arg2_result = try self.visitExpr(args[1]);
            try buf.writer(self.allocator).print("runtime.PyString.replace(allocator, {s}, {s}, {s})", .{ obj_result.code, arg1_result.code, arg2_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "capitalize")) {
            try buf.writer(self.allocator).print("runtime.PyString.capitalize(allocator, {s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "swapcase")) {
            try buf.writer(self.allocator).print("runtime.PyString.swapcase(allocator, {s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "title")) {
            try buf.writer(self.allocator).print("runtime.PyString.title(allocator, {s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "center")) {
            if (args.len != 1) return error.InvalidArguments;
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.PyString.center(allocator, {s}, {s})", .{ obj_result.code, arg_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "join")) {
            if (args.len != 1) return error.InvalidArguments;
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.PyString.join(allocator, {s}, {s})", .{ obj_result.code, arg_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "startswith")) {
            if (args.len != 1) return error.InvalidArguments;
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.PyString.startswith({s}, {s})", .{ obj_result.code, arg_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = false };
        } else if (std.mem.eql(u8, method_name, "endswith")) {
            if (args.len != 1) return error.InvalidArguments;
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.PyString.endswith({s}, {s})", .{ obj_result.code, arg_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = false };
        } else if (std.mem.eql(u8, method_name, "isdigit")) {
            try buf.writer(self.allocator).print("runtime.PyString.isdigit({s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = false };
        } else if (std.mem.eql(u8, method_name, "isalpha")) {
            try buf.writer(self.allocator).print("runtime.PyString.isalpha({s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = false };
        } else if (std.mem.eql(u8, method_name, "find")) {
            if (args.len != 1) return error.InvalidArguments;
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.PyString.find({s}, {s})", .{ obj_result.code, arg_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = false };
        }
        // List methods
        else if (std.mem.eql(u8, method_name, "append")) {
            if (args.len != 1) return error.InvalidArguments;
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.PyList.append({s}, {s})", .{ obj_result.code, arg_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "pop")) {
            try buf.writer(self.allocator).print("runtime.PyList.pop(allocator, {s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "extend")) {
            if (args.len != 1) return error.InvalidArguments;
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.PyList.extend({s}, {s})", .{ obj_result.code, arg_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "reverse")) {
            try buf.writer(self.allocator).print("runtime.PyList.reverse({s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = false };
        } else if (std.mem.eql(u8, method_name, "remove")) {
            if (args.len != 1) return error.InvalidArguments;
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.PyList.remove(allocator, {s}, {s})", .{ obj_result.code, arg_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "count")) {
            if (args.len != 1) return error.InvalidArguments;
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.PyList.count({s}, {s})", .{ obj_result.code, arg_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = false };
        } else if (std.mem.eql(u8, method_name, "index")) {
            if (args.len != 1) return error.InvalidArguments;
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.PyList.index({s}, {s})", .{ obj_result.code, arg_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = false };
        } else if (std.mem.eql(u8, method_name, "insert")) {
            if (args.len != 2) return error.InvalidArguments;
            const arg1_result = try self.visitExpr(args[0]);
            const arg2_result = try self.visitExpr(args[1]);
            try buf.writer(self.allocator).print("runtime.PyList.insert(allocator, {s}, {s}, {s})", .{ obj_result.code, arg1_result.code, arg2_result.code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else if (std.mem.eql(u8, method_name, "clear")) {
            try buf.writer(self.allocator).print("runtime.PyList.clear(allocator, {s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = false };
        } else if (std.mem.eql(u8, method_name, "sort")) {
            try buf.writer(self.allocator).print("runtime.PyList.sort({s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = false };
        } else if (std.mem.eql(u8, method_name, "copy")) {
            try buf.writer(self.allocator).print("runtime.PyList.copy(allocator, {s})", .{obj_result.code});
            return ExprResult{ .code = try buf.toOwnedSlice(self.allocator), .needs_try = true };
        } else {
            return error.UnsupportedMethod;
        }
    }
    fn visitPrintCall(self: *ZigCodeGenerator, args: []ast.Node) CodegenError!ExprResult {
        if (args.len == 0) {
            return ExprResult{
                .code = "std.debug.print(\"\\n\", .{})",
                .needs_try = false,
            };
        }

        const arg = args[0];
        const arg_result = try self.visitExpr(arg);

        var buf = std.ArrayList(u8){};

        // Determine print format based on variable type
        switch (arg) {
            .name => |name| {
                const var_type = self.var_types.get(name.id);
                if (var_type) |vtype| {
                    if (std.mem.eql(u8, vtype, "string")) {
                        try buf.writer(self.allocator).print("std.debug.print(\"{{s}}\\n\", .{{runtime.PyString.getValue({s})}})", .{arg_result.code});
                    } else {
                        try buf.writer(self.allocator).print("std.debug.print(\"{{}}\\n\", .{{{s}}})", .{arg_result.code});
                    }
                } else {
                    try buf.writer(self.allocator).print("std.debug.print(\"{{}}\\n\", .{{{s}}})", .{arg_result.code});
                }
            },
            else => {
                // For string constants, use getValue
                const is_string_const = switch (arg) {
                    .constant => |c| c.value == .string,
                    else => false,
                };

                if (is_string_const) {
                    try buf.writer(self.allocator).print("std.debug.print(\"{{s}}\\n\", .{{runtime.PyString.getValue(try {s})}})", .{arg_result.code});
                } else if (arg_result.needs_try) {
                    try buf.writer(self.allocator).print("std.debug.print(\"{{}}\\n\", .{{try {s}}})", .{arg_result.code});
                } else {
                    try buf.writer(self.allocator).print("std.debug.print(\"{{}}\\n\", .{{{s}}})", .{arg_result.code});
                }
            },
        }

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitLenCall(self: *ZigCodeGenerator, args: []ast.Node) CodegenError!ExprResult {
        if (args.len == 0) return error.MissingLenArg;

        const arg = args[0];
        const arg_result = try self.visitExpr(arg);

        var buf = std.ArrayList(u8){};

        // Check variable type to determine which len() to call
        switch (arg) {
            .name => |name| {
                const var_type = self.var_types.get(name.id);
                if (var_type) |vtype| {
                    if (std.mem.eql(u8, vtype, "list")) {
                        try buf.writer(self.allocator).print("runtime.PyList.len({s})", .{arg_result.code});
                    } else if (std.mem.eql(u8, vtype, "string")) {
                        try buf.writer(self.allocator).print("runtime.PyString.len({s})", .{arg_result.code});
                    } else {
                        try buf.writer(self.allocator).print("runtime.PyList.len({s})", .{arg_result.code});
                    }
                } else {
                    try buf.writer(self.allocator).print("runtime.PyList.len({s})", .{arg_result.code});
                }
            },
            else => {
                try buf.writer(self.allocator).print("runtime.PyList.len({s})", .{arg_result.code});
            },
        }

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitAbsCall(self: *ZigCodeGenerator, args: []ast.Node) CodegenError!ExprResult {
        if (args.len == 0) return error.MissingLenArg;

        const arg = args[0];
        const arg_result = try self.visitExpr(arg);

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("@abs({s})", .{arg_result.code});

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitRoundCall(self: *ZigCodeGenerator, args: []ast.Node) CodegenError!ExprResult {
        if (args.len == 0) return error.MissingLenArg;

        const arg = args[0];
        const arg_result = try self.visitExpr(arg);

        var buf = std.ArrayList(u8){};
        // Python's round() returns an int, Zig's @round() returns same type
        // Cast to i64 to match Python behavior
        try buf.writer(self.allocator).print("@as(i64, @intFromFloat(@round({s})))", .{arg_result.code});

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitMinCall(self: *ZigCodeGenerator, args: []ast.Node) CodegenError!ExprResult {
        if (args.len == 0) return error.MissingLenArg;

        var buf = std.ArrayList(u8){};

        if (args.len == 1) {
            // min([1, 2, 3]) - list argument - needs runtime
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.minList({s})", .{arg_result.code});
        } else if (args.len == 2) {
            // min(a, b) - use @min builtin
            const arg1 = try self.visitExpr(args[0]);
            const arg2 = try self.visitExpr(args[1]);
            try buf.writer(self.allocator).print("@min({s}, {s})", .{ arg1.code, arg2.code });
        } else {
            // min(a, b, c, ...) - chain @min calls
            var result_code = try self.visitExpr(args[0]);
            for (args[1..]) |arg| {
                const arg_result = try self.visitExpr(arg);
                var temp_buf = std.ArrayList(u8){};
                try temp_buf.writer(self.allocator).print("@min({s}, {s})", .{ result_code.code, arg_result.code });
                result_code.code = try temp_buf.toOwnedSlice(self.allocator);
            }
            return result_code;
        }

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitMaxCall(self: *ZigCodeGenerator, args: []ast.Node) CodegenError!ExprResult {
        if (args.len == 0) return error.MissingLenArg;

        var buf = std.ArrayList(u8){};

        if (args.len == 1) {
            // max([1, 2, 3]) - list argument - needs runtime
            const arg_result = try self.visitExpr(args[0]);
            try buf.writer(self.allocator).print("runtime.maxList({s})", .{arg_result.code});
        } else if (args.len == 2) {
            // max(a, b) - use @max builtin
            const arg1 = try self.visitExpr(args[0]);
            const arg2 = try self.visitExpr(args[1]);
            try buf.writer(self.allocator).print("@max({s}, {s})", .{ arg1.code, arg2.code });
        } else {
            // max(a, b, c, ...) - chain @max calls
            var result_code = try self.visitExpr(args[0]);
            for (args[1..]) |arg| {
                const arg_result = try self.visitExpr(arg);
                var temp_buf = std.ArrayList(u8){};
                try temp_buf.writer(self.allocator).print("@max({s}, {s})", .{ result_code.code, arg_result.code });
                result_code.code = try temp_buf.toOwnedSlice(self.allocator);
            }
            return result_code;
        }

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitSumCall(self: *ZigCodeGenerator, args: []ast.Node) CodegenError!ExprResult {
        if (args.len == 0) return error.MissingLenArg;

        const arg = args[0];
        const arg_result = try self.visitExpr(arg);

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("runtime.sum({s})", .{arg_result.code});

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitAllCall(self: *ZigCodeGenerator, args: []ast.Node) CodegenError!ExprResult {
        if (args.len == 0) return error.MissingLenArg;

        const arg = args[0];
        const arg_result = try self.visitExpr(arg);

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("runtime.all({s})", .{arg_result.code});

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitAnyCall(self: *ZigCodeGenerator, args: []ast.Node) CodegenError!ExprResult {
        if (args.len == 0) return error.MissingLenArg;

        const arg = args[0];
        const arg_result = try self.visitExpr(arg);

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("runtime.any({s})", .{arg_result.code});

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

    fn visitBoolOp(self: *ZigCodeGenerator, boolop: ast.Node.BoolOp) CodegenError!ExprResult {
        if (boolop.values.len < 2) {
            return error.UnsupportedExpression;
        }

        const left_result = try self.visitExpr(boolop.values[0]);
        const right_result = try self.visitExpr(boolop.values[1]);

        const op_str = switch (boolop.op) {
            .And => "and",
            .Or => "or",
        };

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("({s} {s} {s})", .{ left_result.code, op_str, right_result.code });

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = left_result.needs_try or right_result.needs_try,
        };
    }

    fn visitUnaryOp(self: *ZigCodeGenerator, unaryop: ast.Node.UnaryOp) CodegenError!ExprResult {
        const operand_result = try self.visitExpr(unaryop.operand.*);

        const op_str = switch (unaryop.op) {
            .Not => "!",
            .USub => "-",
            .UAdd => "+",
        };

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("{s}({s})", .{ op_str, operand_result.code });

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = operand_result.needs_try,
        };
    }

    fn visitAttribute(self: *ZigCodeGenerator, attr: ast.Node.Attribute) CodegenError!ExprResult {
        const value_result = try self.visitExpr(attr.value.*);
        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("{s}.{s}", .{ value_result.code, attr.attr });
        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitClassInstantiation(self: *ZigCodeGenerator, class_name: []const u8, args: []ast.Node) CodegenError!ExprResult {
        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("{s}.init(", .{class_name});
        for (args, 0..) |arg, i| {
            if (i > 0) try buf.writer(self.allocator).writeAll(", ");
            const arg_result = try self.visitExpr(arg);
            try buf.writer(self.allocator).writeAll(arg_result.code);
        }
        try buf.writer(self.allocator).writeAll(")");
        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitClassDef(self: *ZigCodeGenerator, class: ast.Node.ClassDef) CodegenError!void {
        try self.class_names.put(class.name, {});
        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("const {s} = struct {{", .{class.name});
        try self.emit(try buf.toOwnedSlice(self.allocator));
        self.indent();

        var init_method: ?ast.Node.FunctionDef = null;
        var methods = std.ArrayList(ast.Node.FunctionDef){};
        defer methods.deinit(self.allocator);

        for (class.body) |node| {
            switch (node) {
                .function_def => |func| {
                    if (std.mem.eql(u8, func.name, "__init__")) {
                        init_method = func;
                    } else {
                        try methods.append(self.allocator, func);
                    }
                },
                else => {},
            }
        }

        if (init_method) |init_func| {
            for (init_func.body) |stmt| {
                switch (stmt) {
                    .assign => |assign| {
                        for (assign.targets) |target| {
                            switch (target) {
                                .attribute => |attr| {
                                    switch (attr.value.*) {
                                        .name => |name| {
                                            if (std.mem.eql(u8, name.id, "self")) {
                                                var field_buf = std.ArrayList(u8){};
                                                try field_buf.writer(self.allocator).print("{s}: i64,", .{attr.attr});
                                                try self.emit(try field_buf.toOwnedSlice(self.allocator));
                                            }
                                        },
                                        else => {},
                                    }
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            }

            try self.emit("");
            buf = std.ArrayList(u8){};
            try buf.writer(self.allocator).writeAll("pub fn init(");

            for (init_func.args, 0..) |arg, i| {
                if (std.mem.eql(u8, arg.name, "self")) continue;
                if (i > 1) try buf.writer(self.allocator).writeAll(", ");
                try buf.writer(self.allocator).print("{s}: i64", .{arg.name});
            }

            try buf.writer(self.allocator).print(") {s} {{", .{class.name});
            try self.emit(try buf.toOwnedSlice(self.allocator));
            self.indent();

            buf = std.ArrayList(u8){};
            try buf.writer(self.allocator).print("return {s}{{", .{class.name});
            try self.emit(try buf.toOwnedSlice(self.allocator));
            self.indent();

            for (init_func.body) |stmt| {
                switch (stmt) {
                    .assign => |assign| {
                        for (assign.targets) |target| {
                            switch (target) {
                                .attribute => |attr| {
                                    switch (attr.value.*) {
                                        .name => |name| {
                                            if (std.mem.eql(u8, name.id, "self")) {
                                                const value_result = try self.visitExpr(assign.value.*);
                                                buf = std.ArrayList(u8){};
                                                try buf.writer(self.allocator).print(".{s} = {s},", .{ attr.attr, value_result.code });
                                                try self.emit(try buf.toOwnedSlice(self.allocator));
                                            }
                                        },
                                        else => {},
                                    }
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            }

            self.dedent();
            try self.emit("};");
            self.dedent();
            try self.emit("}");
        }

        for (methods.items) |method| {
            try self.emit("");
            buf = std.ArrayList(u8){};
            try buf.writer(self.allocator).print("pub fn {s}(", .{method.name});

            for (method.args, 0..) |arg, i| {
                if (i > 0) try buf.writer(self.allocator).writeAll(", ");
                if (std.mem.eql(u8, arg.name, "self")) {
                    try buf.writer(self.allocator).print("self: *{s}", .{class.name});
                } else {
                    try buf.writer(self.allocator).print("{s}: i64", .{arg.name});
                }
            }

            try buf.writer(self.allocator).writeAll(") void {");
            try self.emit(try buf.toOwnedSlice(self.allocator));
            self.indent();

            for (method.body) |stmt| {
                try self.visitNode(stmt);
            }

            self.dedent();
            try self.emit("}");
        }

        self.dedent();
        try self.emit("};");
    }
};
