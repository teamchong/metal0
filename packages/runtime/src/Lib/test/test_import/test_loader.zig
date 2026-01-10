//! test.test_import.test_loader - Loader testing
//!
//! Tests for Python's import loaders including:
//! - Abstract loader interface (ABC)
//! - SourceLoader for .py files
//! - SourcelessLoader for .pyc files
//! - ExtensionFileLoader for .so/.pyd files
//! - InspectLoader for source introspection
//! - Loader protocol methods (create_module, exec_module, load_module)

const std = @import("std");
const Allocator = std.mem.Allocator;

/// LoaderError - Errors that can occur during module loading
pub const LoaderError = error{
    ModuleNotFound,
    LoadFailed,
    ExecutionFailed,
    InvalidBytecode,
    SourceNotAvailable,
    CompilationError,
    ImportError,
    OutOfMemory,
};

/// Abstract Loader interface (ABC)
pub const Loader = struct {
    vtable: *const VTable,
    context: *anyopaque,

    pub const VTable = struct {
        /// Create a module from spec (returns null to use default)
        create_module: *const fn (*anyopaque, *const ModuleSpec) LoaderError!?*Module,

        /// Execute the module code
        exec_module: *const fn (*anyopaque, *Module) LoaderError!void,

        /// Legacy load_module (deprecated but still supported)
        load_module: *const fn (*anyopaque, []const u8) LoaderError!*Module,

        /// Get the module representation (for repr())
        module_repr: *const fn (*anyopaque, *const Module) ?[]const u8,
    };

    pub fn createModule(self: *const Loader, spec: *const ModuleSpec) LoaderError!?*Module {
        return self.vtable.create_module(self.context, spec);
    }

    pub fn execModule(self: *const Loader, module: *Module) LoaderError!void {
        return self.vtable.exec_module(self.context, module);
    }

    pub fn loadModule(self: *const Loader, fullname: []const u8) LoaderError!*Module {
        return self.vtable.load_module(self.context, fullname);
    }

    pub fn moduleRepr(self: *const Loader, module: *const Module) ?[]const u8 {
        return self.vtable.module_repr(self.context, module);
    }
};

/// InspectLoader - Loader that can provide source code
pub const InspectLoader = struct {
    base: Loader,
    inspect_vtable: *const InspectVTable,

    pub const InspectVTable = struct {
        /// Get the source code for a module
        get_source: *const fn (*anyopaque, []const u8) LoaderError!?[]const u8,

        /// Get the code object (compiled) for a module
        get_code: *const fn (*anyopaque, []const u8) LoaderError!?*CodeObject,

        /// Check if the module is a package
        is_package: *const fn (*anyopaque, []const u8) bool,
    };

    pub fn getSource(self: *const InspectLoader, fullname: []const u8) LoaderError!?[]const u8 {
        return self.inspect_vtable.get_source(self.base.context, fullname);
    }

    pub fn getCode(self: *const InspectLoader, fullname: []const u8) LoaderError!?*CodeObject {
        return self.inspect_vtable.get_code(self.base.context, fullname);
    }

    pub fn isPackage(self: *const InspectLoader, fullname: []const u8) bool {
        return self.inspect_vtable.is_package(self.base.context, fullname);
    }
};

/// ExecutionLoader - Loader that can get filename
pub const ExecutionLoader = struct {
    base: InspectLoader,
    exec_vtable: *const ExecVTable,

    pub const ExecVTable = struct {
        /// Get the filename for a module
        get_filename: *const fn (*anyopaque, []const u8) LoaderError!?[]const u8,
    };

    pub fn getFilename(self: *const ExecutionLoader, fullname: []const u8) LoaderError!?[]const u8 {
        return self.exec_vtable.get_filename(self.base.base.context, fullname);
    }
};

/// ModuleSpec - Specification for how to load a module
pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*const Loader,
    origin: ?[]const u8,
    cached: ?[]const u8,
    parent: ?[]const u8,
    submodule_search_locations: ?[]const []const u8,
    has_location: bool,
    loader_state: ?*anyopaque,

    pub fn init(name: []const u8) ModuleSpec {
        return .{
            .name = name,
            .loader = null,
            .origin = null,
            .cached = null,
            .parent = null,
            .submodule_search_locations = null,
            .has_location = false,
            .loader_state = null,
        };
    }

    pub fn isPackage(self: *const ModuleSpec) bool {
        return self.submodule_search_locations != null;
    }
};

