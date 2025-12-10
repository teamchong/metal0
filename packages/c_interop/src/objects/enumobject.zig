/// Enumerate and Reversed Objects Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/enumobject.c
/// enumerate() and reversed() built-in functions
///
/// Reference: cpython/Objects/enumobject.c
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// enumobject - enumerate() iterator
/// Reference: cpython/Objects/enumobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     Py_ssize_t en_index;           /* current index of enumeration */
///     PyObject* en_sit;              /* secondary iterator of enumeration */
///     PyObject* en_result;           /* result tuple */
///     PyObject* en_longindex;        /* index for sequences >= PY_SSIZE_T_MAX */
///     PyObject* one;                 /* borrowed reference */
/// } enumobject;
pub const enumobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    en_index: isize, // 8 bytes - current index
    en_sit: ?*cpython.PyObject, // 8 bytes - secondary iterator
    en_result: ?*cpython.PyObject, // 8 bytes - result tuple
    en_longindex: ?*cpython.PyObject, // 8 bytes - index for very large sequences
    one: ?*cpython.PyObject, // 8 bytes - borrowed reference to integer 1
};

// Verify enumobject size: 16 + 8 + 8 + 8 + 8 + 8 = 56 bytes
comptime {
    if (@sizeOf(enumobject) != 56) {
        @compileError("enumobject size mismatch with CPython");
    }
}

/// reversedobject - reversed() iterator
/// Reference: cpython/Objects/enumobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     Py_ssize_t index;
///     PyObject* seq;
/// } reversedobject;
pub const reversedobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    index: isize, // 8 bytes - current index (counts down)
    seq: ?*cpython.PyObject, // 8 bytes - sequence being reversed
};

// Verify reversedobject size: 16 + 8 + 8 = 32 bytes
comptime {
    if (@sizeOf(reversedobject) != 32) {
        @compileError("reversedobject size mismatch with CPython");
    }
}

// ============================================================================
// ENUMERATE TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for enumerate object
fn enum_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const en: *enumobject = @ptrCast(@alignCast(self_obj.?));

    // Decref iterator
    if (en.en_sit) |sit| {
        sit.ob_refcnt -= 1;
    }

    // Decref result tuple
    if (en.en_result) |result| {
        result.ob_refcnt -= 1;
    }

    // Decref longindex if present
    if (en.en_longindex) |longindex| {
        longindex.ob_refcnt -= 1;
    }

    // Note: en.one is a borrowed reference, don't decref

    // Free the object
    const ptr: [*]u8 = @ptrCast(en);
    allocator.free(ptr[0..@sizeOf(enumobject)]);
}

