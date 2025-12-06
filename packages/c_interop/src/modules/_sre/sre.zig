/// _sre/sre - Core regex types and definitions
///
/// Implements types from CPython's Modules/_sre/sre.h
/// Provides Pattern, Match, Scanner objects
///
/// Reference: cpython/Modules/_sre/sre.h
const std = @import("std");
const cpython = @import("../../include/object.zig");

pub const allocator = std.heap.c_allocator;

// ============================================================================
// CONSTANTS
// ============================================================================

/// SRE_CODE - Code word type (UCS4)
pub const SRE_CODE = u32;

/// Maximum repeat count
pub const SRE_MAXREPEAT: SRE_CODE = @as(SRE_CODE, std.math.maxInt(SRE_CODE));

/// Maximum number of groups
pub const SRE_MAXGROUPS: SRE_CODE = std.math.maxInt(i32) / 2;

// Opcodes from sre_constants.h
pub const SRE_OP_FAILURE: SRE_CODE = 0;
pub const SRE_OP_SUCCESS: SRE_CODE = 1;
pub const SRE_OP_ANY: SRE_CODE = 2;
pub const SRE_OP_ANY_ALL: SRE_CODE = 3;
pub const SRE_OP_ASSERT: SRE_CODE = 4;
pub const SRE_OP_ASSERT_NOT: SRE_CODE = 5;
pub const SRE_OP_AT: SRE_CODE = 6;
pub const SRE_OP_BRANCH: SRE_CODE = 7;
pub const SRE_OP_CALL: SRE_CODE = 8;
pub const SRE_OP_CATEGORY: SRE_CODE = 9;
pub const SRE_OP_CHARSET: SRE_CODE = 10;
pub const SRE_OP_GROUPREF: SRE_CODE = 11;
pub const SRE_OP_GROUPREF_EXISTS: SRE_CODE = 12;
pub const SRE_OP_IN: SRE_CODE = 13;
pub const SRE_OP_INFO: SRE_CODE = 14;
pub const SRE_OP_JUMP: SRE_CODE = 15;
pub const SRE_OP_LITERAL: SRE_CODE = 16;
pub const SRE_OP_MARK: SRE_CODE = 17;
pub const SRE_OP_MAX_UNTIL: SRE_CODE = 18;
pub const SRE_OP_MIN_UNTIL: SRE_CODE = 19;
pub const SRE_OP_NOT_LITERAL: SRE_CODE = 20;
pub const SRE_OP_NEGATE: SRE_CODE = 21;
pub const SRE_OP_RANGE: SRE_CODE = 22;
pub const SRE_OP_REPEAT: SRE_CODE = 23;
pub const SRE_OP_REPEAT_ONE: SRE_CODE = 24;
pub const SRE_OP_SUBPATTERN: SRE_CODE = 25;
pub const SRE_OP_MIN_REPEAT_ONE: SRE_CODE = 26;

// Flags
pub const SRE_FLAG_TEMPLATE: c_int = 1;
pub const SRE_FLAG_IGNORECASE: c_int = 2;
pub const SRE_FLAG_LOCALE: c_int = 4;
pub const SRE_FLAG_MULTILINE: c_int = 8;
pub const SRE_FLAG_DOTALL: c_int = 16;
pub const SRE_FLAG_UNICODE: c_int = 32;
pub const SRE_FLAG_VERBOSE: c_int = 64;
pub const SRE_FLAG_DEBUG: c_int = 128;
pub const SRE_FLAG_ASCII: c_int = 256;

// ============================================================================
// REPEAT CONTEXT
// ============================================================================

/// SRE_REPEAT - Repeat context for pattern matching
pub const SRE_REPEAT = extern struct {
    count: isize,
    pattern: ?[*]const SRE_CODE, // Points to REPEAT operator arguments
    last_ptr: ?*const anyopaque, // Helper to check for infinite loops
    prev: ?*SRE_REPEAT, // Points to previous repeat context
    pool_prev: ?*SRE_REPEAT, // For SRE_REPEAT pool
    pool_next: ?*SRE_REPEAT,
};

