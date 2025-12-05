/// CPython Context API
///
/// Implements Python 3.7+ contextvars support for C extensions.
/// Context variables provide a way to have per-task state in async code.
///
/// Reference: cpython/Include/cpython/context.h

const std = @import("std");
const cpython = @import("object.zig");
const traits = @import("../objects/typetraits.zig");

const allocator = std.heap.c_allocator;

/// Context variable object
pub const PyContextVar = extern struct {
    ob_base: cpython.PyObject,
    var_name: ?*cpython.PyObject,
    var_default: ?*cpython.PyObject,
    var_cached: ?*cpython.PyObject,
    var_cached_tsid: usize,
    var_cached_tsver: usize,
};

/// Context token (returned by ContextVar.set)
pub const PyContextToken = extern struct {
    ob_base: cpython.PyObject,
    tok_used: c_int,
    tok_var: ?*PyContextVar,
    tok_oldval: ?*cpython.PyObject,
};

/// Context object
pub const PyContext = extern struct {
    ob_base: cpython.PyObject,
    ctx_vars: ?*cpython.PyObject, // dict mapping ContextVar -> value
    ctx_prev: ?*PyContext, // previous context in stack
};

// Global current context (per-thread in real implementation)
var current_context: ?*PyContext = null;

/// PyContext_Type - the 'Context' type
pub var PyContext_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "Context",
    .tp_basicsize = @sizeOf(PyContext),
    .tp_itemsize = 0,
    .tp_dealloc = context_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "Context object for contextvars",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
    .tp_watched = 0,
    .tp_versions_used = 0,
};

/// PyContextToken_Type - the 'Token' type
pub var PyContextToken_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "Token",
    .tp_basicsize = @sizeOf(PyContextToken),
    .tp_itemsize = 0,
    .tp_dealloc = contexttoken_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "Context variable token",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
    .tp_watched = 0,
    .tp_versions_used = 0,
};

/// PyContextVar_Type - the 'ContextVar' type
pub var PyContextVar_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "ContextVar",
    .tp_basicsize = @sizeOf(PyContextVar),
    .tp_itemsize = 0,
    .tp_dealloc = contextvar_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "Context variable",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
    .tp_watched = 0,
    .tp_versions_used = 0,
};

// ============================================================================
// Context API
// ============================================================================

/// Create a new empty context
export fn PyContext_New() callconv(.c) ?*cpython.PyObject {
    const ctx = allocator.create(PyContext) catch return null;

    ctx.ob_base.ob_refcnt = 1;
    ctx.ob_base.ob_type = &PyContext_Type;
    ctx.ctx_vars = PyDict_New();
    ctx.ctx_prev = null;

    if (ctx.ctx_vars == null) {
        allocator.destroy(ctx);
        return null;
    }

    return @ptrCast(&ctx.ob_base);
}

/// Copy a context
export fn PyContext_Copy(ctx: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const src: *PyContext = @ptrCast(@alignCast(ctx));
    const new_ctx = allocator.create(PyContext) catch return null;

    new_ctx.ob_base.ob_refcnt = 1;
    new_ctx.ob_base.ob_type = &PyContext_Type;
    new_ctx.ctx_prev = null;

    // Copy the vars dict
    if (src.ctx_vars) |vars| {
        new_ctx.ctx_vars = PyDict_Copy(vars);
    } else {
        new_ctx.ctx_vars = PyDict_New();
    }

    if (new_ctx.ctx_vars == null) {
        allocator.destroy(new_ctx);
        return null;
    }

    return @ptrCast(&new_ctx.ob_base);
}

/// Copy the current context
export fn PyContext_CopyCurrent() callconv(.c) ?*cpython.PyObject {
    if (current_context) |ctx| {
        return PyContext_Copy(@ptrCast(&ctx.ob_base));
    }

    // No current context, create new empty one
    return PyContext_New();
}

/// Enter a context (make it current)
/// Returns 0 on success, -1 on error
export fn PyContext_Enter(ctx: *cpython.PyObject) callconv(.c) c_int {
    const context: *PyContext = @ptrCast(@alignCast(ctx));

    // Save previous context
    context.ctx_prev = current_context;
    current_context = context;

    // Increment refcount
    _ = traits.incref(ctx);

    return 0;
}

/// Exit a context (restore previous)
/// Returns 0 on success, -1 on error
export fn PyContext_Exit(ctx: *cpython.PyObject) callconv(.c) c_int {
    const context: *PyContext = @ptrCast(@alignCast(ctx));

    if (current_context != context) {
        traits.setError("RuntimeError", "Context was not entered");
        return -1;
    }

    // Restore previous context
    current_context = context.ctx_prev;
    context.ctx_prev = null;

    // Decrement refcount
    traits.decref(ctx);

    return 0;
}

// ============================================================================
// ContextVar API
// ============================================================================