/// Module - Represents a loaded Python module
pub const Module = struct {
    __name__: []const u8,
    __file__: ?[]const u8,
    __loader__: ?*const Loader,
    __package__: ?[]const u8,
    __spec__: ?*const ModuleSpec,
    __path__: ?[]const []const u8,
    __doc__: ?[]const u8,
    __dict__: std.StringHashMapUnmanaged(Value),
    __cached__: ?[]const u8,
    initialized: bool,
    allocator: Allocator,

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
            .__cached__ = null,
            .initialized = false,
            .allocator = allocator,
        };
        return module;
    }

    pub fn deinit(self: *Module) void {
        self.__dict__.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setAttr(self: *Module, name: []const u8, value: Value) !void {
        try self.__dict__.put(self.allocator, name, value);
    }

    pub fn getAttr(self: *const Module, name: []const u8) ?Value {
        return self.__dict__.get(name);
    }

    pub fn hasAttr(self: *const Module, name: []const u8) bool {
        return self.__dict__.contains(name);
    }

    pub fn delAttr(self: *Module, name: []const u8) bool {
        return self.__dict__.remove(name);
    }
};

/// Value - Generic Python value
pub const Value = union(enum) {
    none,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    bytes: []const u8,
    list: []Value,
    dict: *std.StringHashMapUnmanaged(Value),
    function: *anyopaque,
    class: *anyopaque,
    module: *Module,
    code: *CodeObject,

    pub fn isNone(self: Value) bool {
        return self == .none;
    }
};

/// CodeObject - Compiled Python code
pub const CodeObject = struct {
    co_name: []const u8,
    co_filename: []const u8,
    co_code: []const u8,
    co_consts: []const Value,
    co_names: []const []const u8,
    co_varnames: []const []const u8,
    co_freevars: []const []const u8,
    co_cellvars: []const []const u8,
    co_argcount: u32,
    co_posonlyargcount: u32,
    co_kwonlyargcount: u32,
    co_nlocals: u32,
    co_stacksize: u32,
    co_flags: CodeFlags,
    co_firstlineno: u32,
    co_lnotab: []const u8,

    pub const CodeFlags = packed struct {
        optimized: bool = false,
        newlocals: bool = false,
        varargs: bool = false,
        varkeywords: bool = false,
        nested: bool = false,
        generator: bool = false,
        nofree: bool = false,
        coroutine: bool = false,
        iterable_coroutine: bool = false,
        async_generator: bool = false,
        _padding: u6 = 0,
    };
};

/// SourceLoader - Loader for .py source files
pub const SourceLoader = struct {
    path: []const u8,
    source_cache: std.StringHashMapUnmanaged([]const u8),
    mtime_cache: std.StringHashMapUnmanaged(i64),
    allocator: Allocator,

    pub fn init(allocator: Allocator, path: []const u8) SourceLoader {
        return .{
            .path = path,
            .source_cache = .{},
            .mtime_cache = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SourceLoader) void {
        self.source_cache.deinit(self.allocator);
        self.mtime_cache.deinit(self.allocator);
    }

    /// Get the path to the source file
    pub fn getSourcePath(self: *const SourceLoader, fullname: []const u8) ![]u8 {
        // Convert module name to file path
        var buf = std.ArrayList(u8).init(self.allocator);
        try buf.appendSlice(self.path);
        try buf.append('/');

        var iter = std.mem.splitScalar(u8, fullname, '.');
        var first = true;
        while (iter.next()) |part| {
            if (!first) try buf.append('/');
            try buf.appendSlice(part);
            first = false;
        }
        try buf.appendSlice(".py");

        return buf.toOwnedSlice();
    }

    /// Read the source code from file
    pub fn getSource(self: *SourceLoader, fullname: []const u8) !?[]const u8 {
        // Check cache first
        if (self.source_cache.get(fullname)) |cached| {
            return cached;
        }

        const path = try self.getSourcePath(fullname);
        defer self.allocator.free(path);

        // In real implementation, would read file here
        // For testing, return placeholder
        return null;
    }

    /// Get the modification time of the source
    pub fn getSourceMtime(self: *const SourceLoader, fullname: []const u8) ?i64 {
        return self.mtime_cache.get(fullname);
    }

    /// Set cached bytecode path
    pub fn getCachedPath(self: *const SourceLoader, fullname: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        try buf.appendSlice(self.path);
        try buf.appendSlice("/__pycache__/");

        // Replace dots with slashes for package path
        var iter = std.mem.splitScalar(u8, fullname, '.');
        if (iter.next()) |first| {
            try buf.appendSlice(first);
        }
        while (iter.next()) |part| {
            try buf.append('/');
            try buf.appendSlice(part);
        }
        try buf.appendSlice(".cpython-311.pyc");

        return buf.toOwnedSlice();
    }

    /// Check if this is a package
    pub fn isPackage(self: *const SourceLoader, fullname: []const u8) bool {
        // Check if __init__.py exists
        var buf: [512]u8 = undefined;
        const init_path = std.fmt.bufPrint(&buf, "{s}/{s}/__init__.py", .{
            self.path,
            fullname,
        }) catch return false;
        _ = init_path;
        // Would check file existence here
        return false;
    }

    /// Create a module from spec
    pub fn createModule(self: *SourceLoader, spec: *const ModuleSpec) !*Module {
        const module = try Module.init(self.allocator, spec.name);
        module.__spec__ = spec;
        module.__file__ = spec.origin;
        module.__cached__ = spec.cached;
        if (spec.submodule_search_locations) |locs| {
            module.__path__ = locs;
        }
        return module;
    }

    /// Execute the module
    pub fn execModule(self: *SourceLoader, module: *Module) !void {
        // Get source and compile/execute
        if (try self.getSource(module.__name__)) |_| {
            // Would compile and execute here
            module.initialized = true;
        }
    }
};

/// SourcelessLoader - Loader for .pyc bytecode files only
pub const SourcelessLoader = struct {
    path: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, path: []const u8) SourcelessLoader {
        return .{
            .path = path,
            .allocator = allocator,
        };
    }

    /// Get path to bytecode file
    pub fn getBytecodeFile(self: *const SourcelessLoader, fullname: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        try buf.appendSlice(self.path);
        try buf.append('/');

        var iter = std.mem.splitScalar(u8, fullname, '.');
        var first = true;
        while (iter.next()) |part| {
            if (!first) try buf.append('/');
            try buf.appendSlice(part);
            first = false;
        }
        try buf.appendSlice(".pyc");

        return buf.toOwnedSlice();
    }

    /// Validate bytecode header
    pub fn validateBytecode(data: []const u8) bool {
        if (data.len < 16) return false;
        // Check magic number (Python 3.11)
        if (data[0] != 0xa7 or data[1] != 0x0d) return false;
        return true;
    }

    /// Get source (always returns null for sourceless)
    pub fn getSource(_: *const SourcelessLoader, _: []const u8) ?[]const u8 {
        return null;
    }
};

