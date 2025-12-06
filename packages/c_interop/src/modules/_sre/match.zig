/// _sre/match - Match object implementation
///
/// Implements CPython's Match object from sre.c
/// Provides match result access
///
/// Reference: cpython/Modules/_sre/sre.c
const std = @import("std");
const cpython = @import("../../include/object.zig");
const sre = @import("sre.zig");

const allocator = sre.allocator;

// ============================================================================
// MATCH METHODS
// ============================================================================

/// Match_new - Create new Match
fn Match_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;

    const base_size = @sizeOf(sre.MatchObject);
    const mem = allocator.alignedAlloc(u8, @alignOf(sre.MatchObject), base_size) catch return null;
    const match: *sre.MatchObject = @ptrCast(@alignCast(mem.ptr));

    match.* = .{
        .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = type_obj orelse &SRE_Match_Type }, .ob_size = 1 },
        .string = null,
        .regs = null,
        .pattern = null,
        .pos = 0,
        .endpos = 0,
        .lastindex = -1,
        .groups = 0,
        .mark = .{0},
    };

    return @ptrCast(match);
}

/// Match_dealloc - Destructor
fn Match_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const match: *sre.MatchObject = @ptrCast(@alignCast(self.?));

    if (match.string) |s| s.ob_refcnt -= 1;
    if (match.regs) |r| r.ob_refcnt -= 1;
    if (match.pattern) |p| {
        const p_obj: *cpython.PyObject = @ptrCast(p);
        p_obj.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(match);
    allocator.free(ptr[0..@sizeOf(sre.MatchObject)]);
}

/// Match_repr - String representation
fn Match_repr(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

/// Match_group - Return matched group(s)
fn Match_group(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    return null;
}

/// Match_groups - Return all groups
fn Match_groups(self: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    _ = kwargs;
    return null;
}

/// Match_groupdict - Return groups as dict
fn Match_groupdict(self: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    _ = kwargs;
    return null;
}

/// Match_start - Return start of match
fn Match_start(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    return null;
}

/// Match_end - Return end of match
fn Match_end(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    return null;
}

/// Match_span - Return (start, end) tuple
fn Match_span(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    return null;
}

/// Match_expand - Return replacement string
fn Match_expand(self: ?*cpython.PyObject, template: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = template;
    return null;
}

/// Match_bool - Boolean conversion (always True for successful match)
fn Match_bool(self: ?*cpython.PyObject) callconv(.c) c_int {
    if (self == null) return 0;
    return 1;
}

/// Match_getitem - Get group by index
fn Match_getitem(self: ?*cpython.PyObject, index: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or index == null) return null;
    _ = self;
    return null;
}

// ============================================================================
// GETSET
// ============================================================================

