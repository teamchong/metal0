//! test.test_pydoc.test_doc - Tests for documentation extraction
//! Tests extracting docstrings and documentation from Python objects.

const std = @import("std");
const testing = std.testing;

/// Represents a docstring parsed from Python source
pub const Docstring = struct {
    raw: []const u8,
    summary: []const u8,
    body: []const u8,
    sections: []const Section,
    allocator: std.mem.Allocator,

    pub const Section = struct {
        name: []const u8,
        content: []const u8,
        items: []const SectionItem,
    };

    pub const SectionItem = struct {
        name: []const u8,
        type_hint: ?[]const u8,
        description: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, raw: []const u8) Docstring {
        return .{
            .raw = raw,
            .summary = extractSummary(raw),
            .body = extractBody(raw),
            .sections = &.{},
            .allocator = allocator,
        };
    }

    fn extractSummary(raw: []const u8) []const u8 {
        var lines = std.mem.splitScalar(u8, raw, '\n');
        if (lines.next()) |first_line| {
            return std.mem.trim(u8, first_line, " \t");
        }
        return "";
    }

    fn extractBody(raw: []const u8) []const u8 {
        var lines = std.mem.splitScalar(u8, raw, '\n');
        _ = lines.next(); // Skip summary
        const rest = lines.rest();
        return std.mem.trim(u8, rest, " \t\n");
    }

    pub fn isEmpty(self: Docstring) bool {
        return self.raw.len == 0;
    }

    pub fn hasSections(self: Docstring) bool {
        return self.sections.len > 0;
    }
};

/// Parser for different docstring formats
pub const DocstringParser = struct {
    style: DocStyle,
    allocator: std.mem.Allocator,

    pub const DocStyle = enum {
        google,
        numpy,
        sphinx,
        epytext,
        plain,
    };

    pub fn init(allocator: std.mem.Allocator, style: DocStyle) DocstringParser {
        return .{
            .allocator = allocator,
            .style = style,
        };
    }

    pub fn parse(self: DocstringParser, source: []const u8) Docstring {
        return Docstring.init(self.allocator, source);
    }

    pub fn detectStyle(source: []const u8) DocStyle {
        if (std.mem.indexOf(u8, source, ":param ") != null or
            std.mem.indexOf(u8, source, ":returns:") != null)
        {
            return .sphinx;
        }
        if (std.mem.indexOf(u8, source, "Args:") != null or
            std.mem.indexOf(u8, source, "Returns:") != null)
        {
            return .google;
        }
        if (std.mem.indexOf(u8, source, "Parameters\n----------") != null) {
            return .numpy;
        }
        if (std.mem.indexOf(u8, source, "@param") != null) {
            return .epytext;
        }
        return .plain;
    }
};

/// Represents extracted documentation for a callable
pub const CallableDoc = struct {
    name: []const u8,
    signature: ?Signature,
    docstring: ?Docstring,
    source_file: ?[]const u8,
    line_number: ?u32,

    pub const Signature = struct {
        params: []const Parameter,
        return_type: ?[]const u8,
        is_async: bool,
        is_generator: bool,

        pub const Parameter = struct {
            name: []const u8,
            type_hint: ?[]const u8,
            default: ?[]const u8,
            kind: ParameterKind,
        };

        pub const ParameterKind = enum {
            positional_only,
            positional_or_keyword,
            var_positional,
            keyword_only,
            var_keyword,
        };
    };

    pub fn init(name: []const u8) CallableDoc {
        return .{
            .name = name,
            .signature = null,
            .docstring = null,
            .source_file = null,
            .line_number = null,
        };
    }

    pub fn withSignature(self: CallableDoc, sig: Signature) CallableDoc {
        var result = self;
        result.signature = sig;
        return result;
    }

    pub fn withDocstring(self: CallableDoc, doc: Docstring) CallableDoc {
        var result = self;
        result.docstring = doc;
        return result;
    }

    pub fn getFullSignature(self: CallableDoc) []const u8 {
        _ = self;
        // Would build full signature string
        return "()";
    }
};

/// Represents extracted documentation for a class
pub const ClassDoc = struct {
    name: []const u8,
    bases: []const []const u8,
    docstring: ?Docstring,
    methods: []const CallableDoc,
    class_methods: []const CallableDoc,
    static_methods: []const CallableDoc,
    properties: []const PropertyDoc,
    class_attributes: []const AttributeDoc,
    mro: []const []const u8,

    pub fn init(name: []const u8) ClassDoc {
        return .{
            .name = name,
            .bases = &.{},
            .docstring = null,
            .methods = &.{},
            .class_methods = &.{},
            .static_methods = &.{},
            .properties = &.{},
            .class_attributes = &.{},
            .mro = &.{},
        };
    }

    pub fn hasDocstring(self: ClassDoc) bool {
        return self.docstring != null and !self.docstring.?.isEmpty();
    }

    pub fn getAllMethods(self: ClassDoc) []const CallableDoc {
        _ = self;
        // Would concatenate all method types
        return &.{};
    }
};

