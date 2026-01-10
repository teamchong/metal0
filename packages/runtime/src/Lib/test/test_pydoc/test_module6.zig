//! test.test_pydoc.test_modules - Tests for module documentation
//! Tests extracting and rendering documentation from Python modules.

const std = @import("std");
const testing = std.testing;

/// Module metadata
pub const ModuleMeta = struct {
    name: []const u8,
    version: ?[]const u8 = null,
    author: ?[]const u8 = null,
    email: ?[]const u8 = null,
    url: ?[]const u8 = null,
    license: ?[]const u8 = null,
    path: ?[]const u8 = null,
    package: ?[]const u8 = null,

    pub fn init(name: []const u8) ModuleMeta {
        return .{ .name = name };
    }

    pub fn withVersion(self: ModuleMeta, version: []const u8) ModuleMeta {
        var result = self;
        result.version = version;
        return result;
    }

    pub fn withAuthor(self: ModuleMeta, author: []const u8) ModuleMeta {
        var result = self;
        result.author = author;
        return result;
    }

    pub fn isBuiltin(self: ModuleMeta) bool {
        return self.path == null;
    }

    pub fn qualifiedName(self: ModuleMeta) []const u8 {
        if (self.package) |pkg| {
            _ = pkg;
            // Would join package.name
            return self.name;
        }
        return self.name;
    }
};

/// Module member types
pub const MemberType = enum {
    function,
    class_type,
    constant,
    variable,
    submodule,
    exception,
    type_alias,

    pub fn displayName(self: MemberType) []const u8 {
        return switch (self) {
            .function => "FUNCTIONS",
            .class_type => "CLASSES",
            .constant => "CONSTANTS",
            .variable => "VARIABLES",
            .submodule => "SUBMODULES",
            .exception => "EXCEPTIONS",
            .type_alias => "TYPE ALIASES",
        };
    }
};

/// A module member entry
pub const ModuleMember = struct {
    name: []const u8,
    member_type: MemberType,
    docstring: ?[]const u8,
    signature: ?[]const u8,
    value_repr: ?[]const u8,
    is_public: bool = true,
    is_dunder: bool = false,
    is_private: bool = false,

    pub fn init(name: []const u8, member_type: MemberType) ModuleMember {
        var member = ModuleMember{
            .name = name,
            .member_type = member_type,
            .docstring = null,
            .signature = null,
            .value_repr = null,
        };
        // Detect visibility from name
        if (name.len >= 2 and std.mem.startsWith(u8, name, "__") and std.mem.endsWith(u8, name, "__")) {
            member.is_dunder = true;
        } else if (name.len >= 1 and name[0] == '_') {
            member.is_private = true;
            member.is_public = false;
        }
        return member;
    }

    pub fn withDoc(self: ModuleMember, doc: []const u8) ModuleMember {
        var result = self;
        result.docstring = doc;
        return result;
    }

    pub fn withSignature(self: ModuleMember, sig: []const u8) ModuleMember {
        var result = self;
        result.signature = sig;
        return result;
    }

    pub fn shortDoc(self: ModuleMember) ?[]const u8 {
        if (self.docstring) |doc| {
            var lines = std.mem.splitScalar(u8, doc, '\n');
            return lines.first();
        }
        return null;
    }
};

/// Complete module documentation
pub const ModuleDoc = struct {
    meta: ModuleMeta,
    docstring: ?[]const u8,
    members: std.ArrayList(ModuleMember),
    all_list: ?[]const []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) ModuleDoc {
        return .{
            .meta = ModuleMeta.init(name),
            .docstring = null,
            .members = std.ArrayList(ModuleMember).init(allocator),
            .all_list = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ModuleDoc) void {
        self.members.deinit();
    }

    pub fn addMember(self: *ModuleDoc, member: ModuleMember) !void {
        try self.members.append(member);
    }

    pub fn getMembersByType(self: ModuleDoc, member_type: MemberType) []const ModuleMember {
        _ = self;
        _ = member_type;
        // Would filter members
        return &.{};
    }

    pub fn getPublicMembers(self: ModuleDoc) []const ModuleMember {
        _ = self;
        // Would filter public only
        return &.{};
    }

    pub fn getFunctions(self: ModuleDoc) !std.ArrayList(ModuleMember) {
        var funcs = std.ArrayList(ModuleMember).init(self.allocator);
        for (self.members.items) |m| {
            if (m.member_type == .function) {
                try funcs.append(m);
            }
        }
        return funcs;
    }

    pub fn getClasses(self: ModuleDoc) !std.ArrayList(ModuleMember) {
        var classes = std.ArrayList(ModuleMember).init(self.allocator);
        for (self.members.items) |m| {
            if (m.member_type == .class_type) {
                try classes.append(m);
            }
        }
        return classes;
    }

    pub fn memberCount(self: ModuleDoc) usize {
        return self.members.items.len;
    }
};

/// Module documentation extractor
pub const ModuleExtractor = struct {
    include_private: bool = false,
    include_dunder: bool = false,
    follow_imports: bool = true,
    max_depth: u32 = 3,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ModuleExtractor {
        return .{ .allocator = allocator };
    }

    pub fn extract(self: ModuleExtractor, module_name: []const u8) !ModuleDoc {
        // Would actually introspect a module
        _ = self;
        return ModuleDoc.init(self.allocator, module_name);
    }

    pub fn extractBuiltin(self: ModuleExtractor, name: []const u8) !ModuleDoc {
        var doc = ModuleDoc.init(self.allocator, name);
        doc.docstring = "Built-in module.";
        return doc;
    }

    pub fn shouldInclude(self: ModuleExtractor, member: ModuleMember) bool {
        if (member.is_dunder and !self.include_dunder) return false;
        if (member.is_private and !self.include_private) return false;
        return true;
    }
};

