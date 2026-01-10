//! test.test_module.test_loader - Module loader testing
//! Tests for Python's importlib loader classes
//! Reference: CPython Lib/test/test_importlib/test_abc.py

const std = @import("std");
const importlib = @import("../../importlib.zig");
const machinery = @import("../../importlib/machinery.zig");
const abc = @import("../../importlib/abc.zig");

// ============================================================================
// Loader Types from importlib
// ============================================================================

pub const SourceFileLoader = importlib.SourceFileLoader;
pub const SourcelessFileLoader = importlib.SourcelessFileLoader;
pub const ExtensionFileLoader = importlib.ExtensionFileLoader;
pub const Loader = importlib.Loader;
pub const ModuleSpec = importlib.ModuleSpec;

// ============================================================================
// Test Fixtures
// ============================================================================

/// Mock source loader for testing
pub const MockSourceLoader = struct {
    name: []const u8,
    path: []const u8,
    source: []const u8 = "# test module\n",
    is_package: bool = false,

    const Self = @This();

    pub fn init(name: []const u8, path: []const u8) Self {
        return .{ .name = name, .path = path };
    }

    pub fn initWithSource(name: []const u8, path: []const u8, source: []const u8) Self {
        return .{ .name = name, .path = path, .source = source };
    }

    pub fn getFilename(self: *const Self) []const u8 {
        return self.path;
    }

    pub fn getSource(self: *const Self) []const u8 {
        return self.source;
    }

    pub fn isPackage(self: *const Self) bool {
        return self.is_package;
    }

    pub fn createModule(self: *const Self, spec: *const ModuleSpec) ?*anyopaque {
        _ = self;
        _ = spec;
        return null;
    }

    pub fn execModule(self: *const Self, module: *anyopaque) !void {
        _ = self;
        _ = module;
    }
};

/// Mock bytecode loader for testing
pub const MockBytecodeLoader = struct {
    name: []const u8,
    path: []const u8,
    bytecode: []const u8 = "",

    const Self = @This();

    pub fn init(name: []const u8, path: []const u8) Self {
        return .{ .name = name, .path = path };
    }

    pub fn getFilename(self: *const Self) []const u8 {
        return self.path;
    }

    pub fn getBytecode(self: *const Self) []const u8 {
        return self.bytecode;
    }
};

/// Mock extension loader for testing
pub const MockExtensionLoader = struct {
    name: []const u8,
    path: []const u8,

    const Self = @This();

    pub fn init(name: []const u8, path: []const u8) Self {
        return .{ .name = name, .path = path };
    }

    pub fn getFilename(self: *const Self) []const u8 {
        return self.path;
    }

    pub fn createModule(self: *const Self, spec: *const ModuleSpec) ?*anyopaque {
        _ = self;
        _ = spec;
        return null;
    }
};

// ============================================================================
// Loader Protocol Tests
// ============================================================================

/// Test basic Loader protocol
pub const LoaderProtocolTest = struct {
    pub fn testCreateModuleReturnsNull() !void {
        const result = Loader.create_module(&ModuleSpec.init(std.heap.page_allocator, "test", null));
        try std.testing.expect(result == null);
    }

    pub fn testExecModuleDoesNotError() !void {
        var dummy: u8 = 0;
        try Loader.exec_module(&dummy);
    }

    pub fn testModuleReprReturnsString() !void {
        var dummy: u8 = 0;
        const repr = Loader.module_repr(&dummy);
        try std.testing.expectEqualStrings("<module>", repr);
    }
};

// ============================================================================
// SourceFileLoader Tests
// ============================================================================

/// Test SourceFileLoader initialization
pub fn testSourceFileLoaderInit() !void {
    const loader = SourceFileLoader.init("mymodule", "/path/to/mymodule.py");
    try std.testing.expectEqualStrings("mymodule", loader.name);
    try std.testing.expectEqualStrings("/path/to/mymodule.py", loader.path);
}

/// Test SourceFileLoader get_filename
pub fn testSourceFileLoaderGetFilename() !void {
    const loader = SourceFileLoader.init("test", "/test/module.py");
    const filename = loader.get_filename();
    try std.testing.expectEqualStrings("/test/module.py", filename);
}

