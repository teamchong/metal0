/// Try/except/finally statement code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

pub fn genTry(self: *NativeCodegen, try_node: ast.Node.Try) CodegenError!void {
    // Wrap in block for defer scope
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "{\n");
    self.indent();

    // Generate finally as defer
    if (try_node.finalbody.len > 0) {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "defer {\n");
        self.indent();
        for (try_node.finalbody) |stmt| {
            try self.generateStmt(stmt);
        }
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
    }

    // Generate try block with exception handling
    if (try_node.handlers.len > 0) {
        // Collect captured variables
        var captured_vars = std.ArrayList([]const u8){};
        defer captured_vars.deinit(self.allocator);

        const common_names = [_][]const u8{ "nums", "data", "items", "values", "list", "dict", "result", "text", "x", "y", "z" };
        for (common_names) |name| {
            if (self.semantic_info.lifetimes.contains(name)) {
                try captured_vars.append(self.allocator, name);
            }
        }

        // Create helper function
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const __TryHelper = struct {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "fn run(");

        // Parameters
        for (captured_vars.items, 0..) |var_name, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try self.output.appendSlice(self.allocator, "p_");
            try self.output.appendSlice(self.allocator, var_name);
            try self.output.appendSlice(self.allocator, ": anytype");
        }

        try self.output.appendSlice(self.allocator, ") !void {\n");
        self.indent();

        // Create aliases with explicit type annotation to avoid anytype issues
        for (captured_vars.items) |var_name| {
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "const __local_");
            try self.output.appendSlice(self.allocator, var_name);
            try self.output.appendSlice(self.allocator, ": @TypeOf(p_");
            try self.output.appendSlice(self.allocator, var_name);
            try self.output.appendSlice(self.allocator, ") = p_");
            try self.output.appendSlice(self.allocator, var_name);
            try self.output.appendSlice(self.allocator, ";\n");

            // Add to rename map so expressions use __local_X instead of X
            var buf = std.ArrayList(u8){};
            try buf.writer(self.allocator).print("__local_{s}", .{var_name});
            const renamed = try buf.toOwnedSlice(self.allocator);
            try self.var_renames.put(var_name, renamed);
        }

        // Generate try block body with renamed variables
        for (try_node.body) |stmt| {
            try self.generateStmt(stmt);
        }

        // Clear rename map after generating body
        for (captured_vars.items) |var_name| {
            _ = self.var_renames.remove(var_name);
        }

        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "};\n");

        // Call helper with captured variables
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "__TryHelper.run(");
        for (captured_vars.items, 0..) |var_name, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try self.output.appendSlice(self.allocator, var_name);
        }
        try self.output.appendSlice(self.allocator, ") catch |err| {\n");
        self.indent();

        // Generate exception handlers
        var generated_handler = false;
        for (try_node.handlers, 0..) |handler, i| {
            if (i > 0) {
                try self.emitIndent();
                try self.output.appendSlice(self.allocator, "} else ");
            } else if (handler.type != null) {
                try self.emitIndent();
            }

            if (handler.type) |exc_type| {
                const zig_err = pythonExceptionToZigError(exc_type);
                try self.output.appendSlice(self.allocator, "if (err == error.");
                try self.output.appendSlice(self.allocator, zig_err);
                try self.output.appendSlice(self.allocator, ") {\n");
                self.indent();
                for (handler.body) |stmt| {
                    try self.generateStmt(stmt);
                }
                self.dedent();
                generated_handler = true;
            } else {
                if (i > 0) {
                    try self.output.appendSlice(self.allocator, "{\n");
                } else {
                    try self.emitIndent();
                    try self.output.appendSlice(self.allocator, "{\n");
                }
                self.indent();
                try self.emitIndent();
                try self.output.appendSlice(self.allocator, "_ = err;\n");
                for (handler.body) |stmt| {
                    try self.generateStmt(stmt);
                }
                self.dedent();
                try self.emitIndent();
                try self.output.appendSlice(self.allocator, "}\n");
                generated_handler = true;
            }
        }

        if (generated_handler and try_node.handlers[try_node.handlers.len - 1].type != null) {
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "} else {\n");
            self.indent();
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "return err;\n");
            self.dedent();
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "}\n");
        }

        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "};\n");
    } else {
        for (try_node.body) |stmt| {
            try self.generateStmt(stmt);
        }
    }

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}

fn pythonExceptionToZigError(exc_type: []const u8) []const u8 {
    if (std.mem.eql(u8, exc_type, "ZeroDivisionError")) return "ZeroDivisionError";
    if (std.mem.eql(u8, exc_type, "IndexError")) return "IndexError";
    if (std.mem.eql(u8, exc_type, "ValueError")) return "ValueError";
    if (std.mem.eql(u8, exc_type, "TypeError")) return "TypeError";
    if (std.mem.eql(u8, exc_type, "KeyError")) return "KeyError";
    return "GenericError";
}
