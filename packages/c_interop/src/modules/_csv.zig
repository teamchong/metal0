/// _csv Module - CSV Parser C Accelerator
///
/// Implements CPython's Modules/_csv.c
/// Provides C implementation for CSV parsing and writing
///
/// Reference: cpython/Modules/_csv.c

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// CSV DIALECT
// ============================================================================

pub const QuoteStyle = enum(c_int) {
    QUOTE_MINIMAL = 0,
    QUOTE_ALL = 1,
    QUOTE_NONNUMERIC = 2,
    QUOTE_NONE = 3,
    QUOTE_STRINGS = 4,
    QUOTE_NOTNULL = 5,
};

/// DialectObj - CSV dialect settings
pub const DialectObj = extern struct {
    ob_base: cpython.PyObject,
    delimiter: u32, // Field delimiter (default ',')
    quotechar: u32, // Quote character (default '"')
    escapechar: u32, // Escape character (default none)
    doublequote: c_int, // Double quotes to escape (default true)
    skipinitialspace: c_int, // Skip space after delimiter
    lineterminator: ?*cpython.PyObject, // Line terminator string
    quoting: c_int, // QuoteStyle
    strict: c_int, // Raise exception on bad CSV
};

/// Create a new dialect
pub export fn _csv_Dialect_new() ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(DialectObj), @sizeOf(DialectObj)) catch return null;
    const dialect: *DialectObj = @ptrCast(@alignCast(mem.ptr));

    const pyunicode = @import("../objects/unicodeobject.zig");

    dialect.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &DialectType },
        .delimiter = ',',
        .quotechar = '"',
        .escapechar = 0,
        .doublequote = 1,
        .skipinitialspace = 0,
        .lineterminator = pyunicode.PyUnicode_FromString("\r\n"),
        .quoting = @intFromEnum(QuoteStyle.QUOTE_MINIMAL),
        .strict = 0,
    };

    return @ptrCast(dialect);
}

// ============================================================================
// CSV READER
// ============================================================================

/// ReaderObj - CSV reader
pub const ReaderObj = extern struct {
    ob_base: cpython.PyObject,
    input_iter: ?*cpython.PyObject, // Iterator over input lines
    dialect: ?*DialectObj,
    field: ?*cpython.PyObject, // Current field being built
    fields: ?*cpython.PyObject, // List of fields
    line_num: isize,
};

/// Create a new reader
pub export fn _csv_reader_new(input_iter: ?*cpython.PyObject, dialect: ?*DialectObj) ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(ReaderObj), @sizeOf(ReaderObj)) catch return null;
    const reader: *ReaderObj = @ptrCast(@alignCast(mem.ptr));

    reader.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &ReaderType },
        .input_iter = input_iter,
        .dialect = dialect,
        .field = null,
        .fields = null,
        .line_num = 0,
    };

    if (input_iter) |i| i.ob_refcnt += 1;
    if (dialect) |d| d.ob_base.ob_refcnt += 1;

    return @ptrCast(reader);
}

/// Reader iterator - get next row
fn reader_iternext(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const reader: *ReaderObj = @ptrCast(@alignCast(self_obj.?));

    // Get next line from input
    if (reader.input_iter == null) return null;

    const object_mod = @import("../objects/object.zig");
    const line = object_mod.PyIter_Next(reader.input_iter);
    if (line == null) return null;
    defer line.?.ob_refcnt -= 1;

    reader.line_num += 1;

    // Parse the line
    const pyunicode = @import("../objects/unicodeobject.zig");
    const list = @import("../objects/listobject.zig");

    const line_str = pyunicode.PyUnicode_AsUTF8(line.?) orelse return null;
    const line_len = pyunicode.PyUnicode_GetLength(line.?);

    const fields = list.PyList_New(0);
    if (fields == null) return null;

    var field_start: usize = 0;
    var in_quotes = false;
    const delimiter: u8 = if (reader.dialect) |d| @intCast(d.delimiter) else ',';
    const quotechar: u8 = if (reader.dialect) |d| @intCast(d.quotechar) else '"';

    var i: usize = 0;
    const len: usize = @intCast(line_len);
    while (i <= len) : (i += 1) {
        const c = if (i < len) line_str[i] else 0;

        if (c == quotechar and !in_quotes) {
            in_quotes = true;
            field_start = i + 1;
        } else if (c == quotechar and in_quotes) {
            in_quotes = false;
        } else if ((c == delimiter or c == 0) and !in_quotes) {
            // End of field
            const field_len = if (i > field_start) i - field_start else 0;
            const field = pyunicode.PyUnicode_FromStringAndSize(line_str + field_start, @intCast(field_len));
            if (field) |f| {
                _ = list.PyList_Append(fields, f);
                f.ob_refcnt -= 1;
            }
            field_start = i + 1;
        }
    }

    return fields;
}

// ============================================================================
// CSV WRITER
// ============================================================================

/// WriterObj - CSV writer
pub const WriterObj = extern struct {
    ob_base: cpython.PyObject,
    write: ?*cpython.PyObject, // Write method
    dialect: ?*DialectObj,
};

/// Create a new writer
pub export fn _csv_writer_new(fileobj: ?*cpython.PyObject, dialect: ?*DialectObj) ?*cpython.PyObject {
    if (fileobj == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(WriterObj), @sizeOf(WriterObj)) catch return null;
    const writer: *WriterObj = @ptrCast(@alignCast(mem.ptr));

    // Get write method from file object
    const object_mod = @import("../objects/object.zig");
    const write_method = object_mod.PyObject_GetAttrString(fileobj.?, "write");

    writer.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &WriterType },
        .write = write_method,
        .dialect = dialect,
    };

    if (dialect) |d| d.ob_base.ob_refcnt += 1;

    return @ptrCast(writer);
}

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub export var DialectType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_csv.Dialect",
    .tp_basicsize = @sizeOf(DialectObj),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_doc = "CSV dialect",
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
};

pub export var ReaderType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_csv.reader",
    .tp_basicsize = @sizeOf(ReaderObj),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_doc = "CSV reader",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = reader_iternext,
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

pub export var WriterType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_csv.writer",
    .tp_basicsize = @sizeOf(WriterObj),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_doc = "CSV writer",
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
};

// ============================================================================
// MODULE DEFINITION
// ============================================================================

pub export var _csvmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_csv",
    .m_doc = "C implementation of the csv module.",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__csv() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&_csvmodule);
}