/// Traverse for enumerate object (GC)
fn enum_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const en: *enumobject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (en.en_sit) |sit| {
            const result = v(sit, arg);
            if (result != 0) return result;
        }
        if (en.en_result) |res| {
            const result = v(res, arg);
            if (result != 0) return result;
        }
        if (en.en_longindex) |idx| {
            const result = v(idx, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Iterator self-return
fn enum_iter(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    self_obj.?.ob_refcnt += 1;
    return self_obj;
}

/// Get next item from enumerate iterator
fn enum_next(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const en: *enumobject = @ptrCast(@alignCast(self_obj.?));

    // Get the underlying iterator
    const it = en.en_sit orelse return null;

    // Get type's iternext
    const tp = it.ob_type;
    const iternext = tp.tp_iternext orelse return null;

    // Get next item from underlying iterator
    const next_item = iternext(it);
    if (next_item == null) return null;

    // Check if we need to use long index
    if (en.en_index == std.math.maxInt(isize)) {
        return enum_next_long(en, next_item);
    }

    // Create index object
    const pylong = @import("longobject.zig");
    const next_index = pylong.PyLong_FromSsize_t(en.en_index);
    if (next_index == null) {
        next_item.ob_refcnt -= 1;
        return null;
    }

    // Increment index
    en.en_index += 1;

    // Try to reuse result tuple
    if (en.en_result) |result| {
        if (result.ob_refcnt == 1) {
            // We can reuse the tuple
            result.ob_refcnt += 1;

            // Get tuple items array
            const tuple = @import("tupleobject.zig");
            const old_index = tuple.PyTuple_GetItem(result, 0);
            const old_item = tuple.PyTuple_GetItem(result, 1);

            // Set new items (steals references)
            _ = tuple.PyTuple_SetItem(result, 0, next_index);
            _ = tuple.PyTuple_SetItem(result, 1, next_item);

            // Decref old items
            if (old_index) |oi| oi.ob_refcnt -= 1;
            if (old_item) |oit| oit.ob_refcnt -= 1;

            return result;
        }
    }

    // Create new tuple
    const tuple = @import("tupleobject.zig");
    const result = tuple.PyTuple_New(2);
    if (result == null) {
        next_index.ob_refcnt -= 1;
        next_item.ob_refcnt -= 1;
        return null;
    }

    _ = tuple.PyTuple_SetItem(result, 0, next_index);
    _ = tuple.PyTuple_SetItem(result, 1, next_item);

    return result;
}

/// Handle enumerate with very large indices (>= PY_SSIZE_T_MAX)
fn enum_next_long(en: *enumobject, next_item: *cpython.PyObject) ?*cpython.PyObject {
    // Get or create long index
    var next_index: ?*cpython.PyObject = en.en_longindex;
    if (next_index == null) {
        const pylong = @import("longobject.zig");
        next_index = pylong.PyLong_FromSsize_t(std.math.maxInt(isize));
        if (next_index == null) {
            next_item.ob_refcnt -= 1;
            return null;
        }
    }

    // Increment for next call
    const pylong = @import("longobject.zig");
    if (en.en_longindex) |long_idx| {
        // Using big integer index - increment via PyNumber_Add
        if (en.one) |one| {
            const object_mod = @import("object.zig");
            const new_idx = object_mod.PyNumber_Add(long_idx, one);
            if (new_idx) |ni| {
                long_idx.ob_refcnt -= 1;
                en.en_longindex = ni;
            }
        } else {
            // Fall back to creating new long from incrementing
            const val = pylong.PyLong_AsSsize_t(long_idx) + 1;
            const new_idx = pylong.PyLong_FromSsize_t(val);
            if (new_idx) |ni| {
                long_idx.ob_refcnt -= 1;
                en.en_longindex = ni;
            }
        }
    } else {
        // Using fast path with en_index
        en.en_index += 1;

        // Check for overflow and switch to long index
        if (en.en_index < 0) {
            en.en_longindex = pylong.PyLong_FromSsize_t(std.math.maxInt(isize));
            en.en_index = 0;
        }
    }

    // Create result tuple
    const tuple = @import("tupleobject.zig");
    const result = tuple.PyTuple_New(2);
    if (result == null) {
        next_item.ob_refcnt -= 1;
        return null;
    }

    next_index.?.ob_refcnt += 1; // Keep our copy
    _ = tuple.PyTuple_SetItem(result, 0, next_index.?);
    _ = tuple.PyTuple_SetItem(result, 1, next_item);

    return result;
}

/// Create new enumerate object
fn enum_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;

    if (args == null) return null;

    const tuple = @import("tupleobject.zig");
    const pylong = @import("longobject.zig");
    const pyunicode = @import("unicodeobject.zig");

    // Get iterable (required first positional arg)
    const nargs = tuple.PyTuple_Size(args.?);
    if (nargs < 1) return null;

    const iterable = tuple.PyTuple_GetItem(args.?, 0);
    if (iterable == null) return null;

    // Get start value (optional second arg or keyword arg)
    var start: isize = 0;
    var start_obj: ?*cpython.PyObject = null;

    if (nargs >= 2) {
        // Second positional arg
        const start_arg = tuple.PyTuple_GetItem(args.?, 1);
        if (start_arg) |sa| {
            if (pylong.PyLong_Check(sa) != 0) {
                start = pylong.PyLong_AsSsize_t(sa);
                // If start is large, keep as object
                if (start == -1 and pylong.PyLong_AsLongLong(sa) != -1) {
                    start_obj = sa;
                    sa.ob_refcnt += 1;
                }
            }
        }
    } else if (kwargs) |kw| {
        // Check kwargs for 'start'
        const dict = @import("dictobject.zig");
        const start_key = pyunicode.PyUnicode_FromString("start");
        if (start_key) |sk| {
            defer sk.ob_refcnt -= 1;
            const start_val = dict.PyDict_GetItem(kw, sk);
            if (start_val) |sv| {
                if (pylong.PyLong_Check(sv) != 0) {
                    start = pylong.PyLong_AsSsize_t(sv);
                }
            }
        }
    }

    // Get iterator from iterable
    const iter = PyObject_GetIter(iterable.?);
    if (iter == null) {
        if (start_obj) |so| so.ob_refcnt -= 1;
        return null;
    }

    // Allocate enumerate object
    const mem = allocator.alignedAlloc(u8, @alignOf(enumobject), @sizeOf(enumobject)) catch {
        iter.?.ob_refcnt -= 1;
        if (start_obj) |so| so.ob_refcnt -= 1;
        return null;
    };
    const en: *enumobject = @ptrCast(@alignCast(mem.ptr));

    // Create result tuple
    const result_tuple = tuple.PyTuple_New(2);
    if (result_tuple == null) {
        iter.?.ob_refcnt -= 1;
        if (start_obj) |so| so.ob_refcnt -= 1;
        allocator.free(mem);
        return null;
    }

    // Get the constant 1 for incrementing
    const one = pylong.PyLong_FromLong(1);

    // Initialize
    en.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyEnum_Type,
        },
        .en_index = start,
        .en_sit = iter,
        .en_result = result_tuple,
        .en_longindex = start_obj,
        .one = one,
    };

    return @ptrCast(en);
}

