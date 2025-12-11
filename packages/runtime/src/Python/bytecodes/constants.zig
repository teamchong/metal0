/// Opcode Constants and Categories
/// All Python bytecode opcode definitions and flag constants

// ============================================================================
// Opcode Categories
// ============================================================================

/// Opcode does not have an argument
pub const OPCODE_NO_ARG: u8 = 0;
/// Opcode has a regular argument
pub const OPCODE_HAS_ARG: u8 = 1;
/// Opcode is a jump instruction
pub const OPCODE_IS_JUMP: u8 = 2;
/// Opcode is a relative jump
pub const OPCODE_REL_JUMP: u8 = 4;
/// Opcode has a local variable argument
pub const OPCODE_HAS_LOCAL: u8 = 8;
/// Opcode has a free variable argument
pub const OPCODE_HAS_FREE: u8 = 16;
/// Opcode has a constant argument
pub const OPCODE_HAS_CONST: u8 = 32;
/// Opcode has a name argument
pub const OPCODE_HAS_NAME: u8 = 64;

// ============================================================================
// Bytecode Opcodes (Python 3.12+)
// ============================================================================

/// No operation
pub const NOP: u8 = 0;

/// Stack manipulation
pub const POP_TOP: u8 = 1;
pub const PUSH_NULL: u8 = 2;
pub const END_FOR: u8 = 4;
pub const END_SEND: u8 = 5;

/// Unary operations
pub const UNARY_NEGATIVE: u8 = 11;
pub const UNARY_NOT: u8 = 12;
pub const UNARY_INVERT: u8 = 15;

/// Binary operations (with inline cache)
pub const BINARY_OP: u8 = 22;
pub const BINARY_SUBSCR: u8 = 25;

/// Subscript operations
pub const STORE_SUBSCR: u8 = 60;
pub const DELETE_SUBSCR: u8 = 61;

/// Iterators
pub const GET_ITER: u8 = 68;
pub const GET_YIELD_FROM_ITER: u8 = 69;

/// Print statement (Python 2 compat)
pub const PRINT_EXPR: u8 = 70;

/// Load operations
pub const LOAD_BUILD_CLASS: u8 = 71;
pub const GET_AWAITABLE: u8 = 73;

/// Async/Await
pub const LOAD_ASSERTION_ERROR: u8 = 74;

/// Return
pub const RETURN_VALUE: u8 = 83;
pub const RETURN_CONST: u8 = 121;

/// Yield
pub const YIELD_VALUE: u8 = 86;
pub const YIELD_FROM: u8 = 72;

/// Setup
pub const SETUP_ANNOTATIONS: u8 = 85;

/// Async
pub const ASYNC_GEN_WRAP: u8 = 87;
pub const PREP_RERAISE_STAR: u8 = 88;
pub const POP_EXCEPT: u8 = 89;

/// Store/Delete
pub const STORE_NAME: u8 = 90;
pub const DELETE_NAME: u8 = 91;
pub const UNPACK_SEQUENCE: u8 = 92;
pub const FOR_ITER: u8 = 93;
pub const UNPACK_EX: u8 = 94;

/// Attribute access
pub const STORE_ATTR: u8 = 95;
pub const DELETE_ATTR: u8 = 96;
pub const STORE_GLOBAL: u8 = 97;
pub const DELETE_GLOBAL: u8 = 98;

/// Swap and Copy
pub const SWAP: u8 = 99;
pub const LOAD_CONST: u8 = 100;
pub const LOAD_NAME: u8 = 101;

/// Build operations
pub const BUILD_TUPLE: u8 = 102;
pub const BUILD_LIST: u8 = 103;
pub const BUILD_SET: u8 = 104;
pub const BUILD_MAP: u8 = 105;
pub const LOAD_ATTR: u8 = 106;
pub const COMPARE_OP: u8 = 107;
pub const IMPORT_NAME: u8 = 108;
pub const IMPORT_FROM: u8 = 109;

/// Jump operations
pub const JUMP_FORWARD: u8 = 110;
pub const JUMP_BACKWARD: u8 = 140;
pub const POP_JUMP_IF_FALSE: u8 = 114;
pub const POP_JUMP_IF_TRUE: u8 = 115;
pub const JUMP_IF_FALSE_OR_POP: u8 = 111;
pub const JUMP_IF_TRUE_OR_POP: u8 = 112;
pub const JUMP_BACKWARD_NO_INTERRUPT: u8 = 134;