// ============================================================================
// SRE STATE
// ============================================================================

/// SRE_STATE - Matching state
pub const SRE_STATE = extern struct {
    // String pointers
    ptr: ?*const anyopaque, // Current position
    beginning: ?*const anyopaque, // Start of original string
    start: ?*const anyopaque, // Start of current slice
    end: ?*const anyopaque, // End of original string

    // Match object attributes
    string: ?*cpython.PyObject,
    buffer: cpython.Py_buffer,
    pos: isize,
    endpos: isize,
    isbytes: c_int,
    charsize: c_int, // Character size
    match_all: c_int,
    must_advance: c_int,
    debug_flag: c_int,

    // Marks
    lastmark: c_int,
    lastindex: c_int,
    mark: ?[*]?*const anyopaque,

    // Dynamic data
    data_stack: ?[*]u8,
    data_stack_size: usize,
    data_stack_base: usize,

    // Repeat context
    repeat: ?*SRE_REPEAT,
    repeat_pool_used: ?*SRE_REPEAT,
    repeat_pool_unused: ?*SRE_REPEAT,
    sigcount: c_uint,
};

// ============================================================================
// PATTERN OBJECT
// ============================================================================

/// PatternObject - Compiled regex pattern
pub const PatternObject = extern struct {
    ob_base: cpython.PyVarObject,
    groups: isize, // Must be first!
    groupindex: ?*cpython.PyObject, // Dict
    indexgroup: ?*cpython.PyObject, // Tuple
    pattern: ?*cpython.PyObject, // Pattern source (or None)
    flags: c_int, // Flags used when compiling
    weakreflist: ?*cpython.PyObject, // List of weak references
    isbytes: c_int, // Pattern type (1=bytes, 0=string, -1=None)
    codesize: isize,
    code: [1]SRE_CODE, // Pattern code (variable length)
};

// ============================================================================
// MATCH OBJECT
// ============================================================================

/// MatchObject - Match result
pub const MatchObject = extern struct {
    ob_base: cpython.PyVarObject,
    string: ?*cpython.PyObject, // Link to target string (must be first)
    regs: ?*cpython.PyObject, // Cached list of matching spans
    pattern: ?*PatternObject, // Link to pattern object
    pos: isize, // Current target slice start
    endpos: isize, // Current target slice end
    lastindex: isize, // Last index marker seen (-1 if none)
    groups: isize, // Number of groups
    mark: [1]isize, // Group marks (variable length)
};

// ============================================================================
// TEMPLATE OBJECT
// ============================================================================

/// TemplateItem - Template group/literal pair
pub const TemplateItem = extern struct {
    index: isize,
    literal: ?*cpython.PyObject, // NULL if empty
};

/// TemplateObject - Replacement template
pub const TemplateObject = extern struct {
    ob_base: cpython.PyVarObject,
    chunks: isize, // Number of group references and non-NULL literals
    literal: ?*cpython.PyObject,
    // items: [0]TemplateItem, // Variable length
};

// ============================================================================
// SCANNER OBJECT
// ============================================================================

/// ScannerObject - Pattern scanner
pub const ScannerObject = extern struct {
    ob_base: cpython.PyObject,
    pattern: ?*PatternObject,
    state: SRE_STATE,
    executing: c_int,
};

// ============================================================================
// MODULE STATE
// ============================================================================

/// sre_state - Module state
pub const sre_state = extern struct {
    Pattern_Type: ?*cpython.PyTypeObject,
    Match_Type: ?*cpython.PyTypeObject,
    Scanner_Type: ?*cpython.PyTypeObject,
    Template_Type: ?*cpython.PyTypeObject,
};

/// Global module state
pub var _sre_state: sre_state = .{
    .Pattern_Type = null,
    .Match_Type = null,
    .Scanner_Type = null,
    .Template_Type = null,
};