/// PyEnum_Type - the enumerate type object
pub export var PyEnum_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "enumerate",
    .tp_basicsize = @sizeOf(enumobject),
    .tp_itemsize = 0,
    .tp_dealloc = enum_dealloc,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "Return an enumerate object.\n\nThe enumerate object yields pairs containing a count (from start, which\ndefaults to zero) and a value yielded by the iterable argument.\n\nenumerate is useful for obtaining an indexed list:\n    (0, seq[0]), (1, seq[1]), (2, seq[2]), ...",
    .tp_traverse = enum_traverse,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = enum_iter,
    .tp_iternext = enum_next,
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
    .tp_new = enum_new,
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
};

// ============================================================================
// REVERSED TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for reversed object
fn reversed_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const ro: *reversedobject = @ptrCast(@alignCast(self_obj.?));

    // Decref sequence
    if (ro.seq) |seq| {
        seq.ob_refcnt -= 1;
    }

    // Free the object
    const ptr: [*]u8 = @ptrCast(ro);
    allocator.free(ptr[0..@sizeOf(reversedobject)]);
}

/// Traverse for reversed object (GC)
fn reversed_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const ro: *reversedobject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (ro.seq) |seq| {
            const result = v(seq, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Iterator self-return
fn reversed_iter(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    self_obj.?.ob_refcnt += 1;
    return self_obj;
}

/// Get next item from reversed iterator
fn reversed_next(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const ro: *reversedobject = @ptrCast(@alignCast(self_obj.?));

    const index = ro.index;
    if (index < 0) return null;

    const seq = ro.seq orelse return null;

    // Get item at current index
    const item = PySequence_GetItem(seq, index);
    if (item != null) {
        ro.index = index - 1;
        return item;
    }

    // On error, clear exception if IndexError or StopIteration
    // and mark iterator as exhausted
    ro.index = -1;
    return null;
}

/// Create new reversed object
fn reversed_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = kwargs;

    if (args == null) return null;

    // Get sequence from args
    const tuple = @import("tupleobject.zig");
    if (tuple.PyTuple_Size(args.?) != 1) return null;

    const seq = tuple.PyTuple_GetItem(args.?, 0);
    if (seq == null) return null;

    // Check if object has __reversed__ method
    const pyunicode = @import("unicodeobject.zig");
    const reversed_name = pyunicode.PyUnicode_FromString("__reversed__");
    if (reversed_name) |rn| {
        defer rn.ob_refcnt -= 1;

        // Check for __reversed__ method
        if (seq.?.ob_type.tp_getattro) |getattr_fn| {
            const method = getattr_fn(seq.?, rn);
            if (method) |m| {
                // Has __reversed__, call it
                defer m.ob_refcnt -= 1;
                const object_mod = @import("object.zig");
                return object_mod.PyObject_CallNoArgs(m);
            }
        }
    }

    // Get sequence size
    const n = PySequence_Size(seq.?);
    if (n < 0) return null;

    // Allocate reversed object
    const mem = allocator.alignedAlloc(u8, @alignOf(reversedobject), @sizeOf(reversedobject)) catch return null;
    const ro: *reversedobject = @ptrCast(@alignCast(mem.ptr));

    // Initialize
    seq.?.ob_refcnt += 1;
    ro.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyReversed_Type,
        },
        .index = n - 1,
        .seq = seq,
    };

    return @ptrCast(ro);
}

