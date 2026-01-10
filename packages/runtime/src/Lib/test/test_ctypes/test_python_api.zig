//! test.test_ctypes.test_python_api - Tests for Python C API
//! Reference: cpython/Lib/test/test_ctypes/test_python_api.py
//!
//! Tests for ctypes integration with the Python C API.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Python Object Simulation
// ============================================================================

pub const PyObject = struct {
    const Self = @This();

    ob_refcnt: isize = 1,
    ob_type: ?*PyTypeObject = null,

    pub fn init() Self {
        return .{};
    }

    pub fn incref(self: *Self) void {
        self.ob_refcnt +|= 1;
    }

    pub fn decref(self: *Self) void {
        self.ob_refcnt -|= 1;
    }

    pub fn getRefCount(self: *const Self) isize {
        return self.ob_refcnt;
    }
};

pub const PyTypeObject = struct {
    tp_name: []const u8 = "",
    tp_basicsize: isize = 0,
    tp_flags: u64 = 0,
};

// ============================================================================
// Python API Functions
// ============================================================================

/// Py_INCREF simulation
pub fn Py_INCREF(obj: *PyObject) void {
    obj.incref();
}

/// Py_DECREF simulation
pub fn Py_DECREF(obj: *PyObject) void {
    obj.decref();
}

/// Py_XINCREF simulation (NULL-safe)
pub fn Py_XINCREF(obj: ?*PyObject) void {
    if (obj) |o| o.incref();
}

/// Py_XDECREF simulation (NULL-safe)
pub fn Py_XDECREF(obj: ?*PyObject) void {
    if (obj) |o| o.decref();
}

/// PyLong_AsLong simulation
pub fn PyLong_AsLong(value: i64) i64 {
    return value;
}

/// PyLong_FromLong simulation
pub fn PyLong_FromLong(value: i64) i64 {
    return value;
}

/// PyFloat_AsDouble simulation
pub fn PyFloat_AsDouble(value: f64) f64 {
    return value;
}

/// PyFloat_FromDouble simulation
pub fn PyFloat_FromDouble(value: f64) f64 {
    return value;
}

// ============================================================================
// Type Flags
// ============================================================================

pub const Py_TPFLAGS_DEFAULT: u64 = 0;
pub const Py_TPFLAGS_BASETYPE: u64 = 1 << 10;
pub const Py_TPFLAGS_HEAPTYPE: u64 = 1 << 9;
pub const Py_TPFLAGS_HAVE_GC: u64 = 1 << 14;

// ============================================================================
// pythonapi Simulation
// ============================================================================

pub const PythonAPI = struct {
    const Self = @This();

    loaded: bool = false,

    pub fn init() Self {
        return .{ .loaded = true };
    }

    /// Get a function pointer
    pub fn getFunction(name: []const u8) ?*anyopaque {
        _ = name;
        return null; // Mock
    }

    /// Check if API is available
    pub fn isAvailable(self: *const Self) bool {
        return self.loaded;
    }
};

pub const pythonapi = PythonAPI.init();

// ============================================================================
// py_object ctypes type
// ============================================================================

pub const py_object = struct {
    const Self = @This();

    ptr: ?*PyObject = null,

    pub fn init() Self {
        return .{};
    }

    pub fn fromPtr(p: *PyObject) Self {
        return .{ .ptr = p };
    }

    pub fn isNull(self: *const Self) bool {
        return self.ptr == null;
    }

    pub fn value(self: *const Self) ?*PyObject {
        return self.ptr;
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testPyObject() !void {
    var obj = PyObject.init();
    try std.testing.expectEqual(@as(isize, 1), obj.getRefCount());

    obj.incref();
    try std.testing.expectEqual(@as(isize, 2), obj.getRefCount());

    obj.decref();
    try std.testing.expectEqual(@as(isize, 1), obj.getRefCount());
}

fn testPyIncDecRef() !void {
    var obj = PyObject.init();

    Py_INCREF(&obj);
    try std.testing.expectEqual(@as(isize, 2), obj.getRefCount());

    Py_DECREF(&obj);
    try std.testing.expectEqual(@as(isize, 1), obj.getRefCount());
}

fn testPyXIncDecRef() !void {
    var obj = PyObject.init();

    Py_XINCREF(&obj);
    try std.testing.expectEqual(@as(isize, 2), obj.getRefCount());

    Py_XINCREF(null); // Should not crash
    try std.testing.expectEqual(@as(isize, 2), obj.getRefCount());

    Py_XDECREF(&obj);
    try std.testing.expectEqual(@as(isize, 1), obj.getRefCount());

    Py_XDECREF(null); // Should not crash
}

fn testPyLong() !void {
    try std.testing.expectEqual(@as(i64, 42), PyLong_AsLong(42));
    try std.testing.expectEqual(@as(i64, -100), PyLong_FromLong(-100));
}

fn testPyFloat() !void {
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), PyFloat_AsDouble(3.14), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.718), PyFloat_FromDouble(2.718), 0.001);
}

fn testTypeFlags() !void {
    try std.testing.expect(Py_TPFLAGS_BASETYPE != Py_TPFLAGS_HEAPTYPE);
    try std.testing.expect((Py_TPFLAGS_BASETYPE | Py_TPFLAGS_HEAPTYPE) > Py_TPFLAGS_BASETYPE);
}

fn testPythonAPI() !void {
    try std.testing.expect(pythonapi.isAvailable());
    try std.testing.expect(pythonapi.getFunction("Py_Initialize") == null); // Mock returns null
}

fn testPyObjectType() !void {
    const po = py_object.init();
    try std.testing.expect(po.isNull());

    var obj = PyObject.init();
    const po2 = py_object.fromPtr(&obj);
    try std.testing.expect(!po2.isNull());
    try std.testing.expect(po2.value() != null);
}

fn testPyTypeObject() !void {
    const tp = PyTypeObject{
        .tp_name = "MyType",
        .tp_basicsize = 24,
        .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    };

    try std.testing.expectEqualStrings("MyType", tp.tp_name);
    try std.testing.expectEqual(@as(isize, 24), tp.tp_basicsize);
}

fn testRefCountOverflow() !void {
    var obj = PyObject.init();

    // Many increfs
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        obj.incref();
    }
    try std.testing.expectEqual(@as(isize, 1001), obj.getRefCount());

    // Many decrefs
    i = 0;
    while (i < 1000) : (i += 1) {
        obj.decref();
    }
    try std.testing.expectEqual(@as(isize, 1), obj.getRefCount());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "py_object" {
    try testPyObject();
}

test "py_inc_dec_ref" {
    try testPyIncDecRef();
}

test "py_x_inc_dec_ref" {
    try testPyXIncDecRef();
}

test "py_long" {
    try testPyLong();
}

test "py_float" {
    try testPyFloat();
}

test "type_flags" {
    try testTypeFlags();
}

test "python_api" {
    try testPythonAPI();
}

test "py_object_type" {
    try testPyObjectType();
}

test "py_type_object" {
    try testPyTypeObject();
}

test "ref_count_overflow" {
    try testRefCountOverflow();
}