fn Match_get_string(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const match: *sre.MatchObject = @ptrCast(@alignCast(self.?));
    if (match.string) |s| {
        s.ob_refcnt += 1;
        return s;
    }
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

fn Match_get_re(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const match: *sre.MatchObject = @ptrCast(@alignCast(self.?));
    if (match.pattern) |p| {
        const p_obj: *cpython.PyObject = @ptrCast(p);
        p_obj.ob_refcnt += 1;
        return p_obj;
    }
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

fn Match_get_pos(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

fn Match_get_endpos(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

fn Match_get_lastindex(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

fn Match_get_lastgroup(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

fn Match_get_regs(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const match: *sre.MatchObject = @ptrCast(@alignCast(self.?));
    if (match.regs) |r| {
        r.ob_refcnt += 1;
        return r;
    }
    return null;
}

// ============================================================================
// AS MAPPING
// ============================================================================

pub export var Match_as_mapping: cpython.PyMappingMethods = .{
    .mp_length = null,
    .mp_subscript = Match_getitem,
    .mp_ass_subscript = null,
};

pub export var Match_as_number: cpython.PyNumberMethods = .{
    .nb_add = null,
    .nb_subtract = null,
    .nb_multiply = null,
    .nb_remainder = null,
    .nb_divmod = null,
    .nb_power = null,
    .nb_negative = null,
    .nb_positive = null,
    .nb_absolute = null,
    .nb_bool = Match_bool,
    .nb_invert = null,
    .nb_lshift = null,
    .nb_rshift = null,
    .nb_and = null,
    .nb_xor = null,
    .nb_or = null,
    .nb_int = null,
    .nb_reserved = null,
    .nb_float = null,
    .nb_inplace_add = null,
    .nb_inplace_subtract = null,
    .nb_inplace_multiply = null,
    .nb_inplace_remainder = null,
    .nb_inplace_power = null,
    .nb_inplace_lshift = null,
    .nb_inplace_rshift = null,
    .nb_inplace_and = null,
    .nb_inplace_xor = null,
    .nb_inplace_or = null,
    .nb_floor_divide = null,
    .nb_true_divide = null,
    .nb_inplace_floor_divide = null,
    .nb_inplace_true_divide = null,
    .nb_index = null,
    .nb_matrix_multiply = null,
    .nb_inplace_matrix_multiply = null,
};

// ============================================================================
// METHOD TABLE
// ============================================================================

pub export var Match_methods: [9]cpython.PyMethodDef = .{
    .{ .ml_name = "group", .ml_meth = @ptrCast(&Match_group), .ml_flags = 0x0001, .ml_doc = "Return matched group(s)." },
    .{ .ml_name = "groups", .ml_meth = @ptrCast(&Match_groups), .ml_flags = 0x0003, .ml_doc = "Return all groups." },
    .{ .ml_name = "groupdict", .ml_meth = @ptrCast(&Match_groupdict), .ml_flags = 0x0003, .ml_doc = "Return groups as dict." },
    .{ .ml_name = "start", .ml_meth = @ptrCast(&Match_start), .ml_flags = 0x0001, .ml_doc = "Return start of match." },
    .{ .ml_name = "end", .ml_meth = @ptrCast(&Match_end), .ml_flags = 0x0001, .ml_doc = "Return end of match." },
    .{ .ml_name = "span", .ml_meth = @ptrCast(&Match_span), .ml_flags = 0x0001, .ml_doc = "Return (start, end) tuple." },
    .{ .ml_name = "expand", .ml_meth = @ptrCast(&Match_expand), .ml_flags = 0x0008, .ml_doc = "Return replacement string." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var Match_getset: [8]cpython.PyGetSetDef = .{
    .{ .name = "string", .get = @ptrCast(&Match_get_string), .set = null, .doc = "Target string", .closure = null },
    .{ .name = "re", .get = @ptrCast(&Match_get_re), .set = null, .doc = "Pattern object", .closure = null },
    .{ .name = "pos", .get = @ptrCast(&Match_get_pos), .set = null, .doc = "Start position", .closure = null },
    .{ .name = "endpos", .get = @ptrCast(&Match_get_endpos), .set = null, .doc = "End position", .closure = null },
    .{ .name = "lastindex", .get = @ptrCast(&Match_get_lastindex), .set = null, .doc = "Last matched group index", .closure = null },
    .{ .name = "lastgroup", .get = @ptrCast(&Match_get_lastgroup), .set = null, .doc = "Last matched group name", .closure = null },
    .{ .name = "regs", .get = @ptrCast(&Match_get_regs), .set = null, .doc = "Match spans", .closure = null },
    .{ .name = null, .get = null, .set = null, .doc = null, .closure = null },
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub export var SRE_Match_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "re.Match",
    .tp_basicsize = @sizeOf(sre.MatchObject),
    .tp_itemsize = @sizeOf(isize),
    .tp_dealloc = Match_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = Match_repr,
    .tp_as_number = &Match_as_number,
    .tp_as_sequence = null,
    .tp_as_mapping = &Match_as_mapping,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "Regex match object.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &Match_methods,
    .tp_members = null,
    .tp_getset = &Match_getset,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = Match_new,
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
