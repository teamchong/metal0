//! test.test_tools.test_clinic - Argument Clinic testing
//! Tests for Python's Argument Clinic tool which generates argument parsing code
//! for C extension modules from a domain-specific language.

const std = @import("std");

/// Represents a function parameter in Argument Clinic syntax
pub const ClinicParameter = struct {
    name: []const u8,
    type_annotation: TypeAnnotation,
    default_value: ?[]const u8 = null,
    docstring: ?[]const u8 = null,
    positional_only: bool = false,
    keyword_only: bool = false,
    required: bool = true,
    converter: ?[]const u8 = null,

    pub const TypeAnnotation = enum {
        object,
        str,
        int,
        float,
        bool,
        bytes,
        bytearray,
        size_t,
        ssize_t,
        py_buffer,
        sequence,
        mapping,
        iterable,
        callable,
        none,
    };

    pub fn isOptional(self: ClinicParameter) bool {
        return self.default_value != null or !self.required;
    }

    pub fn formatSignature(self: ClinicParameter, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        try result.appendSlice(self.name);
        try result.appendSlice(": ");
        try result.appendSlice(@tagName(self.type_annotation));

        if (self.default_value) |default| {
            try result.appendSlice(" = ");
            try result.appendSlice(default);
        }

        return result.toOwnedSlice();
    }
};

/// Represents a function definition in Argument Clinic
pub const ClinicFunction = struct {
    module: []const u8,
    class: ?[]const u8 = null,
    name: []const u8,
    parameters: []const ClinicParameter,
    return_type: ?[]const u8 = null,
    docstring: ?[]const u8 = null,
    coexist: bool = false,

    pub fn fullName(self: ClinicFunction, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        try result.appendSlice(self.module);
        if (self.class) |cls| {
            try result.append('.');
            try result.appendSlice(cls);
        }
        try result.append('.');
        try result.appendSlice(self.name);

        return result.toOwnedSlice();
    }

    pub fn positionalCount(self: ClinicFunction) usize {
        var count: usize = 0;
        for (self.parameters) |param| {
            if (!param.keyword_only) {
                count += 1;
            }
        }
        return count;
    }

    pub fn keywordCount(self: ClinicFunction) usize {
        var count: usize = 0;
        for (self.parameters) |param| {
            if (param.keyword_only) {
                count += 1;
            }
        }
        return count;
    }

    pub fn requiredCount(self: ClinicFunction) usize {
        var count: usize = 0;
        for (self.parameters) |param| {
            if (param.required and param.default_value == null) {
                count += 1;
            }
        }
        return count;
    }
};

/// Converter registry for type converters
pub const ConverterRegistry = struct {
    allocator: std.mem.Allocator,
    converters: std.StringHashMap(Converter),

    pub const Converter = struct {
        name: []const u8,
        c_type: []const u8,
        format_unit: u8,
        needs_cleanup: bool = false,
        py_type: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator) ConverterRegistry {
        var self = ConverterRegistry{
            .allocator = allocator,
            .converters = std.StringHashMap(Converter).init(allocator),
        };
        self.registerBuiltins() catch {};
        return self;
    }

    pub fn deinit(self: *ConverterRegistry) void {
        self.converters.deinit();
    }

    fn registerBuiltins(self: *ConverterRegistry) !void {
        try self.converters.put("object", .{
            .name = "object",
            .c_type = "PyObject *",
            .format_unit = 'O',
        });
        try self.converters.put("str", .{
            .name = "str",
            .c_type = "const char *",
            .format_unit = 's',
        });
        try self.converters.put("int", .{
            .name = "int",
            .c_type = "int",
            .format_unit = 'i',
        });
        try self.converters.put("long", .{
            .name = "long",
            .c_type = "long",
            .format_unit = 'l',
        });
        try self.converters.put("Py_ssize_t", .{
            .name = "Py_ssize_t",
            .c_type = "Py_ssize_t",
            .format_unit = 'n',
        });
        try self.converters.put("float", .{
            .name = "float",
            .c_type = "float",
            .format_unit = 'f',
        });
        try self.converters.put("double", .{
            .name = "double",
            .c_type = "double",
            .format_unit = 'd',
        });
        try self.converters.put("bool", .{
            .name = "bool",
            .c_type = "int",
            .format_unit = 'p',
        });
    }

    pub fn get(self: ConverterRegistry, name: []const u8) ?Converter {
        return self.converters.get(name);
    }

    pub fn register(self: *ConverterRegistry, converter: Converter) !void {
        try self.converters.put(converter.name, converter);
    }
};

