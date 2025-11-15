const std = @import("std");
const ast = @import("../ast.zig");
const CodegenError = @import("../codegen.zig").CodegenError;
const ExprResult = @import("../codegen.zig").ExprResult;
const ZigCodeGenerator = @import("../codegen.zig").ZigCodeGenerator;
const expressions = @import("expressions.zig");
const statements = @import("statements.zig");

pub fn visitAttribute(self: *ZigCodeGenerator, attr: ast.Node.Attribute) CodegenError!ExprResult {
    // Check if base is an imported module (e.g., np in np.array)
    if (attr.value.* == .name) {
        const var_name = attr.value.name.id;
        if (self.imported_modules.contains(var_name)) {
            // This is a module attribute access (e.g., np.array)
            var buf = std.ArrayList(u8){};
            try buf.writer(self.temp_allocator).print(
                "try python.getattr(allocator, {s}, \"{s}\")",
                .{ var_name, attr.attr }
            );
            return ExprResult{
                .code = try buf.toOwnedSlice(self.temp_allocator),
                .needs_try = false,
                .needs_decref = false, // Python manages refcounting
            };
        }
    }

    // Regular attribute access (for PyObjects or user classes)
    const value_result = try expressions.visitExpr(self, attr.value.*);
    var buf = std.ArrayList(u8){};
    try buf.writer(self.temp_allocator).print("{s}.{s}", .{ value_result.code, attr.attr });
    return ExprResult{
        .code = try buf.toOwnedSlice(self.temp_allocator),
        .needs_try = false,
    };
}

pub fn visitClassInstantiation(self: *ZigCodeGenerator, class_name: []const u8, args: []ast.Node) CodegenError!ExprResult {
    var buf = std.ArrayList(u8){};
    try buf.writer(self.temp_allocator).print("{s}.init(", .{class_name});
    for (args, 0..) |arg, i| {
        if (i > 0) try buf.writer(self.temp_allocator).writeAll(", ");
        const arg_result = try expressions.visitExpr(self,arg);
        // Add 'try' if the argument needs it (e.g., PyString.create)
        if (arg_result.needs_try) {
            try buf.writer(self.temp_allocator).print("try {s}", .{arg_result.code});
        } else {
            try buf.writer(self.temp_allocator).writeAll(arg_result.code);
        }
    }
    try buf.writer(self.temp_allocator).writeAll(")");
    return ExprResult{
        .code = try buf.toOwnedSlice(self.temp_allocator),
        .needs_try = false,
    };
}

