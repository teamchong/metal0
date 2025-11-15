const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("../../codegen.zig").CodegenError;
const ExprResult = @import("../../codegen.zig").ExprResult;
const ZigCodeGenerator = @import("../../codegen.zig").ZigCodeGenerator;
const expressions = @import("../expressions.zig");
const python_ffi = @import("python_ffi.zig");
const instantiation = @import("instantiation.zig");

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
        return try python_ffi.visitPythonFunctionCall(self, obj_code, method_name, args);
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
        const wrapped_arg = try instantiation.wrapPrimitiveIfNeeded(self, args[0], arg_result.code);
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
        const wrapped_arg = try instantiation.wrapPrimitiveWithDecref(self, args[0], arg_result);
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
            const wrapped_arg = try instantiation.wrapPrimitiveWithDecref(self, args[0], arg_result);
            try buf.writer(self.temp_allocator).print("runtime.PyList.count({s}, {s})", .{ obj_code, wrapped_arg });
            return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = false };
        }
    } else if (std.mem.eql(u8, method_name, "index")) {
        if (args.len != 1) return error.InvalidArguments;
        const arg_result = try expressions.visitExpr(self,args[0]);
        const wrapped_arg = try instantiation.wrapPrimitiveWithDecref(self, args[0], arg_result);
        try buf.writer(self.temp_allocator).print("runtime.PyList.index({s}, {s})", .{ obj_code, wrapped_arg });
        return ExprResult{ .code = try buf.toOwnedSlice(self.temp_allocator), .needs_try = false };
    } else if (std.mem.eql(u8, method_name, "insert")) {
        if (args.len != 2) return error.InvalidArguments;
        const arg1_result = try expressions.visitExpr(self,args[0]);
        const arg2_result = try expressions.visitExpr(self,args[1]);
        const wrapped_arg2 = try instantiation.wrapPrimitiveIfNeeded(self, args[1], arg2_result.code);
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