/// Module index for searching
pub const ModuleIndex = struct {
    modules: std.StringHashMap(ModuleMeta),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ModuleIndex {
        return .{
            .modules = std.StringHashMap(ModuleMeta).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ModuleIndex) void {
        self.modules.deinit();
    }

    pub fn add(self: *ModuleIndex, meta: ModuleMeta) !void {
        try self.modules.put(meta.name, meta);
    }

    pub fn get(self: ModuleIndex, name: []const u8) ?ModuleMeta {
        return self.modules.get(name);
    }

    pub fn contains(self: ModuleIndex, name: []const u8) bool {
        return self.modules.contains(name);
    }

    pub fn count(self: ModuleIndex) usize {
        return self.modules.count();
    }

    pub fn search(self: ModuleIndex, pattern: []const u8) !std.ArrayList(ModuleMeta) {
        var results = std.ArrayList(ModuleMeta).init(self.allocator);
        var iter = self.modules.iterator();
        while (iter.next()) |entry| {
            if (std.mem.indexOf(u8, entry.key_ptr.*, pattern) != null) {
                try results.append(entry.value_ptr.*);
            }
        }
        return results;
    }
};

// Tests
test "module_meta_init" {
    const meta = ModuleMeta.init("os");
    try testing.expectEqualStrings("os", meta.name);
    try testing.expect(meta.isBuiltin());
}

test "module_meta_with_version" {
    const meta = ModuleMeta.init("mymodule").withVersion("1.0.0");
    try testing.expectEqualStrings("1.0.0", meta.version.?);
}

test "module_meta_with_author" {
    const meta = ModuleMeta.init("mymodule").withAuthor("John Doe");
    try testing.expectEqualStrings("John Doe", meta.author.?);
}

test "member_type_display_name" {
    try testing.expectEqualStrings("FUNCTIONS", MemberType.function.displayName());
    try testing.expectEqualStrings("CLASSES", MemberType.class_type.displayName());
}

test "module_member_init" {
    const member = ModuleMember.init("my_func", .function);
    try testing.expectEqualStrings("my_func", member.name);
    try testing.expect(member.is_public);
    try testing.expect(!member.is_private);
}

test "module_member_private_detection" {
    const member = ModuleMember.init("_private", .function);
    try testing.expect(member.is_private);
    try testing.expect(!member.is_public);
}

test "module_member_dunder_detection" {
    const member = ModuleMember.init("__init__", .function);
    try testing.expect(member.is_dunder);
}

test "module_member_with_doc" {
    const member = ModuleMember.init("func", .function)
        .withDoc("Does something useful.");
    try testing.expectEqualStrings("Does something useful.", member.docstring.?);
}

test "module_member_with_signature" {
    const member = ModuleMember.init("func", .function)
        .withSignature("(x, y)");
    try testing.expectEqualStrings("(x, y)", member.signature.?);
}

test "module_member_short_doc" {
    const member = ModuleMember.init("func", .function)
        .withDoc("First line.\n\nMore details.");
    try testing.expectEqualStrings("First line.", member.shortDoc().?);
}

test "module_doc_init" {
    var doc = ModuleDoc.init(testing.allocator, "mymodule");
    defer doc.deinit();
    try testing.expectEqualStrings("mymodule", doc.meta.name);
}

test "module_doc_add_member" {
    var doc = ModuleDoc.init(testing.allocator, "mymodule");
    defer doc.deinit();
    try doc.addMember(ModuleMember.init("func1", .function));
    try testing.expectEqual(@as(usize, 1), doc.memberCount());
}

test "module_doc_get_functions" {
    var doc = ModuleDoc.init(testing.allocator, "mymodule");
    defer doc.deinit();
    try doc.addMember(ModuleMember.init("func1", .function));
    try doc.addMember(ModuleMember.init("MyClass", .class_type));
    var funcs = try doc.getFunctions();
    defer funcs.deinit();
    try testing.expectEqual(@as(usize, 1), funcs.items.len);
}

test "module_extractor_init" {
    const extractor = ModuleExtractor.init(testing.allocator);
    try testing.expect(!extractor.include_private);
    try testing.expect(extractor.follow_imports);
}

test "module_extractor_should_include" {
    const extractor = ModuleExtractor.init(testing.allocator);
    const pub_member = ModuleMember.init("public", .function);
    const priv_member = ModuleMember.init("_private", .function);
    try testing.expect(extractor.shouldInclude(pub_member));
    try testing.expect(!extractor.shouldInclude(priv_member));
}

test "module_index_init" {
    var index = ModuleIndex.init(testing.allocator);
    defer index.deinit();
    try testing.expectEqual(@as(usize, 0), index.count());
}

test "module_index_add_get" {
    var index = ModuleIndex.init(testing.allocator);
    defer index.deinit();
    try index.add(ModuleMeta.init("os"));
    try testing.expect(index.contains("os"));
    try testing.expectEqual(@as(usize, 1), index.count());
}