/// Test SourceFileLoader with various paths
pub fn testSourceFileLoaderPaths() !void {
    // Absolute path
    const abs_loader = SourceFileLoader.init("abs", "/usr/lib/python3/module.py");
    try std.testing.expect(abs_loader.path[0] == '/');

    // Relative path
    const rel_loader = SourceFileLoader.init("rel", "module.py");
    try std.testing.expect(rel_loader.path[0] != '/');

    // Dotted module name
    const dot_loader = SourceFileLoader.init("pkg.sub.mod", "/pkg/sub/mod.py");
    try std.testing.expect(std.mem.indexOf(u8, dot_loader.name, ".") != null);
}

// ============================================================================
// SourcelessFileLoader Tests
// ============================================================================

/// Test SourcelessFileLoader initialization
pub fn testSourcelessFileLoaderInit() !void {
    const loader = SourcelessFileLoader.init("mymodule", "/path/to/mymodule.pyc");
    try std.testing.expectEqualStrings("mymodule", loader.name);
    try std.testing.expectEqualStrings("/path/to/mymodule.pyc", loader.path);
}

/// Test SourcelessFileLoader with pycache path
pub fn testSourcelessFileLoaderPycache() !void {
    const loader = SourcelessFileLoader.init(
        "mymodule",
        "/path/to/__pycache__/mymodule.cpython-312.pyc",
    );
    try std.testing.expect(std.mem.indexOf(u8, loader.path, "__pycache__") != null);
    try std.testing.expect(std.mem.endsWith(u8, loader.path, ".pyc"));
}

// ============================================================================
// ExtensionFileLoader Tests
// ============================================================================

/// Test ExtensionFileLoader initialization
pub fn testExtensionFileLoaderInit() !void {
    const loader = ExtensionFileLoader.init("_json", "/usr/lib/python3/lib-dynload/_json.so");
    try std.testing.expectEqualStrings("_json", loader.name);
    try std.testing.expectEqualStrings("/usr/lib/python3/lib-dynload/_json.so", loader.path);
}

/// Test ExtensionFileLoader get_filename
pub fn testExtensionFileLoaderGetFilename() !void {
    const loader = ExtensionFileLoader.init("_ctypes", "/lib/_ctypes.so");
    const filename = loader.get_filename();
    try std.testing.expectEqualStrings("/lib/_ctypes.so", filename);
}

/// Test ExtensionFileLoader with different extensions
pub fn testExtensionFileLoaderExtensions() !void {
    // .so extension (Unix)
    const so_loader = ExtensionFileLoader.init("mod", "/lib/mod.so");
    try std.testing.expect(std.mem.endsWith(u8, so_loader.path, ".so"));

    // .pyd extension (Windows)
    const pyd_loader = ExtensionFileLoader.init("mod", "C:\\Python\\mod.pyd");
    try std.testing.expect(std.mem.endsWith(u8, pyd_loader.path, ".pyd"));

    // .dylib extension (macOS)
    const dylib_loader = ExtensionFileLoader.init("mod", "/lib/mod.dylib");
    try std.testing.expect(std.mem.endsWith(u8, dylib_loader.path, ".dylib"));
}

// ============================================================================
// FileLoader ABC Tests
// ============================================================================

/// Test FileLoader abstract base class
pub fn testFileLoaderABC() !void {
    const loader = abc.FileLoader.init("test", "/path/to/test.py");
    try std.testing.expectEqualStrings("test", loader.name);
    try std.testing.expectEqualStrings("/path/to/test.py", loader.path);
}

/// Test FileLoader getFilename
pub fn testFileLoaderGetFilename() !void {
    const loader = abc.FileLoader.init("mod", "/mod.py");
    const filename = loader.getFilename("ignored");
    try std.testing.expectEqualStrings("/mod.py", filename);
}

// ============================================================================
// Mock Loader Tests
// ============================================================================

/// Test MockSourceLoader
pub fn testMockSourceLoader() !void {
    const loader = MockSourceLoader.init("test", "/test.py");
    try std.testing.expectEqualStrings("test", loader.name);
    try std.testing.expectEqualStrings("/test.py", loader.path);
    try std.testing.expect(!loader.isPackage());
}

/// Test MockSourceLoader with custom source
pub fn testMockSourceLoaderCustomSource() !void {
    const source = "def hello(): print('hello')";
    const loader = MockSourceLoader.initWithSource("hello", "/hello.py", source);
    try std.testing.expectEqualStrings(source, loader.getSource());
}

/// Test MockBytecodeLoader
pub fn testMockBytecodeLoader() !void {
    const loader = MockBytecodeLoader.init("cached", "/cached.pyc");
    try std.testing.expectEqualStrings("cached", loader.name);
    try std.testing.expectEqualStrings("/cached.pyc", loader.path);
}

