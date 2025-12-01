//! Code Builder Utilities - Fluent API for code generation
//!
//! Reduces boilerplate in codegen by providing reusable patterns.
//!
//! ## Examples
//!
//! ### Simple for loop
//! ```zig
//! var builder = CodeBuilder.init(codegen);
//! try builder.forLoop("items", "item").beginBlock();
//! try builder.line("std.debug.print(\"{}\", .{item});");
//! try builder.endBlock();
//! ```
//!
//! ### If statement with method call
//! ```zig
//! try builder.ifStmt("x > 0").beginBlock();
//! try builder.call("handlePositive", &[_][]const u8{"x"});
//! try builder.endBlock();
//! ```
//!
//! ### Variable declaration
//! ```zig
//! try builder.declareVar("result", "i64", true);
//! try builder.write(" = ");
//! try builder.call("calculate", &[_][]const u8{"a", "b"});
//! try builder.write(";\n");
//! ```

const std = @import("std");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

/// Fluent code builder for common patterns
pub const CodeBuilder = struct {
    codegen: *NativeCodegen,

    pub fn init(codegen: *NativeCodegen) CodeBuilder {
        return CodeBuilder{ .codegen = codegen };
    }

    /// Emit code with automatic indentation
    pub fn line(self: *CodeBuilder, code: []const u8) CodegenError!*CodeBuilder {
        try self.codegen.emitIndent();
        try self.codegen.emit(code);
        try self.codegen.emit("\n");
        return self;
    }

    /// Emit code without newline
    pub fn write(self: *CodeBuilder, code: []const u8) CodegenError!*CodeBuilder {
        try self.codegen.emit(code);
        return self;
    }

    /// Start a block with opening brace
    pub fn beginBlock(self: *CodeBuilder) CodegenError!*CodeBuilder {
        try self.codegen.emit(" {\n");
        self.codegen.indent();
        return self;
    }

    /// End a block with closing brace
    pub fn endBlock(self: *CodeBuilder) CodegenError!*CodeBuilder {
        self.codegen.dedent();
        try self.codegen.emitIndent();
        try self.codegen.emit("}\n");
        return self;
    }

    /// Emit formatted code
    pub fn fmt(
        self: *CodeBuilder,
        comptime format: []const u8,
        args: anytype,
    ) CodegenError!*CodeBuilder {
        var buf = std.ArrayList(u8){};
        try buf.writer(self.codegen.allocator).print(format, args);
        const code = try buf.toOwnedSlice(self.codegen.allocator);
        defer self.codegen.allocator.free(code);
        try self.codegen.emit(code);
        return self;
    }

    /// Generate for loop
    pub fn forLoop(
        self: *CodeBuilder,
        iterable: []const u8,
        var_name: []const u8,
    ) CodegenError!*CodeBuilder {
        try self.codegen.emitIndent();
        try self.fmt("for ({s}) |{s}|", .{ iterable, var_name });
        return self;
    }

    /// Generate while loop
    pub fn whileLoop(self: *CodeBuilder, condition: []const u8) CodegenError!*CodeBuilder {
        try self.codegen.emitIndent();
        try self.fmt("while ({s})", .{condition});
        return self;
    }

    /// Generate if statement
    pub fn ifStmt(self: *CodeBuilder, condition: []const u8) CodegenError!*CodeBuilder {
        try self.codegen.emitIndent();
        try self.fmt("if ({s})", .{condition});
        return self;
    }

    /// Generate else clause
    /// Closes the previous block and starts else (dedents then writes "} else")
    pub fn elseClause(self: *CodeBuilder) CodegenError!*CodeBuilder {
        self.codegen.dedent();
        try self.codegen.emitIndent();
        _ = try self.write("} else");
        return self;
    }

    /// Generate variable declaration
    pub fn declareVar(
        self: *CodeBuilder,
        var_name: []const u8,
        var_type: []const u8,
        is_mutable: bool,
    ) CodegenError!*CodeBuilder {
        try self.codegen.emitIndent();
        const keyword = if (is_mutable) "var" else "const";
        try self.fmt("{s} {s}: {s}", .{ keyword, var_name, var_type });
        return self;
    }

    /// Generate function call
    pub fn call(
        self: *CodeBuilder,
        func: []const u8,
        args: []const []const u8,
    ) CodegenError!*CodeBuilder {
        try self.fmt("{s}(", .{func});
        for (args, 0..) |arg, i| {
            if (i > 0) try self.write(", ");
            try self.write(arg);
        }
        try self.write(")");
        return self;
    }
};

