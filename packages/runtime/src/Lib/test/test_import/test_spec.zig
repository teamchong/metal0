//! test.test_import.test_spec - ModuleSpec testing (PEP 451)
//!
//! Tests for Python's ModuleSpec class which defines how modules are loaded:
//! - Module spec creation and attributes
//! - Loader binding
//! - Submodule search locations
//! - Cached file handling
//! - Module creation from spec

const std = @import("std");
const Allocator = std.mem.Allocator;

/// ModuleSpec - Core specification object for module loading (PEP 451)
pub const ModuleSpec = struct {
    /// The fully qualified name of the module
    name: []const u8,

    /// The loader used to load the module
    loader: ?*const Loader,

    /// The path to the module source (usually __file__)
    origin: ?[]const u8,

    /// List of search paths for submodules (packages only)
    submodule_search_locations: ?SubmoduleSearchLocations,

    /// Loader-specific state
    loader_state: ?*anyopaque,

    /// Path to cached bytecode file
    cached: ?[]const u8,

    /// Name of the parent package
    parent: ?[]const u8,

    /// Whether the spec has a location (origin)
    has_location: bool,

    allocator: Allocator,

    /// Create a new ModuleSpec with just a name
    pub fn init(allocator: Allocator, name: []const u8) ModuleSpec {
        return .{
            .name = name,
            .loader = null,
            .origin = null,
            .submodule_search_locations = null,
            .loader_state = null,
            .cached = null,
            .parent = null,
            .has_location = false,
            .allocator = allocator,
        };
    }

    /// Create a ModuleSpec with full parameters
    pub fn create(
        allocator: Allocator,
        name: []const u8,
        loader: ?*const Loader,
        origin: ?[]const u8,
        is_package: bool,
    ) !ModuleSpec {
        var spec = ModuleSpec.init(allocator, name);
        spec.loader = loader;
        spec.origin = origin;
        spec.has_location = origin != null;

        // Set parent package name
        if (std.mem.lastIndexOfScalar(u8, name, '.')) |idx| {
            spec.parent = name[0..idx];
        } else {
            spec.parent = "";
        }

        // Initialize submodule search locations for packages
        if (is_package) {
            spec.submodule_search_locations = SubmoduleSearchLocations.init(allocator);
            if (origin) |o| {
                // Add the package directory to search locations
                if (std.mem.lastIndexOfScalar(u8, o, '/')) |idx| {
                    try spec.submodule_search_locations.?.append(o[0..idx]);
                }
            }
        }

        return spec;
    }

    /// Check if this spec represents a package
    pub fn isPackage(self: *const ModuleSpec) bool {
        return self.submodule_search_locations != null;
    }

    /// Get the module's __file__ attribute value
    pub fn getFilename(self: *const ModuleSpec) ?[]const u8 {
        if (self.has_location) {
            return self.origin;
        }
        return null;
    }

    /// Get the cached bytecode path
    pub fn getCachedPath(self: *const ModuleSpec) ?[]const u8 {
        if (self.cached) |c| return c;

        // Auto-compute from origin if not set
        if (self.origin) |o| {
            // Would compute __pycache__ path here
            _ = o;
        }
        return null;
    }

    /// Set the loader
    pub fn withLoader(self: ModuleSpec, loader: *const Loader) ModuleSpec {
        var spec = self;
        spec.loader = loader;
        return spec;
    }

    /// Set the origin
    pub fn withOrigin(self: ModuleSpec, origin: []const u8) ModuleSpec {
        var spec = self;
        spec.origin = origin;
        spec.has_location = true;
        return spec;
    }

    /// Set as package
    pub fn asPackage(self: ModuleSpec) !ModuleSpec {
        var spec = self;
        if (spec.submodule_search_locations == null) {
            spec.submodule_search_locations = SubmoduleSearchLocations.init(spec.allocator);
        }
        return spec;
    }

    pub fn deinit(self: *ModuleSpec) void {
        if (self.submodule_search_locations) |*locs| {
            locs.deinit();
        }
    }
};

