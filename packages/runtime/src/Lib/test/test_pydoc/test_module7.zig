//! test.test_pydoc.test_classes - Tests for class documentation
//! Tests extracting and rendering documentation from Python classes.

const std = @import("std");
const testing = std.testing;

/// Method descriptor types
pub const MethodType = enum {
    instance,
    class_method,
    static_method,
    property_getter,
    property_setter,
    property_deleter,

    pub fn displayName(self: MethodType) []const u8 {
        return switch (self) {
            .instance => "Method",
            .class_method => "Class method",
            .static_method => "Static method",
            .property_getter => "Property (getter)",
            .property_setter => "Property (setter)",
            .property_deleter => "Property (deleter)",
        };
    }

    pub fn isProperty(self: MethodType) bool {
        return self == .property_getter or self == .property_setter or self == .property_deleter;
    }
};

/// Parameter information
pub const ParameterInfo = struct {
    name: []const u8,
    type_hint: ?[]const u8 = null,
    default_value: ?[]const u8 = null,
    kind: ParameterKind = .positional_or_keyword,

    pub const ParameterKind = enum {
        positional_only,
        positional_or_keyword,
        var_positional,
        keyword_only,
        var_keyword,
    };

    pub fn init(name: []const u8) ParameterInfo {
        return .{ .name = name };
    }

    pub fn withType(self: ParameterInfo, type_hint: []const u8) ParameterInfo {
        var result = self;
        result.type_hint = type_hint;
        return result;
    }

    pub fn withDefault(self: ParameterInfo, default: []const u8) ParameterInfo {
        var result = self;
        result.default_value = default;
        return result;
    }

    pub fn isRequired(self: ParameterInfo) bool {
        return self.default_value == null and
            self.kind != .var_positional and
            self.kind != .var_keyword;
    }
};

/// Method documentation
pub const MethodDoc = struct {
    name: []const u8,
    method_type: MethodType,
    params: []const ParameterInfo,
    return_type: ?[]const u8,
    docstring: ?[]const u8,
    decorators: []const []const u8,
    is_async: bool = false,
    is_generator: bool = false,

    pub fn init(name: []const u8, method_type: MethodType) MethodDoc {
        return .{
            .name = name,
            .method_type = method_type,
            .params = &.{},
            .return_type = null,
            .docstring = null,
            .decorators = &.{},
        };
    }

    pub fn signature(self: MethodDoc) []const u8 {
        _ = self;
        // Would build signature string
        return "()";
    }

    pub fn shortDoc(self: MethodDoc) ?[]const u8 {
        if (self.docstring) |doc| {
            var lines = std.mem.splitScalar(u8, doc, '\n');
            return lines.first();
        }
        return null;
    }

    pub fn isDunder(self: MethodDoc) bool {
        return self.name.len >= 4 and
            std.mem.startsWith(u8, self.name, "__") and
            std.mem.endsWith(u8, self.name, "__");
    }

    pub fn isPrivate(self: MethodDoc) bool {
        return self.name.len >= 1 and self.name[0] == '_' and !self.isDunder();
    }
};

/// Attribute documentation
pub const AttributeDoc = struct {
    name: []const u8,
    type_hint: ?[]const u8,
    docstring: ?[]const u8,
    default_value: ?[]const u8,
    is_class_var: bool = false,

    pub fn init(name: []const u8) AttributeDoc {
        return .{
            .name = name,
            .type_hint = null,
            .docstring = null,
            .default_value = null,
        };
    }

    pub fn withType(self: AttributeDoc, type_hint: []const u8) AttributeDoc {
        var result = self;
        result.type_hint = type_hint;
        return result;
    }

    pub fn asClassVar(self: AttributeDoc) AttributeDoc {
        var result = self;
        result.is_class_var = true;
        return result;
    }
};

