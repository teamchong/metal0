//! test.test_importlib.test_lazy - Tests for lazy imports
//! Reference: cpython/Lib/test/test_importlib/test_lazy.py

const std = @import("std");

pub fn LazyModule(comptime loader_fn: fn () anyerror!*Module) type {
    return struct {
        const Self = @This();
        
        _loaded: bool = false,
        _module: ?*Module = null,
        _error: ?anyerror = null,
        
        pub fn get(self: *Self) !*Module {
            if (!self._loaded) {
                self._module = loader_fn() catch |e| {
                    self._error = e;
                    self._loaded = true;
                    return e;
                };
                self._loaded = true;
            }
            if (self._error) |e| return e;
            return self._module.?;
        }
        
        pub fn is_loaded(self: *Self) bool {
            return self._loaded;
        }
    };
}

pub const Module = struct {
    __name__: []const u8,
    pub fn init(name: []const u8) @This() { return .{ .__name__ = name }; }
};

pub const LazyLoader = struct {
    const Self = @This();
    
    factory: *const fn () anyerror!*Module,
    
    pub fn init(factory: *const fn () anyerror!*Module) Self {
        return .{ .factory = factory };
    }
    
    pub fn exec_module(self: *Self, module: *Module) !void {
        const loaded = try self.factory();
        module.* = loaded.*;
    }
};

var test_module = Module.init("lazy_test");

fn lazyLoaderFn() !*Module {
    return &test_module;
}

fn testLazyModule() !void {
    var lazy = LazyModule(lazyLoaderFn){};
    
    try std.testing.expect(!lazy.is_loaded());
    
    const mod = try lazy.get();
    try std.testing.expect(lazy.is_loaded());
    try std.testing.expectEqualStrings("lazy_test", mod.__name__);
    
    // Second access should return cached
    const mod2 = try lazy.get();
    try std.testing.expectEqual(mod, mod2);
}

fn testLazyLoader() !void {
    var loader = LazyLoader.init(lazyLoaderFn);
    var mod = Module.init("to_replace");
    
    try loader.exec_module(&mod);
    try std.testing.expectEqualStrings("lazy_test", mod.__name__);
}

test "lazy_module" { try testLazyModule(); }
test "lazy_loader" { try testLazyLoader(); }