/// Load globals/fast/deref
pub const LOAD_GLOBAL: u8 = 116;
pub const LOAD_FAST: u8 = 124;
pub const STORE_FAST: u8 = 125;
pub const DELETE_FAST: u8 = 126;
pub const LOAD_FAST_CHECK: u8 = 127;
pub const LOAD_FAST_AND_CLEAR: u8 = 128;
pub const LOAD_DEREF: u8 = 137;
pub const STORE_DEREF: u8 = 138;
pub const DELETE_DEREF: u8 = 139;
pub const LOAD_CLASSDEREF: u8 = 148;

/// Closures
pub const COPY_FREE_VARS: u8 = 149;
pub const MAKE_CELL: u8 = 135;

/// Exception handling
pub const RAISE_VARARGS: u8 = 130;

/// Call operations
pub const CALL: u8 = 171;
pub const CALL_FUNCTION_EX: u8 = 142;
pub const PUSH_EXC_INFO: u8 = 35;
pub const CHECK_EXC_MATCH: u8 = 36;
pub const CHECK_EG_MATCH: u8 = 37;

/// Keyword arguments
pub const KW_NAMES: u8 = 172;

/// Make function
pub const MAKE_FUNCTION: u8 = 132;

/// Build operations continued
pub const BUILD_SLICE: u8 = 133;
pub const BUILD_STRING: u8 = 157;

/// Load/Store super attr
pub const LOAD_SUPER_ATTR: u8 = 141;

/// Match operations (pattern matching)
pub const MATCH_CLASS: u8 = 152;
pub const MATCH_MAPPING: u8 = 153;
pub const MATCH_SEQUENCE: u8 = 154;
pub const MATCH_KEYS: u8 = 155;

/// Format
pub const FORMAT_VALUE: u8 = 155;

/// Extended arg
pub const EXTENDED_ARG: u8 = 144;

/// List/Set/Dict comprehensions
pub const LIST_APPEND: u8 = 145;
pub const SET_ADD: u8 = 146;
pub const MAP_ADD: u8 = 147;

/// Context managers
pub const BEFORE_ASYNC_WITH: u8 = 52;
pub const BEFORE_WITH: u8 = 53;

/// Annotations
pub const GET_LEN: u8 = 30;
pub const GET_AITER: u8 = 50;
pub const GET_ANEXT: u8 = 51;

/// Resume (generators)
pub const RESUME: u8 = 151;

/// Send (generators)
pub const SEND: u8 = 123;

/// Copy
pub const COPY: u8 = 120;

// ============================================================================
// Binary Operation Codes
// ============================================================================

/// Binary op names
pub const BINARY_OP_ADD: u8 = 0;
pub const BINARY_OP_SUBTRACT: u8 = 10;
pub const BINARY_OP_MULTIPLY: u8 = 5;
pub const BINARY_OP_TRUE_DIVIDE: u8 = 11;
pub const BINARY_OP_FLOOR_DIVIDE: u8 = 2;
pub const BINARY_OP_MODULO: u8 = 6;
pub const BINARY_OP_POWER: u8 = 8;
pub const BINARY_OP_LSHIFT: u8 = 3;
pub const BINARY_OP_RSHIFT: u8 = 9;
pub const BINARY_OP_AND: u8 = 1;
pub const BINARY_OP_XOR: u8 = 12;
pub const BINARY_OP_OR: u8 = 7;
pub const BINARY_OP_MATMUL: u8 = 4;
pub const BINARY_OP_INPLACE_ADD: u8 = 13;
pub const BINARY_OP_INPLACE_SUBTRACT: u8 = 23;

// ============================================================================
// Comparison Operators
// ============================================================================

/// Comparison operators
pub const COMPARE_LT: u8 = 0;
pub const COMPARE_LE: u8 = 1;
pub const COMPARE_EQ: u8 = 2;
pub const COMPARE_NE: u8 = 3;
pub const COMPARE_GT: u8 = 4;
pub const COMPARE_GE: u8 = 5;