/// ExtensionFileLoader - Loader for .so/.pyd extension modules
pub const ExtensionFileLoader = struct {
    name: []const u8,
    path: []const u8,
    handle: ?*anyopaque,

    pub fn init(name: []const u8, path: []const u8) ExtensionFileLoader {
        return .{
            .name = name,
            .path = path,
            .handle = null,
        };
    }

    /// Get the init function name for the extension
    pub fn getInitFuncName(self: *const ExtensionFileLoader) []const u8 {
        // PyInit_<module_name>
        _ = self;
        return "PyInit_module";
    }

    /// Check if module is a package (extensions cannot be packages)
    pub fn isPackage(_: *const ExtensionFileLoader) bool {
        return false;
    }

    /// Load the extension module
    pub fn load(self: *ExtensionFileLoader) LoaderError!void {
        // Would use dlopen/LoadLibrary here
        _ = self;
    }

    /// Create module from extension
    pub fn createModule(_: *const ExtensionFileLoader, _: *const ModuleSpec) ?*Module {
        // Would call PyInit_<name> here
        return null;
    }
};

/// FileLoader - Base class for file-based loaders
pub const FileLoader = struct {
    name: []const u8,
    path: []const u8,

    pub fn init(name: []const u8, path: []const u8) FileLoader {
        return .{
            .name = name,
            .path = path,
        };
    }

    pub fn getFilename(self: *const FileLoader) []const u8 {
        return self.path;
    }

    pub fn getData(self: *const FileLoader, allocator: Allocator) ![]u8 {
        // Would read file contents here
        _ = self;
        return try allocator.alloc(u8, 0);
    }
};

/// LoaderRegistry - Registry of loaders by extension
pub const LoaderRegistry = struct {
    loaders: std.StringHashMapUnmanaged(LoaderFactory),
    allocator: Allocator,

    pub const LoaderFactory = *const fn ([]const u8, []const u8) *Loader;

    pub fn init(allocator: Allocator) LoaderRegistry {
        return .{
            .loaders = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LoaderRegistry) void {
        self.loaders.deinit(self.allocator);
    }

    pub fn register(self: *LoaderRegistry, extension: []const u8, factory: LoaderFactory) !void {
        try self.loaders.put(self.allocator, extension, factory);
    }

    pub fn getLoader(self: *const LoaderRegistry, extension: []const u8) ?LoaderFactory {
        return self.loaders.get(extension);
    }

    pub fn getSupportedExtensions(self: *const LoaderRegistry, allocator: Allocator) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(allocator);
        var iter = self.loaders.keyIterator();
        while (iter.next()) |key| {
            try result.append(key.*);
        }
        return result.toOwnedSlice();
    }
};

// =============================================================================
// Tests
// =============================================================================