/// Submodule search locations (similar to __path__)
pub const SubmoduleSearchLocations = struct {
    paths: std.ArrayListUnmanaged([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) SubmoduleSearchLocations {
        return .{
            .paths = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SubmoduleSearchLocations) void {
        self.paths.deinit(self.allocator);
    }

    pub fn append(self: *SubmoduleSearchLocations, path: []const u8) !void {
        try self.paths.append(self.allocator, path);
    }

    pub fn insert(self: *SubmoduleSearchLocations, index: usize, path: []const u8) !void {
        try self.paths.insert(self.allocator, index, path);
    }

    pub fn len(self: *const SubmoduleSearchLocations) usize {
        return self.paths.items.len;
    }

    pub fn get(self: *const SubmoduleSearchLocations, index: usize) ?[]const u8 {
        if (index >= self.paths.items.len) return null;
        return self.paths.items[index];
    }

    pub fn contains(self: *const SubmoduleSearchLocations, path: []const u8) bool {
        for (self.paths.items) |p| {
            if (std.mem.eql(u8, p, path)) return true;
        }
        return false;
    }
};

/// Loader interface
pub const Loader = struct {
    vtable: *const VTable,

    pub const VTable = struct {
        create_module: *const fn (*const Loader, *const ModuleSpec) ?*Module,
        exec_module: *const fn (*const Loader, *Module) LoaderError!void,
        get_code: *const fn (*const Loader, []const u8) ?*const Code,
        get_source: *const fn (*const Loader, []const u8) ?[]const u8,
        is_package: *const fn (*const Loader, []const u8) bool,
    };

    pub fn createModule(self: *const Loader, spec: *const ModuleSpec) ?*Module {
        return self.vtable.create_module(self, spec);
    }

    pub fn execModule(self: *const Loader, module: *Module) LoaderError!void {
        return self.vtable.exec_module(self, module);
    }

    pub fn getCode(self: *const Loader, fullname: []const u8) ?*const Code {
        return self.vtable.get_code(self, fullname);
    }

    pub fn getSource(self: *const Loader, fullname: []const u8) ?[]const u8 {
        return self.vtable.get_source(self, fullname);
    }

    pub fn isPackage(self: *const Loader, fullname: []const u8) bool {
        return self.vtable.is_package(self, fullname);
    }
};

pub const LoaderError = error{
    LoadFailed,
    ExecutionFailed,
    InvalidBytecode,
    SourceNotAvailable,
};

/// Code object representation
pub const Code = struct {
    filename: []const u8,
    name: []const u8,
    bytecode: []const u8,
    constants: []const Constant,
    flags: CodeFlags,

    pub const CodeFlags = packed struct {
        optimized: bool = false,
        newlocals: bool = false,
        varargs: bool = false,
        varkeywords: bool = false,
        nested: bool = false,
        generator: bool = false,
        nofree: bool = false,
        coroutine: bool = false,
        _padding: u8 = 0,
    };

    pub const Constant = union(enum) {
        none,
        boolean: bool,
        integer: i64,
        float: f64,
        string: []const u8,
        bytes: []const u8,
        tuple: []const Constant,
        code: *const Code,
    };
};

/// Module representation
pub const Module = struct {
    __name__: []const u8,
    __file__: ?[]const u8,
    __loader__: ?*const Loader,
    __package__: ?[]const u8,
    __spec__: ?*const ModuleSpec,
    __path__: ?SubmoduleSearchLocations,
    __doc__: ?[]const u8,
    __dict__: std.StringHashMapUnmanaged(ModuleValue),
    allocator: Allocator,

    pub const ModuleValue = union(enum) {
        none,
        boolean: bool,
        integer: i64,
        float: f64,
        string: []const u8,
        module: *Module,
        function: *anyopaque,
        class: *anyopaque,
    };

    pub fn init(allocator: Allocator, name: []const u8) !*Module {
        const module = try allocator.create(Module);
        module.* = .{
            .__name__ = name,
            .__file__ = null,
            .__loader__ = null,
            .__package__ = null,
            .__spec__ = null,
            .__path__ = null,
            .__doc__ = null,
            .__dict__ = .{},
            .allocator = allocator,
        };
        return module;
    }

    pub fn deinit(self: *Module) void {
        self.__dict__.deinit(self.allocator);
        if (self.__path__) |*p| p.deinit();
        self.allocator.destroy(self);
    }

    pub fn fromSpec(spec: *const ModuleSpec) !*Module {
        const module = try Module.init(spec.allocator, spec.name);
        module.__spec__ = spec;
        module.__loader__ = spec.loader;
        module.__file__ = spec.origin;
        module.__package__ = spec.parent;

        if (spec.submodule_search_locations) |locs| {
            module.__path__ = SubmoduleSearchLocations.init(spec.allocator);
            for (locs.paths.items) |path| {
                try module.__path__.?.append(path);
            }
        }

        return module;
    }

    pub fn setAttr(self: *Module, name: []const u8, value: ModuleValue) !void {
        try self.__dict__.put(self.allocator, name, value);
    }

    pub fn getAttr(self: *const Module, name: []const u8) ?ModuleValue {
        if (std.mem.eql(u8, name, "__name__")) return .{ .string = self.__name__ };
        if (std.mem.eql(u8, name, "__file__")) {
            if (self.__file__) |f| return .{ .string = f };
            return .none;
        }
        return self.__dict__.get(name);
    }

    pub fn isPackage(self: *const Module) bool {
        return self.__path__ != null;
    }
};

/// Spec factory functions
pub const SpecFactory = struct {
    /// Create spec for a source file module
    pub fn fromSourceFile(allocator: Allocator, name: []const u8, path: []const u8, loader: *const Loader) !ModuleSpec {
        return try ModuleSpec.create(allocator, name, loader, path, false);
    }

    /// Create spec for a package
    pub fn fromPackage(allocator: Allocator, name: []const u8, path: []const u8, loader: *const Loader) !ModuleSpec {
        return try ModuleSpec.create(allocator, name, loader, path, true);
    }

    /// Create spec for a namespace package (PEP 420)
    pub fn forNamespacePackage(allocator: Allocator, name: []const u8, paths: []const []const u8) !ModuleSpec {
        var spec = ModuleSpec.init(allocator, name);
        spec.submodule_search_locations = SubmoduleSearchLocations.init(allocator);
        for (paths) |path| {
            try spec.submodule_search_locations.?.append(path);
        }
        // Set parent
        if (std.mem.lastIndexOfScalar(u8, name, '.')) |idx| {
            spec.parent = name[0..idx];
        } else {
            spec.parent = "";
        }
        return spec;
    }

    /// Create spec for a builtin module
    pub fn forBuiltin(allocator: Allocator, name: []const u8, loader: *const Loader) ModuleSpec {
        var spec = ModuleSpec.init(allocator, name);
        spec.loader = loader;
        spec.origin = "built-in";
        return spec;
    }

    /// Create spec for a frozen module
    pub fn forFrozen(allocator: Allocator, name: []const u8, loader: *const Loader) ModuleSpec {
        var spec = ModuleSpec.init(allocator, name);
        spec.loader = loader;
        spec.origin = "frozen";
        return spec;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "module_spec_basic_init" {
    var spec = ModuleSpec.init(std.testing.allocator, "mymodule");
    defer spec.deinit();

    try std.testing.expectEqualStrings("mymodule", spec.name);
    try std.testing.expect(spec.loader == null);
    try std.testing.expect(spec.origin == null);
    try std.testing.expect(!spec.has_location);
    try std.testing.expect(!spec.isPackage());
}

test "module_spec_create_module" {
    var spec = try ModuleSpec.create(std.testing.allocator, "mypackage.submodule", null, "/path/to/submodule.py", false);
    defer spec.deinit();

    try std.testing.expectEqualStrings("mypackage.submodule", spec.name);
    try std.testing.expect(spec.parent != null);
    try std.testing.expectEqualStrings("mypackage", spec.parent.?);
    try std.testing.expect(spec.has_location);
    try std.testing.expectEqualStrings("/path/to/submodule.py", spec.origin.?);
}

test "module_spec_create_package" {
    var spec = try ModuleSpec.create(std.testing.allocator, "mypackage", null, "/path/to/mypackage/__init__.py", true);
    defer spec.deinit();

    try std.testing.expect(spec.isPackage());
    try std.testing.expect(spec.submodule_search_locations != null);
    try std.testing.expectEqual(@as(usize, 1), spec.submodule_search_locations.?.len());
    try std.testing.expectEqualStrings("/path/to/mypackage", spec.submodule_search_locations.?.get(0).?);
}

test "module_spec_with_methods" {
    var spec = ModuleSpec.init(std.testing.allocator, "test");
    defer spec.deinit();

    spec = spec.withOrigin("/path/to/test.py");
    try std.testing.expect(spec.has_location);
    try std.testing.expectEqualStrings("/path/to/test.py", spec.origin.?);
}

test "module_spec_get_filename" {
    var spec = ModuleSpec.init(std.testing.allocator, "test");
    defer spec.deinit();

    try std.testing.expect(spec.getFilename() == null);

    spec = spec.withOrigin("/path/to/test.py");
    try std.testing.expectEqualStrings("/path/to/test.py", spec.getFilename().?);
}

test "submodule_search_locations" {
    var locs = SubmoduleSearchLocations.init(std.testing.allocator);
    defer locs.deinit();

    try locs.append("/path/a");
    try locs.append("/path/b");
    try locs.insert(1, "/path/inserted");

    try std.testing.expectEqual(@as(usize, 3), locs.len());
    try std.testing.expectEqualStrings("/path/a", locs.get(0).?);
    try std.testing.expectEqualStrings("/path/inserted", locs.get(1).?);
    try std.testing.expectEqualStrings("/path/b", locs.get(2).?);

    try std.testing.expect(locs.contains("/path/a"));
    try std.testing.expect(!locs.contains("/nonexistent"));
}

test "module_creation" {
    const module = try Module.init(std.testing.allocator, "testmod");
    defer module.deinit();

    try std.testing.expectEqualStrings("testmod", module.__name__);
    try std.testing.expect(module.__file__ == null);
    try std.testing.expect(!module.isPackage());
}

test "module_from_spec" {
    var spec = try ModuleSpec.create(std.testing.allocator, "mypackage", null, "/path/to/__init__.py", true);
    defer spec.deinit();

    const module = try Module.fromSpec(&spec);
    defer module.deinit();

    try std.testing.expectEqualStrings("mypackage", module.__name__);
    try std.testing.expect(module.isPackage());
    try std.testing.expect(module.__path__ != null);
}

test "module_setattr_getattr" {
    const module = try Module.init(std.testing.allocator, "test");
    defer module.deinit();

    try module.setAttr("custom", .{ .integer = 42 });

    const val = module.getAttr("custom");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 42), val.?.integer);

    const name = module.getAttr("__name__");
    try std.testing.expect(name != null);
    try std.testing.expectEqualStrings("test", name.?.string);
}

test "spec_factory_namespace_package" {
    var spec = try SpecFactory.forNamespacePackage(std.testing.allocator, "mynamespace", &.{ "/path/a", "/path/b" });
    defer spec.deinit();

    try std.testing.expect(spec.isPackage());
    try std.testing.expect(spec.origin == null);
    try std.testing.expectEqual(@as(usize, 2), spec.submodule_search_locations.?.len());
}

test "spec_factory_builtin" {
    const spec = SpecFactory.forBuiltin(std.testing.allocator, "sys", undefined);

    try std.testing.expectEqualStrings("sys", spec.name);
    try std.testing.expectEqualStrings("built-in", spec.origin.?);
}

test "spec_factory_frozen" {
    const spec = SpecFactory.forFrozen(std.testing.allocator, "_frozen_importlib", undefined);

    try std.testing.expectEqualStrings("_frozen_importlib", spec.name);
    try std.testing.expectEqualStrings("frozen", spec.origin.?);
}

test "code_flags" {
    const flags = Code.CodeFlags{
        .optimized = true,
        .generator = true,
    };

    try std.testing.expect(flags.optimized);
    try std.testing.expect(!flags.newlocals);
    try std.testing.expect(flags.generator);
}

test "module_value_types" {
    const none_val = Module.ModuleValue.none;
    try std.testing.expect(none_val == .none);

    const int_val = Module.ModuleValue{ .integer = 123 };
    try std.testing.expectEqual(@as(i64, 123), int_val.integer);

    const str_val = Module.ModuleValue{ .string = "hello" };
    try std.testing.expectEqualStrings("hello", str_val.string);
}
