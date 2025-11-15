const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("../../codegen.zig").CodegenError;
const ExprResult = @import("../../codegen.zig").ExprResult;
const ZigCodeGenerator = @import("../../codegen.zig").ZigCodeGenerator;
const statements = @import("../statements.zig");
const expressions = @import("../expressions.zig");

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

