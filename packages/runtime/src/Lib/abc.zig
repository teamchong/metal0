//! Python 'abc' module - Abstract Base Classes
//!
//! Provides infrastructure for defining Abstract Base Classes (ABCs).
//! ABCs define interfaces that subclasses must implement.
//!
//! Mirrors: CPython Lib/abc.py

const std = @import("std");

// ============================================================================
// Abstract Base Class Infrastructure
// ============================================================================

/// Marks a class as abstract - cannot be instantiated directly
pub fn abstractclass(comptime T: type) type {
    return struct {
        pub const __abstract__ = true;
        pub const Inner = T;

        pub fn checkAbstract() bool {
            return true;
        }
    };
}

/// Marks a method as abstract - must be implemented by subclasses
pub fn abstractmethod(comptime func: anytype) @TypeOf(func) {
    // At compile time, we just return the function
    // Runtime checks would verify implementation exists
    return func;
}

/// Abstract static method decorator
pub fn abstractstaticmethod(comptime func: anytype) @TypeOf(func) {
    return func;
}

/// Abstract class method decorator
pub fn abstractclassmethod(comptime func: anytype) @TypeOf(func) {
    return func;
}

/// Abstract property (getter)
pub fn abstractproperty(comptime func: anytype) @TypeOf(func) {
    return func;
}

// ============================================================================
// ABC Registry
// ============================================================================

/// Registry for tracking abstract base classes and their virtual subclasses
pub const ABCMeta = struct {
    allocator: std.mem.Allocator,
    /// Maps ABC type names to their registered virtual subclasses
    registry: std.StringHashMap(std.ArrayList([]const u8)),
    /// Tracks negative cache (types that are not instances)
    negative_cache: std.StringHashMap(std.ArrayList([]const u8)),

    pub fn init(allocator: std.mem.Allocator) ABCMeta {
        return .{
            .allocator = allocator,
            .registry = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .negative_cache = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
        };
    }

    pub fn deinit(self: *ABCMeta) void {
        var reg_iter = self.registry.iterator();
        while (reg_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.registry.deinit();

        var neg_iter = self.negative_cache.iterator();
        while (neg_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.negative_cache.deinit();
    }

    /// Register a virtual subclass for an ABC
    pub fn register(self: *ABCMeta, abc_name: []const u8, subclass_name: []const u8) !void {
        const result = try self.registry.getOrPut(abc_name);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }
        try result.value_ptr.append(subclass_name);

        // Invalidate negative cache for this ABC
        if (self.negative_cache.get(abc_name)) |*cache| {
            cache.clearAndFree();
        }
    }

    /// Check if a class is a registered virtual subclass
    pub fn isRegistered(self: *ABCMeta, abc_name: []const u8, class_name: []const u8) bool {
        if (self.registry.get(abc_name)) |subclasses| {
            for (subclasses.items) |name| {
                if (std.mem.eql(u8, name, class_name)) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Get all registered subclasses for an ABC
    pub fn getSubclasses(self: *ABCMeta, abc_name: []const u8) ?[]const []const u8 {
        if (self.registry.get(abc_name)) |subclasses| {
            return subclasses.items;
        }
        return null;
    }
};

// ============================================================================
// ABC Type Checking
// ============================================================================

/// Check if a type implements all abstract methods
pub fn isConcreteImplementation(comptime ABC: type, comptime Impl: type) bool {
    // Check if ABC has abstract methods defined
    if (@hasDecl(ABC, "__abstractmethods__")) {
        const abstract_methods = ABC.__abstractmethods__;
        inline for (abstract_methods) |method_name| {
            if (!@hasDecl(Impl, method_name)) {
                return false;
            }
        }
    }
    return true;
}

/// Get abstract method names from a type
pub fn getAbstractMethods(comptime T: type) []const []const u8 {
    if (@hasDecl(T, "__abstractmethods__")) {
        return T.__abstractmethods__;
    }
    return &[_][]const u8{};
}

// ============================================================================
// Common ABCs (simplified versions)
// ============================================================================

/// ABC for classes that provide __hash__
pub const Hashable = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__hash__"};

    pub fn isHashable(comptime T: type) bool {
        return @hasDecl(T, "__hash__") or @typeInfo(T) == .int or @typeInfo(T) == .float;
    }
};

/// ABC for classes that provide __iter__
pub const Iterable = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__iter__"};

    pub fn isIterable(comptime T: type) bool {
        return @hasDecl(T, "__iter__") or @typeInfo(T) == .array or @typeInfo(T) == .pointer;
    }
};

/// ABC for classes that provide __iter__ and __next__
pub const Iterator = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__iter__", "__next__" };

    pub fn isIterator(comptime T: type) bool {
        return @hasDecl(T, "next") or (@hasDecl(T, "__iter__") and @hasDecl(T, "__next__"));
    }
};

/// ABC for classes that provide __len__
pub const Sized = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__len__"};

    pub fn isSized(comptime T: type) bool {
        if (@hasDecl(T, "__len__") or @hasDecl(T, "len")) return true;
        const info = @typeInfo(T);
        return info == .array or (info == .pointer and info.pointer.size == .Slice);
    }
};