test "module_creation" {
    const module = try Module.init(std.testing.allocator, "test_module");
    defer module.deinit();

    try std.testing.expectEqualStrings("test_module", module.__name__);
    try std.testing.expect(!module.initialized);
}

test "module_attributes" {
    const module = try Module.init(std.testing.allocator, "test");
    defer module.deinit();

    try module.setAttr("foo", .{ .integer = 42 });
    try module.setAttr("bar", .{ .string = "hello" });

    const foo = module.getAttr("foo");
    try std.testing.expect(foo != null);
    try std.testing.expectEqual(@as(i64, 42), foo.?.integer);

    try std.testing.expect(module.hasAttr("foo"));
    try std.testing.expect(!module.hasAttr("baz"));

    try std.testing.expect(module.delAttr("foo"));
    try std.testing.expect(!module.hasAttr("foo"));
}

test "module_spec_basic" {
    const spec = ModuleSpec.init("mymodule");

    try std.testing.expectEqualStrings("mymodule", spec.name);
    try std.testing.expect(!spec.isPackage());
    try std.testing.expect(!spec.has_location);
}

test "source_loader_path" {
    var loader = SourceLoader.init(std.testing.allocator, "/usr/lib/python3");
    defer loader.deinit();

    const path = try loader.getSourcePath("os.path");
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/usr/lib/python3/os/path.py", path);
}

test "source_loader_cached_path" {
    var loader = SourceLoader.init(std.testing.allocator, "/usr/lib/python3");
    defer loader.deinit();

    const path = try loader.getCachedPath("os.path");
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/usr/lib/python3/__pycache__/os/path.cpython-311.pyc", path);
}

test "sourceless_loader_bytecode_path" {
    const loader = SourcelessLoader.init(std.testing.allocator, "/usr/lib/python3");

    const path = try loader.getBytecodeFile("mymodule");
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/usr/lib/python3/mymodule.pyc", path);
}

test "sourceless_loader_validate" {
    const valid_bytecode = &[_]u8{ 0xa7, 0x0d, 0x0d, 0x0a } ++ &[_]u8{0} ** 12;
    try std.testing.expect(SourcelessLoader.validateBytecode(valid_bytecode));

    const invalid_bytecode = &[_]u8{ 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expect(!SourcelessLoader.validateBytecode(invalid_bytecode));

    const too_short = &[_]u8{ 0xa7, 0x0d };
    try std.testing.expect(!SourcelessLoader.validateBytecode(too_short));
}

test "extension_loader_basic" {
    const loader = ExtensionFileLoader.init("myext", "/path/to/myext.so");

    try std.testing.expectEqualStrings("myext", loader.name);
    try std.testing.expectEqualStrings("/path/to/myext.so", loader.path);
    try std.testing.expect(!loader.isPackage());
}

test "file_loader_basic" {
    const loader = FileLoader.init("test", "/path/to/test.py");

    try std.testing.expectEqualStrings("/path/to/test.py", loader.getFilename());
}

test "loader_registry" {
    var registry = LoaderRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const dummy_factory: LoaderRegistry.LoaderFactory = struct {
        fn factory(_: []const u8, _: []const u8) *Loader {
            return undefined;
        }
    }.factory;

    try registry.register(".py", dummy_factory);
    try registry.register(".pyc", dummy_factory);

    try std.testing.expect(registry.getLoader(".py") != null);
    try std.testing.expect(registry.getLoader(".pyc") != null);
    try std.testing.expect(registry.getLoader(".so") == null);

    const exts = try registry.getSupportedExtensions(std.testing.allocator);
    defer std.testing.allocator.free(exts);
    try std.testing.expectEqual(@as(usize, 2), exts.len);
}

test "code_object_flags" {
    const flags = CodeObject.CodeFlags{
        .optimized = true,
        .generator = true,
        .coroutine = false,
    };

    try std.testing.expect(flags.optimized);
    try std.testing.expect(flags.generator);
    try std.testing.expect(!flags.coroutine);
    try std.testing.expect(!flags.varargs);
}

test "value_types" {
    const none_val = Value.none;
    try std.testing.expect(none_val.isNone());

    const int_val = Value{ .integer = 42 };
    try std.testing.expect(!int_val.isNone());
    try std.testing.expectEqual(@as(i64, 42), int_val.integer);

    const str_val = Value{ .string = "test" };
    try std.testing.expectEqualStrings("test", str_val.string);
}

test "loader_error_types" {
    const err1: LoaderError = error.ModuleNotFound;
    const err2: LoaderError = error.LoadFailed;
    const err3: LoaderError = error.InvalidBytecode;

    try std.testing.expect(err1 != err2);
    try std.testing.expect(err2 != err3);
}