/// Complete class documentation
pub const ClassDoc = struct {
    name: []const u8,
    module: ?[]const u8,
    bases: []const []const u8,
    mro: []const []const u8,
    docstring: ?[]const u8,
    methods: std.ArrayList(MethodDoc),
    attributes: std.ArrayList(AttributeDoc),
    nested_classes: []const []const u8,
    is_abstract: bool = false,
    is_dataclass: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) ClassDoc {
        return .{
            .name = name,
            .module = null,
            .bases = &.{},
            .mro = &.{},
            .docstring = null,
            .methods = std.ArrayList(MethodDoc).init(allocator),
            .attributes = std.ArrayList(AttributeDoc).init(allocator),
            .nested_classes = &.{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ClassDoc) void {
        self.methods.deinit();
        self.attributes.deinit();
    }

    pub fn addMethod(self: *ClassDoc, method: MethodDoc) !void {
        try self.methods.append(method);
    }

    pub fn addAttribute(self: *ClassDoc, attr: AttributeDoc) !void {
        try self.attributes.append(attr);
    }

    pub fn getInit(self: ClassDoc) ?MethodDoc {
        for (self.methods.items) |m| {
            if (std.mem.eql(u8, m.name, "__init__")) return m;
        }
        return null;
    }

    pub fn getPublicMethods(self: ClassDoc) !std.ArrayList(MethodDoc) {
        var result = std.ArrayList(MethodDoc).init(self.allocator);
        for (self.methods.items) |m| {
            if (!m.isPrivate() and !m.isDunder()) {
                try result.append(m);
            }
        }
        return result;
    }

    pub fn getDunderMethods(self: ClassDoc) !std.ArrayList(MethodDoc) {
        var result = std.ArrayList(MethodDoc).init(self.allocator);
        for (self.methods.items) |m| {
            if (m.isDunder()) {
                try result.append(m);
            }
        }
        return result;
    }

    pub fn getProperties(self: ClassDoc) !std.ArrayList(MethodDoc) {
        var result = std.ArrayList(MethodDoc).init(self.allocator);
        for (self.methods.items) |m| {
            if (m.method_type.isProperty()) {
                try result.append(m);
            }
        }
        return result;
    }

    pub fn qualifiedName(self: ClassDoc) []const u8 {
        // Would combine module.name
        return self.name;
    }

    pub fn methodCount(self: ClassDoc) usize {
        return self.methods.items.len;
    }

    pub fn attributeCount(self: ClassDoc) usize {
        return self.attributes.items.len;
    }
};

/// Class documentation extractor
pub const ClassExtractor = struct {
    include_inherited: bool = true,
    include_private: bool = false,
    include_dunder: bool = true,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ClassExtractor {
        return .{ .allocator = allocator };
    }

    pub fn extract(self: ClassExtractor, class_name: []const u8) !ClassDoc {
        // Would introspect actual class
        return ClassDoc.init(self.allocator, class_name);
    }

    pub fn extractWithBases(self: ClassExtractor, name: []const u8, bases: []const []const u8) !ClassDoc {
        var doc = ClassDoc.init(self.allocator, name);
        doc.bases = bases;
        return doc;
    }
};

/// Class hierarchy analyzer
pub const ClassHierarchy = struct {
    classes: std.StringHashMap(ClassDoc),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ClassHierarchy {
        return .{
            .classes = std.StringHashMap(ClassDoc).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ClassHierarchy) void {
        self.classes.deinit();
    }

    pub fn add(self: *ClassHierarchy, class: ClassDoc) !void {
        try self.classes.put(class.name, class);
    }

    pub fn getSubclasses(self: ClassHierarchy, base_name: []const u8) !std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8).init(self.allocator);
        var iter = self.classes.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.bases) |b| {
                if (std.mem.eql(u8, b, base_name)) {
                    try result.append(entry.key_ptr.*);
                    break;
                }
            }
        }
        return result;
    }

    pub fn count(self: ClassHierarchy) usize {
        return self.classes.count();
    }
};

// Tests
test "method_type_display_name" {
    try testing.expectEqualStrings("Method", MethodType.instance.displayName());
    try testing.expectEqualStrings("Class method", MethodType.class_method.displayName());
    try testing.expectEqualStrings("Static method", MethodType.static_method.displayName());
}