/// ABC for classes that provide __call__
pub const Callable = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__call__"};

    pub fn isCallable(comptime T: type) bool {
        return @hasDecl(T, "__call__") or @typeInfo(T) == .@"fn" or @typeInfo(T) == .pointer;
    }
};

/// ABC for classes that provide __contains__
pub const Container = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__contains__"};

    pub fn isContainer(comptime T: type) bool {
        return @hasDecl(T, "__contains__") or @hasDecl(T, "contains");
    }
};

/// ABC for collections - combines Sized, Iterable, Container
pub const Collection = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__len__", "__iter__", "__contains__" };

    pub fn isCollection(comptime T: type) bool {
        return Sized.isSized(T) and Iterable.isIterable(T) and Container.isContainer(T);
    }
};

/// ABC for sequences (list-like)
pub const Sequence = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__getitem__", "__len__" };

    pub fn isSequence(comptime T: type) bool {
        if (@hasDecl(T, "__getitem__") and @hasDecl(T, "__len__")) return true;
        const info = @typeInfo(T);
        return info == .array or (info == .pointer and info.pointer.size == .Slice);
    }
};

/// ABC for mutable sequences
pub const MutableSequence = struct {
    pub const __abstractmethods__ = &[_][]const u8{
        "__getitem__", "__setitem__", "__delitem__", "__len__", "insert",
    };

    pub fn isMutableSequence(comptime T: type) bool {
        return @hasDecl(T, "__setitem__") and @hasDecl(T, "insert") and Sequence.isSequence(T);
    }
};

/// ABC for sets
pub const Set = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__contains__", "__iter__", "__len__" };

    pub fn isSet(comptime T: type) bool {
        return Sized.isSized(T) and Iterable.isIterable(T) and Container.isContainer(T);
    }
};

/// ABC for mutable sets
pub const MutableSet = struct {
    pub const __abstractmethods__ = &[_][]const u8{
        "__contains__", "__iter__", "__len__", "add", "discard",
    };

    pub fn isMutableSet(comptime T: type) bool {
        return @hasDecl(T, "add") and @hasDecl(T, "discard") and Set.isSet(T);
    }
};

/// ABC for mappings (dict-like)
pub const Mapping = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__getitem__", "__iter__", "__len__" };

    pub fn isMapping(comptime T: type) bool {
        return @hasDecl(T, "__getitem__") and Iterable.isIterable(T) and Sized.isSized(T);
    }
};

/// ABC for mutable mappings
pub const MutableMapping = struct {
    pub const __abstractmethods__ = &[_][]const u8{
        "__getitem__", "__setitem__", "__delitem__", "__iter__", "__len__",
    };

    pub fn isMutableMapping(comptime T: type) bool {
        return @hasDecl(T, "__setitem__") and @hasDecl(T, "__delitem__") and Mapping.isMapping(T);
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Update an abstract base class to include additional abstract methods
pub fn updateAbstractMethods(
    allocator: std.mem.Allocator,
    existing: []const []const u8,
    new_methods: []const []const u8,
) ![]const []const u8 {
    var result = std.ArrayList([]const u8).init(allocator);
    errdefer result.deinit();

    // Add existing methods
    for (existing) |method| {
        try result.append(method);
    }

    // Add new methods if not already present
    for (new_methods) |new_method| {
        var found = false;
        for (existing) |method| {
            if (std.mem.eql(u8, method, new_method)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try result.append(new_method);
        }
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Tests
// ============================================================================

test "Hashable check" {
    try std.testing.expect(Hashable.isHashable(i32));
    try std.testing.expect(Hashable.isHashable(f64));
}

test "Sized check" {
    try std.testing.expect(Sized.isSized([5]u8));
    try std.testing.expect(Sized.isSized([]const u8));
}

test "Iterable check" {
    try std.testing.expect(Iterable.isIterable([5]u8));
    try std.testing.expect(Iterable.isIterable([]const u8));
}

test "Sequence check" {
    try std.testing.expect(Sequence.isSequence([5]u8));
    try std.testing.expect(Sequence.isSequence([]const u8));
}

test "ABCMeta registry" {
    const allocator = std.testing.allocator;
    var meta = ABCMeta.init(allocator);
    defer meta.deinit();

    try meta.register("Iterable", "MyList");
    try meta.register("Iterable", "MySet");

    try std.testing.expect(meta.isRegistered("Iterable", "MyList"));
    try std.testing.expect(meta.isRegistered("Iterable", "MySet"));
    try std.testing.expect(!meta.isRegistered("Iterable", "MyDict"));

    const subclasses = meta.getSubclasses("Iterable").?;
    try std.testing.expectEqual(@as(usize, 2), subclasses.len);
}

test "abstractmethod decorator" {
    const TestABC = struct {
        fn myMethod(self: *@This()) void {
            _ = self;
        }
    };

    const decorated = abstractmethod(TestABC.myMethod);
    try std.testing.expect(@TypeOf(decorated) == @TypeOf(TestABC.myMethod));
}

test "getAbstractMethods" {
    const methods = getAbstractMethods(Hashable);
    try std.testing.expectEqual(@as(usize, 1), methods.len);
    try std.testing.expectEqualStrings("__hash__", methods[0]);
}