/// Represents a property's documentation
pub const PropertyDoc = struct {
    name: []const u8,
    type_hint: ?[]const u8,
    docstring: ?Docstring,
    has_getter: bool,
    has_setter: bool,
    has_deleter: bool,
};

/// Represents an attribute's documentation
pub const AttributeDoc = struct {
    name: []const u8,
    type_hint: ?[]const u8,
    value_repr: ?[]const u8,
    docstring: ?Docstring,
};

/// Represents extracted documentation for a module
pub const ModuleDoc = struct {
    name: []const u8,
    path: ?[]const u8,
    docstring: ?Docstring,
    functions: []const CallableDoc,
    classes: []const ClassDoc,
    submodules: []const []const u8,
    all_exports: ?[]const []const u8,

    pub fn init(name: []const u8) ModuleDoc {
        return .{
            .name = name,
            .path = null,
            .docstring = null,
            .functions = &.{},
            .classes = &.{},
            .submodules = &.{},
            .all_exports = null,
        };
    }

    pub fn hasDocstring(self: ModuleDoc) bool {
        return self.docstring != null and !self.docstring.?.isEmpty();
    }
};

// Tests
test "docstring_init" {
    const doc = Docstring.init(testing.allocator, "A simple docstring.");
    try testing.expectEqualStrings("A simple docstring.", doc.raw);
    try testing.expect(!doc.isEmpty());
}

test "docstring_summary_extraction" {
    const raw = "Summary line.\n\nBody paragraph here.";
    const doc = Docstring.init(testing.allocator, raw);
    try testing.expectEqualStrings("Summary line.", doc.summary);
}

test "docstring_body_extraction" {
    const raw = "Summary line.\n\nBody paragraph here.";
    const doc = Docstring.init(testing.allocator, raw);
    try testing.expectEqualStrings("Body paragraph here.", doc.body);
}

test "docstring_empty_check" {
    const empty = Docstring.init(testing.allocator, "");
    try testing.expect(empty.isEmpty());
}

test "docstring_parser_detect_google" {
    const source = "Function description.\n\nArgs:\n    x: Input value\n";
    const style = DocstringParser.detectStyle(source);
    try testing.expectEqual(DocstringParser.DocStyle.google, style);
}

test "docstring_parser_detect_sphinx" {
    const source = "Function description.\n\n:param x: Input value\n:returns: Output\n";
    const style = DocstringParser.detectStyle(source);
    try testing.expectEqual(DocstringParser.DocStyle.sphinx, style);
}

test "docstring_parser_detect_plain" {
    const source = "Just a plain docstring with no special formatting.";
    const style = DocstringParser.detectStyle(source);
    try testing.expectEqual(DocstringParser.DocStyle.plain, style);
}

test "callable_doc_init" {
    const doc = CallableDoc.init("my_function");
    try testing.expectEqualStrings("my_function", doc.name);
    try testing.expectEqual(@as(?CallableDoc.Signature, null), doc.signature);
}

test "class_doc_init" {
    const doc = ClassDoc.init("MyClass");
    try testing.expectEqualStrings("MyClass", doc.name);
    try testing.expect(!doc.hasDocstring());
}

test "module_doc_init" {
    const doc = ModuleDoc.init("my_module");
    try testing.expectEqualStrings("my_module", doc.name);
    try testing.expect(!doc.hasDocstring());
}

test "property_doc_struct" {
    const prop = PropertyDoc{
        .name = "value",
        .type_hint = "int",
        .docstring = null,
        .has_getter = true,
        .has_setter = true,
        .has_deleter = false,
    };
    try testing.expectEqualStrings("value", prop.name);
    try testing.expect(prop.has_getter);
    try testing.expect(prop.has_setter);
    try testing.expect(!prop.has_deleter);
}

test "attribute_doc_struct" {
    const attr = AttributeDoc{
        .name = "MAX_SIZE",
        .type_hint = "int",
        .value_repr = "100",
        .docstring = null,
    };
    try testing.expectEqualStrings("MAX_SIZE", attr.name);
    try testing.expectEqualStrings("100", attr.value_repr.?);
}