/// Check if method needs allocator parameter (returns PyObject)
fn methodNeedsAllocator(body: []ast.Node) bool {
    for (body) |node| {
        if (node == .return_stmt) {
            if (node.return_stmt.value) |ret_val| {
                // If returning a string constant, needs allocator
                if (ret_val.* == .constant) {
                    if (ret_val.constant.value == .string) {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

/// Infer return type from method body by checking for return statements
fn inferReturnType(body: []ast.Node) []const u8 {
    for (body) |node| {
        if (node == .return_stmt) {
            if (node.return_stmt.value) |ret_val| {
                // Check if returning a string constant
                if (ret_val.* == .constant) {
                    if (ret_val.constant.value == .string) {
                        return "!*runtime.PyObject";
                    }
                }
            }
            // Other return types default to i64
            return "i64";
        }
    }
    // No return statement found, method returns void
    return "void";
}

pub fn visitClassDef(self: *ZigCodeGenerator, class: ast.Node.ClassDef) CodegenError!void {
    try self.class_names.put(class.name, {});

    var buf = std.ArrayList(u8){};
    try buf.writer(self.temp_allocator).print("const {s} = struct {{", .{class.name});
    try self.emitOwned(try buf.toOwnedSlice(self.temp_allocator));
    self.indent();

    var init_method: ?ast.Node.FunctionDef = null;
    var methods = std.ArrayList(ast.Node.FunctionDef){};
    defer methods.deinit(self.allocator);

    // Collect methods from this class
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

    // If this class has base classes, inherit their methods
    if (class.bases.len > 0) {
        for (class.bases) |base_name| {
            if (self.class_methods.get(base_name)) |parent_methods| {
                // Add parent methods if not overridden
                for (parent_methods.items) |parent_method| {
                    var is_overridden = false;
                    for (methods.items) |child_method| {
                        if (std.mem.eql(u8, child_method.name, parent_method.name)) {
                            is_overridden = true;
                            break;
                        }
                    }
                    if (!is_overridden) {
                        try methods.append(self.allocator, parent_method);
                    }
                }
            }
        }
    }

    // Update class_has_methods after inheritance
    try self.class_has_methods.put(class.name, methods.items.len > 0);

    if (init_method) |init_func| {
        // First pass: determine field types from initializers
        var field_types = std.StringHashMap([]const u8).init(self.allocator);
        defer field_types.deinit();

        for (init_func.body) |stmt| {
            switch (stmt) {
                .assign => |assign| {
                    for (assign.targets) |target| {
                        switch (target) {
                            .attribute => |attr| {
                                switch (attr.value.*) {
                                    .name => |name| {
                                        if (std.mem.eql(u8, name.id, "self")) {
                                            // Infer type from value
                                            const field_type = blk: {
                                                switch (assign.value.*) {
                                                    .name => |val_name| {
                                                        // Look up parameter type from function args
                                                        for (init_func.args) |arg| {
                                                            if (std.mem.eql(u8, arg.name, val_name.id)) {
                                                                if (arg.type_annotation) |type_annot| {
                                                                    if (std.mem.eql(u8, type_annot, "str")) {
                                                                        break :blk "*runtime.PyObject";
                                                                    } else if (std.mem.eql(u8, type_annot, "int")) {
                                                                        break :blk "i64";
                                                                    }
                                                                }
                                                            }
                                                        }
                                                        break :blk "i64"; // Default
                                                    },
                                                    .constant => |c| {
                                                        if (c.value == .string) {
                                                            break :blk "*runtime.PyObject";
                                                        } else if (c.value == .int) {
                                                            break :blk "i64";
                                                        }
                                                        break :blk "i64";
                                                    },
                                                    else => break :blk "i64",
                                                }
                                            };
                                            try field_types.put(attr.attr, field_type);
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

        // Second pass: emit field declarations with correct types
        for (init_func.body) |stmt| {
            switch (stmt) {
                .assign => |assign| {
                    for (assign.targets) |target| {
                        switch (target) {
                            .attribute => |attr| {
                                switch (attr.value.*) {
                                    .name => |name| {
                                        if (std.mem.eql(u8, name.id, "self")) {
                                            const field_type = field_types.get(attr.attr) orelse "i64";
                                            var field_buf = std.ArrayList(u8){};
                                            try field_buf.writer(self.temp_allocator).print("{s}: {s},", .{attr.attr, field_type});
                                            try self.emitOwned(try field_buf.toOwnedSlice(self.temp_allocator));
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
        try buf.writer(self.temp_allocator).writeAll("pub fn init(");

        for (init_func.args, 0..) |arg, i| {
            if (std.mem.eql(u8, arg.name, "self")) continue;
            if (i > 1) try buf.writer(self.temp_allocator).writeAll(", ");

            // Infer parameter type from annotation
            const param_type = blk: {
                if (arg.type_annotation) |type_annot| {
                    if (std.mem.eql(u8, type_annot, "str")) {
                        break :blk "*runtime.PyObject";
                    } else if (std.mem.eql(u8, type_annot, "int")) {
                        break :blk "i64";
                    }
                }
                break :blk "i64"; // Default
            };
            try buf.writer(self.temp_allocator).print("{s}: {s}", .{arg.name, param_type});
        }

        try buf.writer(self.temp_allocator).print(") {s} {{", .{class.name});
        try self.emitOwned(try buf.toOwnedSlice(self.temp_allocator));
        self.indent();

        buf = std.ArrayList(u8){};
        try buf.writer(self.temp_allocator).print("return {s}{{", .{class.name});
        try self.emitOwned(try buf.toOwnedSlice(self.temp_allocator));
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
                                            const value_result = try expressions.visitExpr(self,assign.value.*);
                                            buf = std.ArrayList(u8){};
                                            try buf.writer(self.temp_allocator).print(".{s} = {s},", .{ attr.attr, value_result.code });
                                            try self.emitOwned(try buf.toOwnedSlice(self.temp_allocator));
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
        try buf.writer(self.temp_allocator).print("pub fn {s}(", .{method.name});

        // Check if method needs allocator
        const needs_allocator = methodNeedsAllocator(method.body);

        for (method.args, 0..) |arg, i| {
            if (i > 0) try buf.writer(self.temp_allocator).writeAll(", ");
            if (std.mem.eql(u8, arg.name, "self")) {
                // Use _ prefix to allow unused self
                try buf.writer(self.temp_allocator).print("_self: *{s}", .{class.name});
            } else {
                try buf.writer(self.temp_allocator).print("{s}: i64", .{arg.name});
            }
        }

        // Add allocator parameter if method needs it
        if (needs_allocator) {
            try buf.writer(self.temp_allocator).writeAll(", _allocator: std.mem.Allocator");
        }

        // Infer return type from method body
        const return_type = inferReturnType(method.body);

        // Store method return type for later wrapping in visitMethodCall
        // Key format: "ClassName.methodName" -> "i64" | "void"
        const method_key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{class.name, method.name});
        try self.method_return_types.put(method_key, return_type);

        try buf.writer(self.temp_allocator).print(") {s} {{", .{return_type});
        try self.emitOwned(try buf.toOwnedSlice(self.temp_allocator));
        self.indent();

        // Create aliases for parameters (Zig allows unused with _ prefix on param)
        try self.emit("const self = _self;");
        if (needs_allocator) {
            try self.emit("const allocator = _allocator;");
        }

        for (method.body) |stmt| {
            try statements.visitNode(self, stmt);
        }

        self.dedent();
        try self.emit("}");
    }

    self.dedent();
    try self.emit("};");

    // Store methods for this class so children can inherit them
    var stored_methods = std.ArrayList(ast.Node.FunctionDef){};
    for (methods.items) |method| {
        try stored_methods.append(self.allocator, method);
    }
    try self.class_methods.put(class.name, stored_methods);
}

/// Helper function to wrap primitive constants as PyObjects
fn wrapPrimitiveIfNeeded(self: *ZigCodeGenerator, node: ast.Node, arg_code: []const u8) ![]const u8 {
    switch (node) {
        .constant => |c| {
            switch (c.value) {
                .int => {
                    return try std.fmt.allocPrint(self.temp_allocator,
                        "try runtime.PyInt.create(allocator, {s})", .{arg_code});
                },
                .string => {
                    return try std.fmt.allocPrint(self.temp_allocator,
                        "try runtime.PyString.create(allocator, {s})", .{arg_code});
                },
                .bool => {
                    return try std.fmt.allocPrint(self.temp_allocator,
                        "runtime.PyBool.create({s})", .{arg_code});
                },
                .float => {
                    return try std.fmt.allocPrint(self.temp_allocator,
                        "try runtime.PyFloat.create(allocator, {s})", .{arg_code});
                },
            }
        },
        else => return arg_code,
    }
}

/// Helper function to wrap primitive as PyObject and create temp variable with defer decref
fn wrapPrimitiveWithDecref(self: *ZigCodeGenerator, node: ast.Node, arg_result: ExprResult) ![]const u8 {
    const needs_wrap = switch (node) {
        .constant => |c| switch (c.value) {
            .int, .string, .float => true,
            else => false,
        },
        else => false,
    };

    if (needs_wrap) {
        // Create wrapped version WITHOUT 'try' - extractResultToStatement will add it
        var wrapped_code_buf = std.ArrayList(u8){};
        switch (node) {
            .constant => |c| {
                switch (c.value) {
                    .int => try wrapped_code_buf.writer(self.temp_allocator).print("runtime.PyInt.create(allocator, {s})", .{arg_result.code}),
                    .string => try wrapped_code_buf.writer(self.temp_allocator).print("runtime.PyString.create(allocator, {s})", .{arg_result.code}),
                    .float => try wrapped_code_buf.writer(self.temp_allocator).print("runtime.PyFloat.create(allocator, {s})", .{arg_result.code}),
                    else => unreachable,
                }
            },
            else => unreachable,
        }
        const wrapped_code = try wrapped_code_buf.toOwnedSlice(self.temp_allocator);
        const wrapped_result = ExprResult{
            .code = wrapped_code,
            .needs_try = true,
            .needs_decref = true,
        };
        // Extract to statement with defer decref
        return try self.extractResultToStatement(wrapped_result);
    } else {
        // Not a primitive, use as-is
        return arg_result.code;
    }
}
pub fn visitMethodCall(self: *ZigCodeGenerator, attr: ast.Node.Attribute, args: []ast.Node) CodegenError!ExprResult {
    const obj_result = try expressions.visitExpr(self,attr.value.*);
    // Extract object to statement if it needs try (e.g., constant strings)
    const obj_code = try self.extractResultToStatement(obj_result);
    const method_name = attr.attr;
    var buf = std.ArrayList(u8){};

    // Check if this is a Python function call (e.g., np.array([1, 2, 3]))
    const is_python_call = blk: {
        switch (attr.value.*) {
            .name => |obj_name| {
                if (self.imported_modules.contains(obj_name.id)) {
                    break :blk true;
                }
            },
            else => {},
        }
        break :blk false;
    };

    if (is_python_call) {
        return try visitPythonFunctionCall(self, obj_code, method_name, args);
    }

    // Check if this is a user-defined class method call
    // If the object is a class instance (not a PyObject type), handle it first
    const is_class_method = blk: {
        switch (attr.value.*) {
            .name => |obj_name| {
                const var_type = self.var_types.get(obj_name.id);
                // If no type info or not a PyObject type, assume it's a class instance
                if (var_type == null) {
                    break :blk true;
                }
                // Not a PyObject built-in type
                if (!std.mem.eql(u8, var_type.?, "pyobject") and
                    !std.mem.eql(u8, var_type.?, "string") and
                    !std.mem.eql(u8, var_type.?, "list") and
                    !std.mem.eql(u8, var_type.?, "dict"))
                {
                    break :blk true;
                }
                break :blk false;
            },
            else => break :blk false,
        }
    };

    if (is_class_method) {
        // Get class name from var_type to look up method return type
        const class_name = blk: {
            switch (attr.value.*) {
                .name => |obj_name| {
                    if (self.var_types.get(obj_name.id)) |vt| {
                        break :blk vt;
                    }
                },
                else => {},
            }
            break :blk null;
        };

        // Check if method returns PyObject (needs allocator)
        var method_needs_alloc = false;
        if (class_name) |cname| {
            const method_key = try std.fmt.allocPrint(self.temp_allocator, "{s}.{s}", .{cname, method_name});
            if (self.method_return_types.get(method_key)) |return_type| {
                if (std.mem.eql(u8, return_type, "!*runtime.PyObject")) {
                    method_needs_alloc = true;
                }
            }
        }

        // User-defined class method - generate obj.method(args)
        try buf.writer(self.temp_allocator).print("{s}.{s}(", .{ obj_code, method_name });
        for (args, 0..) |arg, i| {
            if (i > 0) try buf.writer(self.temp_allocator).writeAll(", ");
            const arg_result = try expressions.visitExpr(self,arg);
            if (arg_result.needs_try) {
                try buf.writer(self.temp_allocator).print("try {s}", .{arg_result.code});
            } else {
                try buf.writer(self.temp_allocator).writeAll(arg_result.code);
            }
        }

        // Add allocator argument if method needs it
        if (method_needs_alloc) {
            if (args.len > 0) try buf.writer(self.temp_allocator).writeAll(", ");
            try buf.writer(self.temp_allocator).writeAll("allocator");
            self.needs_allocator = true;
        }

        try buf.writer(self.temp_allocator).writeAll(")");

        const method_call_code = try buf.toOwnedSlice(self.temp_allocator);

        if (class_name) |cname| {
            const method_key = try std.fmt.allocPrint(self.temp_allocator, "{s}.{s}", .{cname, method_name});
            if (self.method_return_types.get(method_key)) |return_type| {
                if (std.mem.eql(u8, return_type, "i64")) {
                    // Wrap i64 return in PyInt
                    self.needs_runtime = true;
                    self.needs_allocator = true;
                    var wrap_buf = std.ArrayList(u8){};
                    try wrap_buf.writer(self.temp_allocator).print("runtime.PyInt.create(allocator, {s})", .{method_call_code});
                    return ExprResult{
                        .code = try wrap_buf.toOwnedSlice(self.temp_allocator),
                        .needs_try = true,
                        .needs_decref = true,
                    };
                } else if (std.mem.eql(u8, return_type, "!*runtime.PyObject")) {
                    // Method returns PyObject with error, needs try
                    return ExprResult{ .code = method_call_code, .needs_try = true, .needs_decref = true };
                }
                // void methods don't return values, return as-is
                // Future: add f64, bool support
            }
        }

        return ExprResult{ .code = method_call_code, .needs_try = false };
    }

    // String methods
    if (std.mem.eql(u8, method_name, "upper")) {
        try buf.writer(self.temp_allocator).print("runtime.PyString.upper(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "lower")) {
        try buf.writer(self.temp_allocator).print("runtime.PyString.lower(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "strip")) {
        try buf.writer(self.temp_allocator).print("runtime.PyString.strip(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "lstrip")) {
        try buf.writer(self.temp_allocator).print("runtime.PyString.lstrip(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "rstrip")) {
        try buf.writer(self.temp_allocator).print("runtime.PyString.rstrip(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "split")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        const arg_code = try self.extractResultToStatement(arg_result);
        try buf.writer(self.temp_allocator).print("runtime.PyString.split(allocator, {s}, {s})", .{ obj_code, arg_code });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "replace")) {
        if (args.len != 2) return error.InvalidArguments;
        const arg1_result = try expressions.visitExpr(self,args[0]);
        const arg2_result = try expressions.visitExpr(self,args[1]);
        const arg1_code = try self.extractResultToStatement(arg1_result);
        const arg2_code = try self.extractResultToStatement(arg2_result);
        try buf.writer(self.temp_allocator).print("runtime.PyString.replace(allocator, {s}, {s}, {s})", .{ obj_code, arg1_code, arg2_code });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "capitalize")) {
        try buf.writer(self.temp_allocator).print("runtime.PyString.capitalize(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "swapcase")) {
        try buf.writer(self.temp_allocator).print("runtime.PyString.swapcase(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "title")) {
        try buf.writer(self.temp_allocator).print("runtime.PyString.title(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "center")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        const arg_code = try self.extractResultToStatement(arg_result);
        try buf.writer(self.temp_allocator).print("runtime.PyString.center(allocator, {s}, {s})", .{ obj_code, arg_code });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "join")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        const arg_code = try self.extractResultToStatement(arg_result);
        try buf.writer(self.temp_allocator).print("runtime.PyString.join(allocator, {s}, {s})", .{ obj_code, arg_code });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "startswith")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        const arg_code = try self.extractResultToStatement(arg_result);
        // Returns bool, wrap in PyInt (1 for true, 0 for false)
        try buf.writer(self.temp_allocator).print("runtime.PyInt.create(allocator, if (runtime.PyString.startswith({s}, {s})) 1 else 0)", .{ obj_code, arg_code });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "endswith")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        const arg_code = try self.extractResultToStatement(arg_result);
        // Returns bool, wrap in PyInt (1 for true, 0 for false)
        try buf.writer(self.temp_allocator).print("runtime.PyInt.create(allocator, if (runtime.PyString.endswith({s}, {s})) 1 else 0)", .{ obj_code, arg_code });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "isdigit")) {
        // Returns bool, wrap in PyInt (1 for true, 0 for false)
        try buf.writer(self.temp_allocator).print("runtime.PyInt.create(allocator, if (runtime.PyString.isdigit({s})) 1 else 0)", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "isalpha")) {
        // Returns bool, wrap in PyInt (1 for true, 0 for false)
        try buf.writer(self.temp_allocator).print("runtime.PyInt.create(allocator, if (runtime.PyString.isalpha({s})) 1 else 0)", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "find")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        const arg_code = try self.extractResultToStatement(arg_result);
        // Returns i64, wrap in PyInt
        try buf.writer(self.temp_allocator).print("runtime.PyInt.create(allocator, runtime.PyString.find({s}, {s}))", .{ obj_code, arg_code });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    }
    // List methods
    else if (std.mem.eql(u8, method_name, "append")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        const wrapped_arg = try wrapPrimitiveIfNeeded(self, args[0], arg_result.code);
        try buf.writer(self.temp_allocator).print("runtime.PyList.append({s}, {s})", .{ obj_code, wrapped_arg });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "pop")) {
        try buf.writer(self.temp_allocator).print("runtime.PyList.pop(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "extend")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        try buf.writer(self.temp_allocator).print("runtime.PyList.extend({s}, {s})", .{ obj_code, arg_result.code });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "reverse")) {
        try buf.writer(self.temp_allocator).print("runtime.PyList.reverse({s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = false };
    } else if (std.mem.eql(u8, method_name, "remove")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        const wrapped_arg = try wrapPrimitiveWithDecref(self, args[0], arg_result);
        try buf.writer(self.temp_allocator).print("runtime.PyList.remove(allocator, {s}, {s})", .{ obj_code, wrapped_arg });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "count")) {
        if (args.len != 1) return error.InvalidArguments;

        // Check if this is a string or list count
        const is_string = blk: {
            switch (attr.value.*) {
                .name => |obj_name| {
                    const var_type = self.var_types.get(obj_name.id);
                    if (var_type) |vt| {
                        if (std.mem.eql(u8, vt, "string")) {
                            break :blk true;
                        }
                    }
                },
                .constant => |c| {
                    if (c.value == .string) {
                        break :blk true;
                    }
                },
                else => {},
            }
            break :blk false;
        };

        const arg_result = try expressions.visitExpr(self,args[0]);
        const arg_code = try self.extractResultToStatement(arg_result);

        if (is_string) {
            // String count - returns i64, wrap in PyInt
            try buf.writer(self.temp_allocator).print("runtime.PyInt.create(allocator, runtime.PyString.count_substr({s}, {s}))", .{ obj_code, arg_code });
            return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
        } else {
            // List count - returns i64, no wrapping needed (already returns i64)
            const wrapped_arg = try wrapPrimitiveWithDecref(self, args[0], arg_result);
            try buf.writer(self.temp_allocator).print("runtime.PyList.count({s}, {s})", .{ obj_code, wrapped_arg });
            return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = false };
        }
    } else if (std.mem.eql(u8, method_name, "index")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        const wrapped_arg = try wrapPrimitiveWithDecref(self, args[0], arg_result);
        try buf.writer(self.temp_allocator).print("runtime.PyList.index({s}, {s})", .{ obj_code, wrapped_arg });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = false };
    } else if (std.mem.eql(u8, method_name, "insert")) {
        if (args.len != 2) return error.InvalidArguments;
        const arg1_result = try expressions.visitExpr(self,args[0]);
        const arg2_result = try expressions.visitExpr(self,args[1]);
        const wrapped_arg2 = try wrapPrimitiveIfNeeded(self, args[1], arg2_result.code);
        try buf.writer(self.temp_allocator).print("runtime.PyList.insert(allocator, {s}, {s}, {s})", .{ obj_code, arg1_result.code, wrapped_arg2 });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "clear")) {
        try buf.writer(self.temp_allocator).print("runtime.PyList.clear(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = false };
    } else if (std.mem.eql(u8, method_name, "sort")) {
        try buf.writer(self.temp_allocator).print("runtime.PyList.sort({s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = false };
    } else if (std.mem.eql(u8, method_name, "copy")) {
        try buf.writer(self.temp_allocator).print("runtime.PyList.copy(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    }
    // Dict methods
    else if (std.mem.eql(u8, method_name, "keys")) {
        try buf.writer(self.temp_allocator).print("runtime.PyDict.keys(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "values")) {
        try buf.writer(self.temp_allocator).print("runtime.PyDict.values(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "get")) {
        if (args.len < 1 or args.len > 2) return error.InvalidArguments;
        const key_result = try expressions.visitExpr(self,args[0]);
        const key_code = if (key_result.needs_try)
            try std.fmt.allocPrint(self.allocator, "try {s}", .{key_result.code})
        else
            key_result.code;
        const default_result = if (args.len == 2)
            try expressions.visitExpr(self,args[1])
        else
            ExprResult{ .code = "runtime.PyNone", .needs_try = false };
        const default_code = if (default_result.needs_try)
            try std.fmt.allocPrint(self.allocator, "try {s}", .{default_result.code})
        else
            default_result.code;
        try buf.writer(self.temp_allocator).print("runtime.PyDict.get_method(allocator, {s}, {s}, {s})", .{ obj_code, key_code, default_code });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = false };
    } else if (std.mem.eql(u8, method_name, "items")) {
        try buf.writer(self.temp_allocator).print("runtime.PyDict.items(allocator, {s})", .{obj_code});
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else if (std.mem.eql(u8, method_name, "update")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        try buf.writer(self.temp_allocator).print("runtime.PyDict.update({s}, {s})", .{ obj_code, arg_result.code });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = true };
    } else {
        // Attempt to handle user-defined class methods
        // Generate generic method call: obj.method(args)
        // If obj is a class instance, Zig will resolve the method call
        buf = std.ArrayList(u8){};
        try buf.writer(self.temp_allocator).print("{s}.{s}(", .{ obj_code, method_name });

        for (args, 0..) |arg, i| {
            if (i > 0) try buf.writer(self.temp_allocator).writeAll(", ");
            const arg_result = try expressions.visitExpr(self,arg);
            if (arg_result.needs_try) {
                try buf.writer(self.temp_allocator).print("try {s}", .{arg_result.code});
            } else {
                try buf.writer(self.temp_allocator).writeAll(arg_result.code);
            }
        }

        try buf.writer(self.temp_allocator).writeAll(")");
        const method_call_code = try buf.toOwnedSlice(self.temp_allocator);

        // Check if we need to wrap the return value (primitive -> PyObject)
        // Get class name from var_type to look up method return type
        const class_name = blk: {
            switch (attr.value.*) {
                .name => |obj_name| {
                    if (self.var_types.get(obj_name.id)) |vt| {
                        break :blk vt;
                    }
                },
                else => {},
            }
            break :blk null;
        };

        if (class_name) |cname| {
            const method_key = try std.fmt.allocPrint(self.temp_allocator, "{s}.{s}", .{cname, method_name});
            if (self.method_return_types.get(method_key)) |return_type| {
                if (std.mem.eql(u8, return_type, "i64")) {
                    // Wrap i64 return in PyInt
                    self.needs_runtime = true;
                    self.needs_allocator = true;
                    var wrap_buf = std.ArrayList(u8){};
                    try wrap_buf.writer(self.temp_allocator).print("runtime.PyInt.create(allocator, {s})", .{method_call_code});
                    return ExprResult{
                        .code = try wrap_buf.toOwnedSlice(self.temp_allocator),
                        .needs_try = true,
                        .needs_decref = true,
                    };
                }
                // void methods don't return values, return as-is
                // Future: add f64, bool support
            }
        }

        return ExprResult{ .code = method_call_code, .needs_try = false };
    }
}

/// Handle Python function calls like np.array([1, 2, 3]) and native modules like json.loads()
fn visitPythonFunctionCall(self: *ZigCodeGenerator, module_code: []const u8, func_name: []const u8, args: []ast.Node) CodegenError!ExprResult {
    self.needs_allocator = true;

    // Check for native JSON module calls (json.loads, json.dumps)
    const is_json_loads = std.mem.eql(u8, func_name, "loads");
    const is_json_dumps = std.mem.eql(u8, func_name, "dumps");

    if (is_json_loads or is_json_dumps) {
        // Native JSON handling
        if (args.len == 0) return error.MissingArgument;

        const arg_result = try expressions.visitExpr(self, args[0]);
        const arg_code = try self.extractResultToStatement(arg_result);

        var buf = std.ArrayList(u8){};
        if (is_json_loads) {
            // json.loads(json_str) -> runtime.jsonLoads(json_str, allocator)
            try buf.writer(self.temp_allocator).print("runtime.jsonLoads({s}, allocator)", .{arg_code});
        } else {
            // json.dumps(obj) -> runtime.jsonDumps(obj, allocator)
            try buf.writer(self.temp_allocator).print("runtime.jsonDumps({s}, allocator)", .{arg_code});
        }

        const code = try buf.toOwnedSlice(self.temp_allocator);
        return ExprResult{ .code = code, .needs_try = true, .needs_decref = true };
    }

    // Check for native HTTP module calls (http.get)
    const is_http_get = std.mem.eql(u8, func_name, "get");

    if (is_http_get) {
        // Native HTTP handling
        if (args.len == 0) return error.MissingArgument;

        const arg_result = try expressions.visitExpr(self, args[0]);
        const arg_code = try self.extractResultToStatement(arg_result);

        var buf = std.ArrayList(u8){};
        // http.get(url) -> runtime.httpGet(allocator, url)
        try buf.writer(self.temp_allocator).print("runtime.httpGet(allocator, {s})", .{arg_code});

        const code = try buf.toOwnedSlice(self.temp_allocator);
        return ExprResult{ .code = code, .needs_try = true, .needs_decref = true };
    }

    // Python FFI function call
    self.needs_python = true;

    // Get the function attribute from module
    var func_buf = std.ArrayList(u8){};
    try func_buf.writer(self.temp_allocator).print("python.getattr(allocator, {s}, \"{s}\")", .{ module_code, func_name });
    const func_code = try func_buf.toOwnedSlice(self.temp_allocator);

    // Convert arguments to Python objects
    var arg_codes = std.ArrayList([]const u8){};

    for (args) |arg| {
        const arg_result = try expressions.visitExpr(self, arg);
        const arg_code = try self.extractResultToStatement(arg_result);

        // Convert Zig type to Python object
        const converted = try convertToPythonObject(self, arg, arg_result, arg_code);
        try arg_codes.append(self.temp_allocator, converted);
    }

    // Build argument array
    var buf = std.ArrayList(u8){};
    try buf.writer(self.temp_allocator).print("python.callPythonFunction(allocator, try {s}, &[_]*anyopaque{{", .{func_code});

    for (arg_codes.items, 0..) |arg_code, i| {
        if (i > 0) try buf.writer(self.temp_allocator).writeAll(", ");
        try buf.writer(self.temp_allocator).print("@ptrCast({s})", .{arg_code});
    }

    try buf.writer(self.temp_allocator).writeAll("})");

    const code = try buf.toOwnedSlice(self.temp_allocator);
    return ExprResult{ .code = code, .needs_try = true, .needs_decref = false };
}

/// Convert Zig value to Python object (*anyopaque)
fn convertToPythonObject(self: *ZigCodeGenerator, node: ast.Node, result: ExprResult, code: []const u8) CodegenError![]const u8 {
    _ = result; // May use this later for type info

    var buf = std.ArrayList(u8){};

    // Check if it's a constant that needs conversion
    switch (node) {
        .constant => |c| {
            switch (c.value) {
                .string => {
                    // String literal - code is already "runtime.PyString.create(...)"
                    // Just wrap in try since it returns !*PyObject
                    try buf.writer(self.temp_allocator).print("try {s}", .{code});
                    return try buf.toOwnedSlice(self.temp_allocator);
                },
                .int => |num| {
                    // Integer literal - convert to Python int
                    try buf.writer(self.temp_allocator).print("try python.fromInt({d})", .{num});
                    return try buf.toOwnedSlice(self.temp_allocator);
                },
                .float => |f| {
                    // Float literal - convert to Python float
                    try buf.writer(self.temp_allocator).print("try python.fromFloat({d})", .{f});
                    return try buf.toOwnedSlice(self.temp_allocator);
                },
                .bool => |b| {
                    // Bool literal - convert to Python bool (as int 0/1)
                    const val: i64 = if (b) 1 else 0;
                    try buf.writer(self.temp_allocator).print("try python.fromInt({d})", .{val});
                    return try buf.toOwnedSlice(self.temp_allocator);
                },
            }
        },
        .list => |list_node| {
            // List literal - for Python FFI, create a Python list, not PyAOT list
            // Check if all elements are integers
            var all_ints = true;
            var int_values = std.ArrayList(i64){};

            for (list_node.elts) |elt| {
                if (elt != .constant or elt.constant.value != .int) {
                    all_ints = false;
                    break;
                }
                try int_values.append(self.temp_allocator, elt.constant.value.int);
            }

            if (all_ints and int_values.items.len > 0) {
                // Create Python list from integers
                try buf.writer(self.temp_allocator).writeAll("try python.listFromInts(&[_]i64{");
                for (int_values.items, 0..) |val, i| {
                    if (i > 0) try buf.writer(self.temp_allocator).writeAll(", ");
                    try buf.writer(self.temp_allocator).print("{d}", .{val});
                }
                try buf.writer(self.temp_allocator).writeAll("})");
                return try buf.toOwnedSlice(self.temp_allocator);
            } else {
                // Fallback: use existing PyList code
                try buf.writer(self.temp_allocator).writeAll(code);
                return try buf.toOwnedSlice(self.temp_allocator);
            }
        },
        .name => {
            // Variable reference - check type to determine conversion
            const var_type = self.var_types.get(code);
            if (var_type) |vtype| {
                if (std.mem.eql(u8, vtype, "list")) {
                    // PyAOT list - convert to Python list for FFI
                    try buf.writer(self.temp_allocator).print("try python.convertPyListToPython({s})", .{code});
                    return try buf.toOwnedSlice(self.temp_allocator);
                } else if (std.mem.eql(u8, vtype, "string") or
                    std.mem.eql(u8, vtype, "dict") or
                    std.mem.eql(u8, vtype, "pyobject")) {
                    // Already a PyObject type (but not list)
                    try buf.writer(self.temp_allocator).writeAll(code);
                    return try buf.toOwnedSlice(self.temp_allocator);
                } else {
                    // Primitive type (i64, f64, bool) - convert
                    try buf.writer(self.temp_allocator).print("try python.fromInt({s})", .{code});
                    return try buf.toOwnedSlice(self.temp_allocator);
                }
            }
            // Unknown type, assume it's already suitable
            try buf.writer(self.temp_allocator).writeAll(code);
            return try buf.toOwnedSlice(self.temp_allocator);
        },
        else => {
            // Other expressions - assume they're already PyObjects
            try buf.writer(self.temp_allocator).writeAll(code);
            return try buf.toOwnedSlice(self.temp_allocator);
        },
    }
}
