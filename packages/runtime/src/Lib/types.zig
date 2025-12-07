//! CPython source: Lib/types.py
//!
//! Defines names for some object types that are used by the standard Python
//! interpreter, but not exposed as builtins.
//!
//! Mirrors: CPython Lib/types.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Function Types
// ============================================================================

/// Type for user-defined functions created by def statements
pub const FunctionType = struct {
    name: []const u8,
    module: ?[]const u8 = null,
    doc: ?[]const u8 = null,
    annotations: ?hashmap_helper.StringHashMap([]const u8) = null,
    defaults: ?[]const u8 = null,
    closure: ?*anyopaque = null,

    pub fn init(name: []const u8) FunctionType {
        return .{ .name = name };
    }
};

/// Type for lambda functions
pub const LambdaType = FunctionType;

/// Type for built-in functions
pub const BuiltinFunctionType = struct {
    name: []const u8,
    doc: ?[]const u8 = null,
};

/// Type for built-in methods
pub const BuiltinMethodType = BuiltinFunctionType;

/// Type for methods of user-defined class instances
pub const MethodType = struct {
    func: *const FunctionType,
    self: *anyopaque,
};

/// Type for unbound methods (Python 2 compatibility)
pub const UnboundMethodType = MethodType;

// ============================================================================
// Code and Frame Types
// ============================================================================

/// Type for code objects
pub const CodeType = struct {
    name: []const u8,
    filename: []const u8 = "<unknown>",
    firstlineno: u32 = 1,
    argcount: u32 = 0,
    kwonlyargcount: u32 = 0,
    nlocals: u32 = 0,
    stacksize: u32 = 0,
    flags: u32 = 0,
    varnames: []const []const u8 = &[_][]const u8{},
    freevars: []const []const u8 = &[_][]const u8{},
    cellvars: []const []const u8 = &[_][]const u8{},
};

/// Type for frame objects
pub const FrameType = struct {
    code: *const CodeType,
    lineno: u32 = 1,
    globals: ?*anyopaque = null,
    locals: ?*anyopaque = null,
    back: ?*FrameType = null,
};

/// Type for traceback objects
pub const TracebackType = struct {
    frame: *FrameType,
    lineno: u32,
    next: ?*TracebackType = null,
};

// ============================================================================
// Generator and Coroutine Types
// ============================================================================

/// Type for generator objects
pub const GeneratorType = struct {
    name: []const u8,
    qualname: []const u8 = "",
    frame: ?*FrameType = null,
    running: bool = false,
};

/// Type for coroutine objects
pub const CoroutineType = struct {
    name: []const u8,
    qualname: []const u8 = "",
    frame: ?*FrameType = null,
    running: bool = false,
};

/// Type for async generator objects
pub const AsyncGeneratorType = struct {
    name: []const u8,
    qualname: []const u8 = "",
    frame: ?*FrameType = null,
    running: bool = false,
};

// ============================================================================
// Module Type
// ============================================================================

/// Type for module objects
pub const ModuleType = struct {
    name: []const u8,
    doc: ?[]const u8 = null,
    package: ?[]const u8 = null,
    loader: ?*anyopaque = null,
    spec: ?*anyopaque = null,
    file: ?[]const u8 = null,
    cached: ?[]const u8 = null,
    dict: ?*anyopaque = null,

    pub fn init(name: []const u8) ModuleType {
        return .{ .name = name };
    }

    pub fn withDoc(self: ModuleType, doc: []const u8) ModuleType {
        var copy = self;
        copy.doc = doc;
        return copy;
    }
};

// ============================================================================
// Descriptor Types
// ============================================================================

/// Type for class method descriptors
pub const ClassMethodDescriptorType = struct {
    func: *anyopaque,
    name: []const u8,
    type_obj: *anyopaque,
};

/// Type for method descriptors
pub const MethodDescriptorType = struct {
    func: *anyopaque,
    name: []const u8,
    type_obj: *anyopaque,
};

/// Type for member descriptors
pub const MemberDescriptorType = struct {
    name: []const u8,
    type_obj: *anyopaque,
    offset: usize = 0,
};

/// Type for getset descriptors
pub const GetSetDescriptorType = struct {
    name: []const u8,
    type_obj: *anyopaque,
    getter: ?*const fn (*anyopaque) *anyopaque = null,
    setter: ?*const fn (*anyopaque, *anyopaque) void = null,
};

/// Type for wrapper descriptors
pub const WrapperDescriptorType = MethodDescriptorType;

// ============================================================================
// Class and Object Types
// ============================================================================

/// Type for new-style classes
pub const TypeType = struct {
    name: []const u8,
    bases: []const *TypeType = &[_]*TypeType{},
    dict: ?*anyopaque = null,
    module: ?[]const u8 = null,
    doc: ?[]const u8 = null,
};

/// Alias for object (no actual object type in Zig)
pub const ObjectType = struct {
    type_obj: *const TypeType,
};

// ============================================================================
// Mapping and Proxy Types
// ============================================================================

/// Type for read-only proxy of a mapping
pub fn MappingProxyType(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        mapping: *const std.AutoHashMap(K, V),

        pub fn init(mapping: *const std.AutoHashMap(K, V)) Self {
            return .{ .mapping = mapping };
        }

        pub fn get(self: Self, key: K) ?V {
            return self.mapping.get(key);
        }

        pub fn contains(self: Self, key: K) bool {
            return self.mapping.contains(key);
        }

        pub fn count(self: Self) usize {
            return self.mapping.count();
        }
    };
}

// ============================================================================
// Simple Namespace
// ============================================================================

