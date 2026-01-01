/// PyObject casting utilities - DRY helpers for type-safe casting
/// Eliminates repeated @ptrCast(@alignCast(obj)) patterns

/// Cast PyObject to a specific CPython type
/// Usage: const long_obj = cast(PyLongObject, obj);
pub inline fn cast(comptime T: type, obj: anytype) *T {
    return @ptrCast(@alignCast(obj));
}

/// Cast PyObject to a specific CPython type (const version)
/// Usage: const long_obj = castConst(PyLongObject, obj);
pub inline fn castConst(comptime T: type, obj: anytype) *const T {
    return @ptrCast(@alignCast(obj));
}

/// Cast and get value for simple numeric types
/// Returns the numeric value directly
pub inline fn getLongValue(obj: anytype, comptime PyLongObject: type) i64 {
    const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
    return long_obj.getValue();
}

pub inline fn getFloatValue(obj: anytype, comptime PyFloatObject: type) f64 {
    const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
    return float_obj.ob_fval;
}

pub inline fn getBoolValue(obj: anytype, comptime PyBoolObject: type) bool {
    const bool_obj: *PyBoolObject = @ptrCast(@alignCast(obj));
    return bool_obj.getValue();
}

/// Get size/length for container types
pub inline fn getListSize(obj: anytype, comptime PyListObject: type) isize {
    const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
    return list_obj.ob_base.ob_size;
}

pub inline fn getTupleSize(obj: anytype, comptime PyTupleObject: type) isize {
    const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
    return tuple_obj.ob_base.ob_size;
}

pub inline fn getDictUsed(obj: anytype, comptime PyDictObject: type) isize {
    const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));
    return dict_obj.ma_used;
}

pub inline fn getStringLength(obj: anytype, comptime PyUnicodeObject: type) isize {
    const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
    return str_obj.length;
}
