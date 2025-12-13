//! test.pickletester - CPython pickle test utilities
//! Provides helpers for testing pickle-related functionality
const std = @import("std");

/// ExtensionSaver - Context manager for saving/restoring extension registry
/// Used by copyreg tests to temporarily modify the extension registry
pub const ExtensionSaver = struct {
    // Saved state (module, name, code) tuple
    saved_module: ?[]const u8,
    saved_name: ?[]const u8,
    saved_code: i32,

    /// Create a new ExtensionSaver
    pub fn init(code: i32) ExtensionSaver {
        return .{
            .saved_module = null,
            .saved_name = null,
            .saved_code = code,
        };
    }

    /// Context manager __enter__ - saves current state and returns self
    pub fn __enter__(self: *ExtensionSaver) *ExtensionSaver {
        // Save current extension registry state (stub - no actual registry)
        _ = self;
        return self;
    }

    /// Context manager __exit__ - restores saved state
    pub fn __exit__(
        self: *ExtensionSaver,
        exc_type: anytype,
        exc_val: anytype,
        exc_tb: anytype,
    ) void {
        _ = exc_type;
        _ = exc_val;
        _ = exc_tb;
        // Restore extension registry state (stub - no actual registry)
        _ = self;
    }
};

/// AbstractPickleTests - Base class for pickle test cases (stub)
pub const AbstractPickleTests = struct {
    pub fn init() AbstractPickleTests {
        return .{};
    }
};

/// AbstractPickleModuleTests - Base class for pickle module tests (stub)
pub const AbstractPickleModuleTests = struct {
    pub fn init() AbstractPickleModuleTests {
        return .{};
    }
};

/// AbstractPersistentPicklerTests - Base class for persistent pickler tests (stub)
pub const AbstractPersistentPicklerTests = struct {
    pub fn init() AbstractPersistentPicklerTests {
        return .{};
    }
};

/// AbstractIdentityPersistentPicklerTests - Base class for identity persistent pickler tests (stub)
pub const AbstractIdentityPersistentPicklerTests = struct {
    pub fn init() AbstractIdentityPersistentPicklerTests {
        return .{};
    }
};

/// AbstractPicklerUnpicklerObjectTests - Base class for pickler/unpickler object tests (stub)
pub const AbstractPicklerUnpicklerObjectTests = struct {
    pub fn init() AbstractPicklerUnpicklerObjectTests {
        return .{};
    }
};

/// BigmemPickleTests - Base class for big memory pickle tests (stub)
pub const BigmemPickleTests = struct {
    pub fn init() BigmemPickleTests {
        return .{};
    }
};