/// Create a new context variable
export fn PyContextVar_New(name: [*:0]const u8, default_value: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const var_obj = allocator.create(PyContextVar) catch return null;

    var_obj.ob_base.ob_refcnt = 1;
    var_obj.ob_base.ob_type = &PyContextVar_Type;
    var_obj.var_name = PyUnicode_FromString(name);
    var_obj.var_default = if (default_value) |v| traits.incref(v) else null;
    var_obj.var_cached = null;
    var_obj.var_cached_tsid = 0;
    var_obj.var_cached_tsver = 0;

    return @ptrCast(&var_obj.ob_base);
}

/// Get value of context variable
/// Returns 0 on success with value in *val, -1 on error
/// If not set and no default, sets LookupError
export fn PyContextVar_Get(var_obj: *cpython.PyObject, default_value: ?*cpython.PyObject, val: *?*cpython.PyObject) callconv(.c) c_int {
    const cv: *PyContextVar = @ptrCast(@alignCast(var_obj));

    // Check current context
    if (current_context) |ctx| {
        if (ctx.ctx_vars) |vars| {
            const result = PyDict_GetItem(vars, var_obj);
            if (result) |v| {
                val.* = traits.incref(v);
                return 0;
            }
        }
    }

    // Not found in context, try default
    if (default_value) |def| {
        val.* = traits.incref(def);
        return 0;
    }

    if (cv.var_default) |def| {
        val.* = traits.incref(def);
        return 0;
    }

    // No value and no default
    traits.setError("LookupError", "ContextVar has no value");
    val.* = null;
    return -1;
}

/// Set value of context variable
/// Returns token that can be used to reset, or null on error
export fn PyContextVar_Set(var_obj: *cpython.PyObject, value: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Ensure we have a current context
    if (current_context == null) {
        const ctx = PyContext_New();
        if (ctx == null) return null;
        _ = PyContext_Enter(ctx.?);
    }

    const ctx = current_context.?;

    // Create token
    const token = allocator.create(PyContextToken) catch return null;
    token.ob_base.ob_refcnt = 1;
    token.ob_base.ob_type = &PyContextToken_Type;
    token.tok_used = 0;
    token.tok_var = @ptrCast(@alignCast(traits.incref(var_obj)));

    // Save old value
    if (ctx.ctx_vars) |vars| {
        token.tok_oldval = PyDict_GetItem(vars, var_obj);
        if (token.tok_oldval) |old| {
            _ = traits.incref(old);
        }

        // Set new value
        _ = PyDict_SetItem(vars, var_obj, value);
    } else {
        token.tok_oldval = null;
    }

    return @ptrCast(&token.ob_base);
}

/// Reset context variable to previous value using token
/// Returns 0 on success, -1 on error
export fn PyContextVar_Reset(var_obj: *cpython.PyObject, token: *cpython.PyObject) callconv(.c) c_int {
    _ = var_obj;
    const tok: *PyContextToken = @ptrCast(@alignCast(token));

    if (tok.tok_used != 0) {
        traits.setError("RuntimeError", "Token has already been used");
        return -1;
    }

    tok.tok_used = 1;

    if (current_context) |ctx| {
        if (ctx.ctx_vars) |vars| {
            if (tok.tok_oldval) |old| {
                if (tok.tok_var) |cv| {
                    _ = PyDict_SetItem(vars, @ptrCast(&cv.ob_base), old);
                }
            } else {
                // No old value - delete from context
                if (tok.tok_var) |cv| {
                    _ = PyDict_DelItem(vars, @ptrCast(&cv.ob_base));
                }
            }
        }
    }

    return 0;
}

// ============================================================================
// Internal functions
// ============================================================================

fn context_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const ctx: *PyContext = @ptrCast(@alignCast(obj));

    if (ctx.ctx_vars) |vars| {
        traits.decref(vars);
    }

    allocator.destroy(ctx);
}

fn contextvar_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const cv: *PyContextVar = @ptrCast(@alignCast(obj));

    if (cv.var_name) |name| {
        traits.decref(name);
    }
    if (cv.var_default) |def| {
        traits.decref(def);
    }

    allocator.destroy(cv);
}

fn contexttoken_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const tok: *PyContextToken = @ptrCast(@alignCast(obj));

    if (tok.tok_var) |cv| {
        traits.decref(@ptrCast(&cv.ob_base));
    }
    if (tok.tok_oldval) |old| {
        traits.decref(old);
    }

    allocator.destroy(tok);
}

// Pure Zig implementations (NO extern declarations - use traits.externs)
const PyDict_New = traits.externs.PyDict_New;
const PyDict_Copy = traits.externs.PyDict_Copy;
const PyDict_GetItem = traits.externs.PyDict_GetItem;
const PyDict_SetItem = traits.externs.PyDict_SetItem;
const PyDict_DelItem = traits.externs.PyDict_DelItem;
const PyUnicode_FromString = traits.externs.PyUnicode_FromString;

// Tests
test "context exports" {
    _ = PyContext_New;
    _ = PyContext_Enter;
    _ = PyContext_Exit;
    _ = PyContextVar_New;
    _ = PyContextVar_Get;
    _ = PyContextVar_Set;
}