/// PyReversed_Type - the reversed type object
pub export var PyReversed_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "reversed",
    .tp_basicsize = @sizeOf(reversedobject),
    .tp_itemsize = 0,
    .tp_dealloc = reversed_dealloc,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "Return a reverse iterator over the values of the given sequence.",
    .tp_traverse = reversed_traverse,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = reversed_iter,
    .tp_iternext = reversed_next,
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
    .tp_new = reversed_new,
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
};

// ============================================================================
// HELPER FUNCTIONS (would be imported from abstract.zig)
// ============================================================================

/// Get iterator from object
fn PyObject_GetIter(obj: *cpython.PyObject) ?*cpython.PyObject {
    const tp = obj.ob_type;
    if (tp.tp_iter) |iter_fn| {
        return iter_fn(obj);
    }

    // Fall back to sequence iteration
    if (tp.tp_as_sequence) |seq_methods| {
        if (seq_methods.sq_item != null) {
            // Create a sequence iterator
            return createSeqIter(obj);
        }
    }

    return null;
}

/// Simple sequence iterator object
const SeqIterObject = extern struct {
    ob_base: cpython.PyObject,
    it_seq: ?*cpython.PyObject,
    it_index: isize,
};

fn createSeqIter(seq: *cpython.PyObject) ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(SeqIterObject), @sizeOf(SeqIterObject)) catch return null;
    const it: *SeqIterObject = @ptrCast(@alignCast(mem.ptr));

    seq.ob_refcnt += 1;
    it.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &SeqIter_Type,
        },
        .it_seq = seq,
        .it_index = 0,
    };

    return @ptrCast(it);
}

fn seqiter_next(self_obj: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    const it: *SeqIterObject = @ptrCast(@alignCast(self_obj));
    if (it.it_seq == null) return null;

    const item = PySequence_GetItem(it.it_seq.?, it.it_index);
    if (item == null) {
        // End of sequence
        it.it_seq.?.ob_refcnt -= 1;
        it.it_seq = null;
        return null;
    }

    it.it_index += 1;
    return item;
}

fn seqiter_dealloc(self_obj: *cpython.PyObject) callconv(.C) void {
    const it: *SeqIterObject = @ptrCast(@alignCast(self_obj));
    if (it.it_seq) |seq| {
        seq.ob_refcnt -= 1;
    }
    const ptr: [*]align(@alignOf(SeqIterObject)) u8 = @ptrCast(@alignCast(it));
    allocator.free(ptr[0..@sizeOf(SeqIterObject)]);
}

var SeqIter_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "iterator",
    .tp_basicsize = @sizeOf(SeqIterObject),
    .tp_itemsize = 0,
    .tp_dealloc = seqiter_dealloc,
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
    .tp_doc = null,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = seqiter_next,
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
};

/// Get sequence size
fn PySequence_Size(obj: *cpython.PyObject) isize {
    const tp = obj.ob_type;
    if (tp.tp_as_sequence) |seq_methods| {
        if (seq_methods.sq_length) |length_fn| {
            return length_fn(obj);
        }
    }
    return -1;
}

/// Get item from sequence by index
fn PySequence_GetItem(obj: *cpython.PyObject, index: isize) ?*cpython.PyObject {
    const tp = obj.ob_type;
    if (tp.tp_as_sequence) |seq_methods| {
        if (seq_methods.sq_item) |item_fn| {
            return item_fn(obj, index);
        }
    }
    return null;
}