/// Parser for Argument Clinic DSL
pub const ClinicParser = struct {
    allocator: std.mem.Allocator,
    current_module: ?[]const u8 = null,
    current_class: ?[]const u8 = null,
    errors: std.ArrayList(ParseError),

    pub const ParseError = struct {
        line: usize,
        column: usize,
        message: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) ClinicParser {
        return .{
            .allocator = allocator,
            .errors = std.ArrayList(ParseError).init(allocator),
        };
    }

    pub fn deinit(self: *ClinicParser) void {
        self.errors.deinit();
    }

    pub fn parseDirective(self: *ClinicParser, line: []const u8) !?Directive {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        if (std.mem.startsWith(u8, trimmed, "module ")) {
            self.current_module = trimmed[7..];
            return .{ .module = trimmed[7..] };
        } else if (std.mem.startsWith(u8, trimmed, "class ")) {
            self.current_class = trimmed[6..];
            return .{ .class = trimmed[6..] };
        } else if (std.mem.startsWith(u8, trimmed, "@")) {
            return .{ .decorator = trimmed[1..] };
        } else if (std.mem.eql(u8, trimmed, "[clinic start generated code]")) {
            return .start_generated;
        } else if (std.mem.eql(u8, trimmed, "[clinic end generated code")) {
            return .end_generated;
        }

        return null;
    }

    pub const Directive = union(enum) {
        module: []const u8,
        class: []const u8,
        decorator: []const u8,
        start_generated,
        end_generated,
    };

    pub fn parseParameter(self: *ClinicParser, line: []const u8) !ClinicParameter {
        _ = self;
        var param = ClinicParameter{
            .name = "",
            .type_annotation = .object,
        };

        var parts = std.mem.split(u8, line, ":");
        if (parts.next()) |name_part| {
            param.name = std.mem.trim(u8, name_part, " \t");
        }
        if (parts.next()) |type_part| {
            const type_str = std.mem.trim(u8, type_part, " \t");
            param.type_annotation = parseTypeAnnotation(type_str);
        }

        return param;
    }

    fn parseTypeAnnotation(type_str: []const u8) ClinicParameter.TypeAnnotation {
        const mapping = .{
            .{ "str", .str },
            .{ "int", .int },
            .{ "float", .float },
            .{ "bool", .bool },
            .{ "bytes", .bytes },
            .{ "bytearray", .bytearray },
            .{ "object", .object },
        };

        inline for (mapping) |entry| {
            if (std.mem.eql(u8, type_str, entry[0])) {
                return entry[1];
            }
        }
        return .object;
    }

    pub fn hasErrors(self: ClinicParser) bool {
        return self.errors.items.len > 0;
    }
};