/// Test MockExtensionLoader
pub fn testMockExtensionLoader() !void {
    const loader = MockExtensionLoader.init("_ext", "/_ext.so");
    try std.testing.expectEqualStrings("_ext", loader.name);
    try std.testing.expectEqualStrings("/_ext.so", loader.path);
}

// ============================================================================
// Loader Selection Tests
// ============================================================================

/// Determine loader type based on file extension
pub fn selectLoaderForPath(path: []const u8) enum { source, sourceless, extension, unknown } {
    if (std.mem.endsWith(u8, path, ".py")) {
        return .source;
    } else if (std.mem.endsWith(u8, path, ".pyc") or std.mem.endsWith(u8, path, ".pyo")) {
        return .sourceless;
    } else if (std.mem.endsWith(u8, path, ".so") or
        std.mem.endsWith(u8, path, ".pyd") or
        std.mem.endsWith(u8, path, ".dylib"))
    {
        return .extension;
    }
    return .unknown;
}

/// Test loader selection by extension
pub fn testLoaderSelection() !void {
    try std.testing.expectEqual(.source, selectLoaderForPath("/mod.py"));
    try std.testing.expectEqual(.sourceless, selectLoaderForPath("/mod.pyc"));
    try std.testing.expectEqual(.sourceless, selectLoaderForPath("/mod.pyo"));
    try std.testing.expectEqual(.extension, selectLoaderForPath("/mod.so"));
    try std.testing.expectEqual(.extension, selectLoaderForPath("/mod.pyd"));
    try std.testing.expectEqual(.extension, selectLoaderForPath("/mod.dylib"));
    try std.testing.expectEqual(.unknown, selectLoaderForPath("/mod.txt"));
}

// ============================================================================
// Zig Tests
// ============================================================================

test "SourceFileLoader init" {
    const loader = SourceFileLoader.init("test_mod", "/path/test.py");
    try std.testing.expectEqualStrings("test_mod", loader.name);
    try std.testing.expectEqualStrings("/path/test.py", loader.path);
}

test "SourceFileLoader get_filename" {
    const loader = SourceFileLoader.init("mod", "/module.py");
    try std.testing.expectEqualStrings("/module.py", loader.get_filename());
}

test "SourcelessFileLoader init" {
    const loader = SourcelessFileLoader.init("cached", "/cached.pyc");
    try std.testing.expectEqualStrings("cached", loader.name);
}

test "ExtensionFileLoader init" {
    const loader = ExtensionFileLoader.init("_ext", "/ext.so");
    try std.testing.expectEqualStrings("_ext", loader.name);
}

test "ExtensionFileLoader get_filename" {
    const loader = ExtensionFileLoader.init("ext", "/lib/ext.so");
    try std.testing.expectEqualStrings("/lib/ext.so", loader.get_filename());
}

test "MockSourceLoader basic" {
    const loader = MockSourceLoader.init("mock", "/mock.py");
    try std.testing.expectEqualStrings("mock", loader.name);
    try std.testing.expect(!loader.is_package);
}

test "MockSourceLoader with source" {
    const src = "x = 42";
    const loader = MockSourceLoader.initWithSource("x", "/x.py", src);
    try std.testing.expectEqualStrings(src, loader.getSource());
}

test "MockBytecodeLoader" {
    const loader = MockBytecodeLoader.init("bc", "/bc.pyc");
    try std.testing.expectEqualStrings("bc", loader.name);
}

test "MockExtensionLoader" {
    const loader = MockExtensionLoader.init("ext", "/ext.so");
    try std.testing.expectEqualStrings("ext", loader.name);
}

test "selectLoaderForPath" {
    try std.testing.expectEqual(.source, selectLoaderForPath("/m.py"));
    try std.testing.expectEqual(.sourceless, selectLoaderForPath("/m.pyc"));
    try std.testing.expectEqual(.extension, selectLoaderForPath("/m.so"));
    try std.testing.expectEqual(.unknown, selectLoaderForPath("/m.zip"));
}

test "Loader protocol" {
    const result = Loader.create_module(&ModuleSpec.init(std.heap.page_allocator, "x", null));
    try std.testing.expect(result == null);
}

test "FileLoader ABC" {
    const loader = abc.FileLoader.init("abc_test", "/abc.py");
    try std.testing.expectEqualStrings("abc_test", loader.name);
}