/// Common code patterns
pub const Patterns = struct {
    /// Generate try-catch wrapper
    pub fn tryCatch(
        codegen: *NativeCodegen,
        body_code: []const u8,
        error_var: []const u8,
        catch_code: []const u8,
    ) CodegenError!void {
        var builder = CodeBuilder.init(codegen);

        try builder.line("(blk: {");
        codegen.indent();

        var buf = std.ArrayList(u8){};
        try buf.writer(codegen.allocator).print("    const result = {s} catch |{s}| {{", .{ body_code, error_var });
        const line1 = try buf.toOwnedSlice(codegen.allocator);
        defer codegen.allocator.free(line1);
        try builder.line(line1);

        codegen.indent();
        try builder.line(catch_code);
        codegen.dedent();
        try builder.line("    };");
        try builder.line("    break :blk result;");

        codegen.dedent();
        _ = try builder.line("})");
    }

    /// Generate array initialization
    pub fn arrayInit(
        codegen: *NativeCodegen,
        element_type: []const u8,
        elements: []const []const u8,
    ) CodegenError!void {
        var builder = CodeBuilder.init(codegen);

        _ = try builder.fmt("&[_]{s}{{", .{element_type});
        for (elements, 0..) |elem, i| {
            if (i > 0) _ = try builder.write(", ");
            _ = try builder.write(elem);
        }
        _ = try builder.write("}");
    }

    /// Generate struct initialization
    pub fn structInit(
        codegen: *NativeCodegen,
        struct_type: []const u8,
        fields: []const struct { name: []const u8, value: []const u8 },
    ) CodegenError!void {
        var builder = CodeBuilder.init(codegen);

        _ = try builder.fmt("{s}{{", .{struct_type});
        for (fields, 0..) |field, i| {
            if (i > 0) _ = try builder.write(", ");
            _ = try builder.fmt(".{s} = {s}", .{ field.name, field.value });
        }
        _ = try builder.write("}");
    }

    /// Generate defer statement
    pub fn defer_(codegen: *NativeCodegen, code: []const u8) CodegenError!void {
        var builder = CodeBuilder.init(codegen);
        _ = try builder.fmt("defer {s};", .{code});
        _ = try builder.write("\n");
    }

    /// Generate block expression
    pub fn blockExpr(
        codegen: *NativeCodegen,
        label: []const u8,
        body_code: []const u8,
    ) CodegenError!void {
        var builder = CodeBuilder.init(codegen);

        _ = try builder.fmt("({s}: {{", .{label});
        codegen.indent();
        _ = try builder.line(body_code);
        codegen.dedent();
        _ = try builder.line("})");
    }
};

/// String building utilities
pub const StringBuilder = struct {
    buffer: std.ArrayList(u8),

    pub fn init(_: std.mem.Allocator) StringBuilder {
        return StringBuilder{
            .buffer = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *StringBuilder, allocator: std.mem.Allocator) void {
        self.buffer.deinit(allocator);
    }

    pub fn append(self: *StringBuilder, allocator: std.mem.Allocator, s: []const u8) !void {
        try self.buffer.appendSlice(allocator, s);
    }

    pub fn appendFmt(
        self: *StringBuilder,
        allocator: std.mem.Allocator,
        comptime format: []const u8,
        args: anytype,
    ) !void {
        try self.buffer.writer(allocator).print(format, args);
    }

    pub fn toString(self: *StringBuilder, allocator: std.mem.Allocator) ![]const u8 {
        return try self.buffer.toOwnedSlice(allocator);
    }

    pub fn clear(self: *StringBuilder) void {
        self.buffer.clearRetainingCapacity();
    }
};

/// Template filling utilities (optional enhancement)
pub const Templates = struct {
    /// Fill template with values
    /// Example: fillTemplate("var {name}: {type}", .{ .name = "x", .type = "i64" })
    pub fn fillTemplate(
        allocator: std.mem.Allocator,
        template: []const u8,
        values: anytype,
    ) ![]const u8 {
        var result = std.ArrayList(u8){};

        var i: usize = 0;
        while (i < template.len) {
            if (template[i] == '{') {
                // Find closing }
                const start = i + 1;
                const end = std.mem.indexOfScalarPos(u8, template, start, '}') orelse {
                    try result.append(allocator, '{');
                    i += 1;
                    continue;
                };

                const key = template[start..end];

                // Look up key in values
                inline for (@typeInfo(@TypeOf(values)).Struct.fields) |field| {
                    if (std.mem.eql(u8, field.name, key)) {
                        const value = @field(values, field.name);
                        try result.appendSlice(allocator, @as([]const u8, value));
                        break;
                    }
                }

                i = end + 1;
            } else {
                try result.append(allocator, template[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(allocator);
    }
};