test "method_type_is_property" {
    try testing.expect(MethodType.property_getter.isProperty());
    try testing.expect(!MethodType.instance.isProperty());
}

test "parameter_info_init" {
    const param = ParameterInfo.init("x");
    try testing.expectEqualStrings("x", param.name);
    try testing.expect(param.isRequired());
}

test "parameter_info_with_type" {
    const param = ParameterInfo.init("x").withType("int");
    try testing.expectEqualStrings("int", param.type_hint.?);
}

test "parameter_info_with_default" {
    const param = ParameterInfo.init("x").withDefault("0");
    try testing.expect(!param.isRequired());
}

test "method_doc_init" {
    const method = MethodDoc.init("my_method", .instance);
    try testing.expectEqualStrings("my_method", method.name);
    try testing.expect(!method.is_async);
}

test "method_doc_is_dunder" {
    const init_method = MethodDoc.init("__init__", .instance);
    const normal_method = MethodDoc.init("normal", .instance);
    try testing.expect(init_method.isDunder());
    try testing.expect(!normal_method.isDunder());
}

test "method_doc_is_private" {
    const private = MethodDoc.init("_helper", .instance);
    const public = MethodDoc.init("public", .instance);
    const dunder = MethodDoc.init("__str__", .instance);
    try testing.expect(private.isPrivate());
    try testing.expect(!public.isPrivate());
    try testing.expect(!dunder.isPrivate());
}

test "attribute_doc_init" {
    const attr = AttributeDoc.init("value");
    try testing.expectEqualStrings("value", attr.name);
    try testing.expect(!attr.is_class_var);
}

test "attribute_doc_with_type" {
    const attr = AttributeDoc.init("value").withType("int");
    try testing.expectEqualStrings("int", attr.type_hint.?);
}

test "attribute_doc_as_class_var" {
    const attr = AttributeDoc.init("count").asClassVar();
    try testing.expect(attr.is_class_var);
}

test "class_doc_init" {
    var doc = ClassDoc.init(testing.allocator, "MyClass");
    defer doc.deinit();
    try testing.expectEqualStrings("MyClass", doc.name);
    try testing.expectEqual(@as(usize, 0), doc.methodCount());
}

test "class_doc_add_method" {
    var doc = ClassDoc.init(testing.allocator, "MyClass");
    defer doc.deinit();
    try doc.addMethod(MethodDoc.init("foo", .instance));
    try testing.expectEqual(@as(usize, 1), doc.methodCount());
}

test "class_doc_add_attribute" {
    var doc = ClassDoc.init(testing.allocator, "MyClass");
    defer doc.deinit();
    try doc.addAttribute(AttributeDoc.init("value"));
    try testing.expectEqual(@as(usize, 1), doc.attributeCount());
}

test "class_doc_get_init" {
    var doc = ClassDoc.init(testing.allocator, "MyClass");
    defer doc.deinit();
    try doc.addMethod(MethodDoc.init("__init__", .instance));
    try doc.addMethod(MethodDoc.init("foo", .instance));
    const init = doc.getInit();
    try testing.expect(init != null);
    try testing.expectEqualStrings("__init__", init.?.name);
}

test "class_doc_get_public_methods" {
    var doc = ClassDoc.init(testing.allocator, "MyClass");
    defer doc.deinit();
    try doc.addMethod(MethodDoc.init("public", .instance));
    try doc.addMethod(MethodDoc.init("_private", .instance));
    try doc.addMethod(MethodDoc.init("__dunder__", .instance));
    var public = try doc.getPublicMethods();
    defer public.deinit();
    try testing.expectEqual(@as(usize, 1), public.items.len);
}

test "class_extractor_init" {
    const extractor = ClassExtractor.init(testing.allocator);
    try testing.expect(extractor.include_inherited);
    try testing.expect(!extractor.include_private);
}

test "class_hierarchy_init" {
    var hierarchy = ClassHierarchy.init(testing.allocator);
    defer hierarchy.deinit();
    try testing.expectEqual(@as(usize, 0), hierarchy.count());
}