/// Code generator for Argument Clinic output
pub const ClinicCodeGenerator = struct {
    allocator: std.mem.Allocator,
    registry: *ConverterRegistry,
    output: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, registry: *ConverterRegistry) ClinicCodeGenerator {
        return .{
            .allocator = allocator,
            .registry = registry,
            .output = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *ClinicCodeGenerator) void {
        self.output.deinit();
    }

    pub fn generateParseArgs(self: *ClinicCodeGenerator, func: ClinicFunction) ![]u8 {
        try self.output.appendSlice("static PyObject *\n");
        try self.output.appendSlice(func.name);
        try self.output.appendSlice("_impl(");

        // Generate parameter list
        for (func.parameters, 0..) |param, i| {
            if (i > 0) {
                try self.output.appendSlice(", ");
            }
            if (self.registry.get(@tagName(param.type_annotation))) |converter| {
                try self.output.appendSlice(converter.c_type);
            } else {
                try self.output.appendSlice("PyObject *");
            }
            try self.output.appendSlice(param.name);
        }

        try self.output.appendSlice(");\n");

        return try self.output.toOwnedSlice();
    }

    pub fn generateMethodDef(self: *ClinicCodeGenerator, func: ClinicFunction) ![]u8 {
        try self.output.appendSlice("{\"");
        try self.output.appendSlice(func.name);
        try self.output.appendSlice("\", ");

        const method_type: []const u8 = if (func.keywordCount() > 0)
            "METH_VARARGS | METH_KEYWORDS"
        else if (func.positionalCount() == 0)
            "METH_NOARGS"
        else
            "METH_VARARGS";

        try self.output.appendSlice(method_type);
        try self.output.appendSlice(", ");
        try self.output.appendSlice(func.name);
        try self.output.appendSlice("_doc},\n");

        return try self.output.toOwnedSlice();
    }
};

/// Signature object representing a callable's signature
pub const Signature = struct {
    name: []const u8,
    parameters: []const SignatureParameter,
    return_annotation: ?[]const u8 = null,

    pub const SignatureParameter = struct {
        name: []const u8,
        kind: ParameterKind,
        default: ?[]const u8 = null,
        annotation: ?[]const u8 = null,

        pub const ParameterKind = enum {
            positional_only,
            positional_or_keyword,
            var_positional,
            keyword_only,
            var_keyword,
        };
    };

    pub fn formatTextSignature(self: Signature, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        try result.appendSlice(self.name);
        try result.append('(');

        var saw_kw_only = false;
        for (self.parameters, 0..) |param, i| {
            if (i > 0) {
                try result.appendSlice(", ");
            }

            // Handle / for positional-only
            if (i > 0 and self.parameters[i - 1].kind == .positional_only and param.kind != .positional_only) {
                try result.appendSlice("/, ");
            }

            // Handle * for keyword-only
            if (!saw_kw_only and param.kind == .keyword_only) {
                try result.appendSlice("*, ");
                saw_kw_only = true;
            }

            switch (param.kind) {
                .var_positional => try result.append('*'),
                .var_keyword => try result.appendSlice("**"),
                else => {},
            }

            try result.appendSlice(param.name);

            if (param.annotation) |ann| {
                try result.appendSlice(": ");
                try result.appendSlice(ann);
            }

            if (param.default) |def| {
                try result.appendSlice("=");
                try result.appendSlice(def);
            }
        }

        try result.append(')');

        if (self.return_annotation) |ret| {
            try result.appendSlice(" -> ");
            try result.appendSlice(ret);
        }

        return result.toOwnedSlice();
    }
};

/// Docstring parser and formatter
pub const DocstringFormatter = struct {
    allocator: std.mem.Allocator,
    width: usize = 72,
    indent: []const u8 = "    ",

    pub fn init(allocator: std.mem.Allocator) DocstringFormatter {
        return .{ .allocator = allocator };
    }

    pub fn formatForC(self: DocstringFormatter, docstring: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try result.appendSlice("PyDoc_STRVAR(doc,\n");

        var lines = std.mem.split(u8, docstring, "\n");
        while (lines.next()) |line| {
            try result.appendSlice("\"");
            // Escape special characters
            for (line) |c| {
                switch (c) {
                    '"' => try result.appendSlice("\\\""),
                    '\\' => try result.appendSlice("\\\\"),
                    '\n' => try result.appendSlice("\\n"),
                    '\t' => try result.appendSlice("\\t"),
                    else => try result.append(c),
                }
            }
            try result.appendSlice("\\n\"\n");
        }

        try result.appendSlice(");\n");

        return result.toOwnedSlice();
    }

    pub fn extractSummary(self: DocstringFormatter, docstring: []const u8) []const u8 {
        _ = self;
        // First paragraph is the summary
        if (std.mem.indexOf(u8, docstring, "\n\n")) |idx| {
            return docstring[0..idx];
        }
        return docstring;
    }
};

