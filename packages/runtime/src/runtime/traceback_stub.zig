/// Traceback field stubs for AOT compilation
///
/// In CPython, traceback objects have fields like tb_next, tb_frame, tb_lineno, tb_lasti.
/// In AOT compilation, we don't have real traceback objects - the exception's __traceback__
/// field is a PyValue stub. These functions provide field access that returns appropriate
/// null/stub values for AOT compatibility.
///
/// All functions accept anytype to handle both PyValue and ?PyValue (from nested calls).
const PyValue = @import("../Objects/object.zig").PyValue;

/// Get tb_next field from a traceback PyValue
/// In AOT, tracebacks don't chain, so always returns null
/// Accepts anytype to handle nested calls like tb_next(tb_next(tb))
pub fn tb_next(_: anytype) ?PyValue {
    return null;
}

/// Get tb_frame field from a traceback PyValue
/// In AOT, we don't have real frame objects, so return null
pub fn tb_frame(_: anytype) ?PyValue {
    return null;
}

/// Get tb_lineno field from a traceback PyValue
/// In AOT, line numbers aren't tracked in tracebacks, return 0
pub fn tb_lineno(_: anytype) i64 {
    return 0;
}

/// Get tb_lasti field from a traceback PyValue
/// In AOT, last instruction index isn't tracked, return 0
pub fn tb_lasti(_: anytype) i64 {
    return 0;
}

/// Set tb_next field (no-op in AOT)
pub fn set_tb_next(_: anytype, _: anytype) void {
    // No-op - tracebacks are immutable stubs in AOT
}