/// A simple attribute-based namespace
pub const SimpleNamespace = struct {
    const Self = @This();
    const StringMap = hashmap_helper.StringHashMap([]const u8);

    allocator: std.mem.Allocator,
    attrs: StringMap,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .attrs = StringMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.attrs.deinit();
    }

    pub fn set(self: *Self, name: []const u8, value: []const u8) !void {
        try self.attrs.put(name, value);
    }

    pub fn get(self: Self, name: []const u8) ?[]const u8 {
        return self.attrs.get(name);
    }

    pub fn delete(self: *Self, name: []const u8) bool {
        return self.attrs.remove(name);
    }

    pub fn repr(self: Self, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        try result.appendSlice("namespace(");
        var first = true;
        var iter = self.attrs.iterator();
        while (iter.next()) |entry| {
            if (!first) {
                try result.appendSlice(", ");
            }
            first = false;
            try result.appendSlice(entry.key_ptr.*);
            try result.appendSlice("='");
            try result.appendSlice(entry.value_ptr.*);
            try result.append('\'');
        }
        try result.append(')');

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Dynamic Class Creation
// ============================================================================

/// Create a new class at runtime
pub fn new_class(
    name: []const u8,
    bases: []const *TypeType,
    dict: ?*anyopaque,
) TypeType {
    return .{
        .name = name,
        .bases = bases,
        .dict = dict,
    };
}

/// Prepare class namespace (called before class body execution)
pub fn prepare_class(
    name: []const u8,
    bases: []const *TypeType,
) struct { name: []const u8, bases: []const *TypeType } {
    _ = bases;
    _ = name;
    return .{
        .name = name,
        .bases = bases,
    };
}

// ============================================================================
// Cell and Closure Types
// ============================================================================

/// Type for cell objects (used in closures)
pub fn CellType(comptime T: type) type {
    return struct {
        const Self = @This();
        cell_contents: ?T = null,

        pub fn init(value: T) Self {
            return .{ .cell_contents = value };
        }

        pub fn empty() Self {
            return .{ .cell_contents = null };
        }

        pub fn get(self: Self) ?T {
            return self.cell_contents;
        }

        pub fn set(self: *Self, value: T) void {
            self.cell_contents = value;
        }
    };
}

// ============================================================================
// Not Implemented and Ellipsis
// ============================================================================

/// The NotImplemented singleton
pub const NotImplementedType = struct {
    pub fn repr() []const u8 {
        return "NotImplemented";
    }
};

pub const NotImplemented = NotImplementedType{};

/// The Ellipsis singleton (...)
pub const EllipsisType = struct {
    pub fn repr() []const u8 {
        return "Ellipsis";
    }
};

pub const Ellipsis = EllipsisType{};

// ============================================================================
// NoneType
// ============================================================================

/// The None singleton type
pub const NoneType = struct {
    pub fn repr() []const u8 {
        return "None";
    }
};

pub const None = NoneType{};

// ============================================================================
// Resolve Forward Reference
// ============================================================================

/// Resolve a forward reference string to a type
pub fn resolve_bases(bases: []const anytype) []const *TypeType {
    _ = bases;
    return &[_]*TypeType{};
}

// ============================================================================
// Coroutine Wrapper
// ============================================================================

/// Wraps a generator to make it behave like a coroutine
pub fn coroutine(gen: anytype) CoroutineType {
    _ = gen;
    return .{ .name = "coroutine" };
}

// ============================================================================
// Tests
// ============================================================================

test "FunctionType" {
    const f = FunctionType.init("my_function");
    try std.testing.expectEqualStrings("my_function", f.name);
}

test "ModuleType" {
    const m = ModuleType.init("my_module").withDoc("A test module");
    try std.testing.expectEqualStrings("my_module", m.name);
    try std.testing.expectEqualStrings("A test module", m.doc.?);
}

test "SimpleNamespace" {
    const allocator = std.testing.allocator;

    var ns = SimpleNamespace.init(allocator);
    defer ns.deinit();

    try ns.set("x", "10");
    try ns.set("y", "20");

    try std.testing.expectEqualStrings("10", ns.get("x").?);
    try std.testing.expectEqualStrings("20", ns.get("y").?);
    try std.testing.expect(ns.get("z") == null);

    const r = try ns.repr(allocator);
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "namespace(") != null);
}

test "CellType" {
    const Cell = CellType(i32);
    var cell = Cell.init(42);
    try std.testing.expectEqual(@as(?i32, 42), cell.get());

    cell.set(100);
    try std.testing.expectEqual(@as(?i32, 100), cell.get());

    const empty_cell = Cell.empty();
    try std.testing.expect(empty_cell.get() == null);
}

test "NotImplemented" {
    try std.testing.expectEqualStrings("NotImplemented", NotImplemented.repr());
}

test "Ellipsis" {
    try std.testing.expectEqualStrings("Ellipsis", Ellipsis.repr());
}

test "NoneType" {
    try std.testing.expectEqualStrings("None", None.repr());
}

test "CodeType" {
    const code = CodeType{
        .name = "my_func",
        .filename = "test.py",
        .firstlineno = 10,
        .argcount = 2,
    };
    try std.testing.expectEqualStrings("my_func", code.name);
    try std.testing.expectEqual(@as(u32, 2), code.argcount);
}

test "GeneratorType" {
    const gen = GeneratorType{
        .name = "my_gen",
        .qualname = "module.my_gen",
    };
    try std.testing.expectEqualStrings("my_gen", gen.name);
    try std.testing.expect(!gen.running);
}