// Tests
test "clinic_parameter_basic" {
    const param = ClinicParameter{
        .name = "value",
        .type_annotation = .int,
        .default_value = "0",
    };
    try std.testing.expect(param.isOptional());
    try std.testing.expect(!param.required or param.default_value != null);
}

test "clinic_parameter_signature" {
    const param = ClinicParameter{
        .name = "name",
        .type_annotation = .str,
        .default_value = "None",
    };
    const sig = try param.formatSignature(std.testing.allocator);
    defer std.testing.allocator.free(sig);
    try std.testing.expectEqualStrings("name: str = None", sig);
}

test "clinic_function_counts" {
    const func = ClinicFunction{
        .module = "os",
        .name = "open",
        .parameters = &[_]ClinicParameter{
            .{ .name = "path", .type_annotation = .str },
            .{ .name = "flags", .type_annotation = .int },
            .{ .name = "mode", .type_annotation = .int, .default_value = "0o777", .keyword_only = true },
        },
    };
    try std.testing.expectEqual(@as(usize, 2), func.positionalCount());
    try std.testing.expectEqual(@as(usize, 1), func.keywordCount());
}

test "clinic_function_full_name" {
    const func = ClinicFunction{
        .module = "io",
        .class = "BufferedReader",
        .name = "read",
        .parameters = &[_]ClinicParameter{},
    };
    const name = try func.fullName(std.testing.allocator);
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("io.BufferedReader.read", name);
}

test "converter_registry" {
    var registry = ConverterRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const int_conv = registry.get("int");
    try std.testing.expect(int_conv != null);
    try std.testing.expectEqual(@as(u8, 'i'), int_conv.?.format_unit);
    try std.testing.expectEqualStrings("int", int_conv.?.c_type);
}

test "clinic_parser_directives" {
    var parser = ClinicParser.init(std.testing.allocator);
    defer parser.deinit();

    const module_dir = try parser.parseDirective("module os");
    try std.testing.expect(module_dir != null);
    try std.testing.expectEqualStrings("os", module_dir.?.module);

    const class_dir = try parser.parseDirective("class stat_result");
    try std.testing.expect(class_dir != null);
    try std.testing.expectEqualStrings("stat_result", class_dir.?.class);
}

test "clinic_parser_parameter" {
    var parser = ClinicParser.init(std.testing.allocator);
    defer parser.deinit();

    const param = try parser.parseParameter("    value: int");
    try std.testing.expectEqualStrings("value", param.name);
    try std.testing.expectEqual(ClinicParameter.TypeAnnotation.int, param.type_annotation);
}

test "signature_format" {
    const sig = Signature{
        .name = "open",
        .parameters = &[_]Signature.SignatureParameter{
            .{ .name = "file", .kind = .positional_or_keyword },
            .{ .name = "mode", .kind = .positional_or_keyword, .default = "'r'" },
        },
        .return_annotation = "IO",
    };
    const formatted = try sig.formatTextSignature(std.testing.allocator);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("open(file, mode='r') -> IO", formatted);
}

test "docstring_formatter" {
    const formatter = DocstringFormatter.init(std.testing.allocator);
    const summary = formatter.extractSummary("Short summary.\n\nLong description here.");
    try std.testing.expectEqualStrings("Short summary.", summary);
}

test "docstring_format_for_c" {
    const formatter = DocstringFormatter.init(std.testing.allocator);
    const result = try formatter.formatForC("Hello\nWorld");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "PyDoc_STRVAR") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\n") != null);
}

test "clinic_code_generator" {
    var registry = ConverterRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var gen = ClinicCodeGenerator.init(std.testing.allocator, &registry);
    defer gen.deinit();

    const func = ClinicFunction{
        .module = "test",
        .name = "add",
        .parameters = &[_]ClinicParameter{
            .{ .name = "a", .type_annotation = .int },
            .{ .name = "b", .type_annotation = .int },
        },
    };

    const code = try gen.generateParseArgs(func);
    defer std.testing.allocator.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "add_impl") != null);
}
