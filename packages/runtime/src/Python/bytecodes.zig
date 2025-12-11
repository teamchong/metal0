/// bytecodes - Bytecode Definitions
/// Mirrors cpython/Python/bytecodes.c
///
/// This module defines all Python bytecode opcodes and their metadata.
/// Python 3.12+ uses a new bytecode format with 16-bit instruction words.
///
/// Module Structure:
/// - constants.zig: Opcode constants and categories
/// - metadata.zig: OpcodeInfo struct and opcode table
/// - utilities.zig: Utility functions (stack effects, jump classification, disassembly)
/// - init.zig: Module initialization and tests

const constants = @import("bytecodes/constants.zig");
const metadata = @import("bytecodes/metadata.zig");
const utilities = @import("bytecodes/utilities.zig");
const init_module = @import("bytecodes/init.zig");

// ============================================================================
// Re-export Opcode Categories
// ============================================================================

pub const OPCODE_NO_ARG = constants.OPCODE_NO_ARG;
pub const OPCODE_HAS_ARG = constants.OPCODE_HAS_ARG;
pub const OPCODE_IS_JUMP = constants.OPCODE_IS_JUMP;
pub const OPCODE_REL_JUMP = constants.OPCODE_REL_JUMP;
pub const OPCODE_HAS_LOCAL = constants.OPCODE_HAS_LOCAL;
pub const OPCODE_HAS_FREE = constants.OPCODE_HAS_FREE;
pub const OPCODE_HAS_CONST = constants.OPCODE_HAS_CONST;
pub const OPCODE_HAS_NAME = constants.OPCODE_HAS_NAME;

// ============================================================================
// Re-export Bytecode Opcodes
// ============================================================================

// Stack manipulation
pub const NOP = constants.NOP;
pub const POP_TOP = constants.POP_TOP;
pub const PUSH_NULL = constants.PUSH_NULL;
pub const END_FOR = constants.END_FOR;
pub const END_SEND = constants.END_SEND;

// Unary operations
pub const UNARY_NEGATIVE = constants.UNARY_NEGATIVE;
pub const UNARY_NOT = constants.UNARY_NOT;
pub const UNARY_INVERT = constants.UNARY_INVERT;

// Binary operations
pub const BINARY_OP = constants.BINARY_OP;
pub const BINARY_SUBSCR = constants.BINARY_SUBSCR;

// Subscript operations
pub const STORE_SUBSCR = constants.STORE_SUBSCR;
pub const DELETE_SUBSCR = constants.DELETE_SUBSCR;

// Iterators
pub const GET_ITER = constants.GET_ITER;
pub const GET_YIELD_FROM_ITER = constants.GET_YIELD_FROM_ITER;

// Print statement
pub const PRINT_EXPR = constants.PRINT_EXPR;

// Load operations
pub const LOAD_BUILD_CLASS = constants.LOAD_BUILD_CLASS;
pub const GET_AWAITABLE = constants.GET_AWAITABLE;

// Async/Await
pub const LOAD_ASSERTION_ERROR = constants.LOAD_ASSERTION_ERROR;

// Return
pub const RETURN_VALUE = constants.RETURN_VALUE;
pub const RETURN_CONST = constants.RETURN_CONST;

// Yield
pub const YIELD_VALUE = constants.YIELD_VALUE;
pub const YIELD_FROM = constants.YIELD_FROM;

// Setup
pub const SETUP_ANNOTATIONS = constants.SETUP_ANNOTATIONS;

// Async
pub const ASYNC_GEN_WRAP = constants.ASYNC_GEN_WRAP;
pub const PREP_RERAISE_STAR = constants.PREP_RERAISE_STAR;
pub const POP_EXCEPT = constants.POP_EXCEPT;

// Store/Delete
pub const STORE_NAME = constants.STORE_NAME;
pub const DELETE_NAME = constants.DELETE_NAME;
pub const UNPACK_SEQUENCE = constants.UNPACK_SEQUENCE;
pub const FOR_ITER = constants.FOR_ITER;
pub const UNPACK_EX = constants.UNPACK_EX;

// Attribute access
pub const STORE_ATTR = constants.STORE_ATTR;
pub const DELETE_ATTR = constants.DELETE_ATTR;
pub const STORE_GLOBAL = constants.STORE_GLOBAL;
pub const DELETE_GLOBAL = constants.DELETE_GLOBAL;

// Swap and Copy
pub const SWAP = constants.SWAP;
pub const LOAD_CONST = constants.LOAD_CONST;
pub const LOAD_NAME = constants.LOAD_NAME;

// Build operations
pub const BUILD_TUPLE = constants.BUILD_TUPLE;
pub const BUILD_LIST = constants.BUILD_LIST;
pub const BUILD_SET = constants.BUILD_SET;
pub const BUILD_MAP = constants.BUILD_MAP;
pub const LOAD_ATTR = constants.LOAD_ATTR;
pub const COMPARE_OP = constants.COMPARE_OP;
pub const IMPORT_NAME = constants.IMPORT_NAME;
pub const IMPORT_FROM = constants.IMPORT_FROM;

// Jump operations
pub const JUMP_FORWARD = constants.JUMP_FORWARD;
pub const JUMP_BACKWARD = constants.JUMP_BACKWARD;
pub const POP_JUMP_IF_FALSE = constants.POP_JUMP_IF_FALSE;
pub const POP_JUMP_IF_TRUE = constants.POP_JUMP_IF_TRUE;
pub const JUMP_IF_FALSE_OR_POP = constants.JUMP_IF_FALSE_OR_POP;
pub const JUMP_IF_TRUE_OR_POP = constants.JUMP_IF_TRUE_OR_POP;
pub const JUMP_BACKWARD_NO_INTERRUPT = constants.JUMP_BACKWARD_NO_INTERRUPT;

// Load globals/fast/deref
pub const LOAD_GLOBAL = constants.LOAD_GLOBAL;
pub const LOAD_FAST = constants.LOAD_FAST;
pub const STORE_FAST = constants.STORE_FAST;
pub const DELETE_FAST = constants.DELETE_FAST;
pub const LOAD_FAST_CHECK = constants.LOAD_FAST_CHECK;
pub const LOAD_FAST_AND_CLEAR = constants.LOAD_FAST_AND_CLEAR;
pub const LOAD_DEREF = constants.LOAD_DEREF;
pub const STORE_DEREF = constants.STORE_DEREF;
pub const DELETE_DEREF = constants.DELETE_DEREF;
pub const LOAD_CLASSDEREF = constants.LOAD_CLASSDEREF;

// Closures
pub const COPY_FREE_VARS = constants.COPY_FREE_VARS;
pub const MAKE_CELL = constants.MAKE_CELL;

// Exception handling
pub const RAISE_VARARGS = constants.RAISE_VARARGS;

// Call operations
pub const CALL = constants.CALL;
pub const CALL_FUNCTION_EX = constants.CALL_FUNCTION_EX;
pub const PUSH_EXC_INFO = constants.PUSH_EXC_INFO;
pub const CHECK_EXC_MATCH = constants.CHECK_EXC_MATCH;
pub const CHECK_EG_MATCH = constants.CHECK_EG_MATCH;

// Keyword arguments
pub const KW_NAMES = constants.KW_NAMES;

// Make function
pub const MAKE_FUNCTION = constants.MAKE_FUNCTION;

// Build operations continued
pub const BUILD_SLICE = constants.BUILD_SLICE;
pub const BUILD_STRING = constants.BUILD_STRING;

// Load/Store super attr
pub const LOAD_SUPER_ATTR = constants.LOAD_SUPER_ATTR;

// Match operations
pub const MATCH_CLASS = constants.MATCH_CLASS;
pub const MATCH_MAPPING = constants.MATCH_MAPPING;
pub const MATCH_SEQUENCE = constants.MATCH_SEQUENCE;
pub const MATCH_KEYS = constants.MATCH_KEYS;

// Format
pub const FORMAT_VALUE = constants.FORMAT_VALUE;

// Extended arg
pub const EXTENDED_ARG = constants.EXTENDED_ARG;

// Comprehensions
pub const LIST_APPEND = constants.LIST_APPEND;
pub const SET_ADD = constants.SET_ADD;
pub const MAP_ADD = constants.MAP_ADD;

// Context managers
pub const BEFORE_ASYNC_WITH = constants.BEFORE_ASYNC_WITH;
pub const BEFORE_WITH = constants.BEFORE_WITH;

// Annotations
pub const GET_LEN = constants.GET_LEN;
pub const GET_AITER = constants.GET_AITER;
pub const GET_ANEXT = constants.GET_ANEXT;

// Resume
pub const RESUME = constants.RESUME;

// Send
pub const SEND = constants.SEND;

// Copy
pub const COPY = constants.COPY;

// Binary op names
pub const BINARY_OP_ADD = constants.BINARY_OP_ADD;
pub const BINARY_OP_SUBTRACT = constants.BINARY_OP_SUBTRACT;
pub const BINARY_OP_MULTIPLY = constants.BINARY_OP_MULTIPLY;
pub const BINARY_OP_TRUE_DIVIDE = constants.BINARY_OP_TRUE_DIVIDE;
pub const BINARY_OP_FLOOR_DIVIDE = constants.BINARY_OP_FLOOR_DIVIDE;
pub const BINARY_OP_MODULO = constants.BINARY_OP_MODULO;
pub const BINARY_OP_POWER = constants.BINARY_OP_POWER;
pub const BINARY_OP_LSHIFT = constants.BINARY_OP_LSHIFT;
pub const BINARY_OP_RSHIFT = constants.BINARY_OP_RSHIFT;
pub const BINARY_OP_AND = constants.BINARY_OP_AND;
pub const BINARY_OP_XOR = constants.BINARY_OP_XOR;
pub const BINARY_OP_OR = constants.BINARY_OP_OR;
pub const BINARY_OP_MATMUL = constants.BINARY_OP_MATMUL;
pub const BINARY_OP_INPLACE_ADD = constants.BINARY_OP_INPLACE_ADD;
pub const BINARY_OP_INPLACE_SUBTRACT = constants.BINARY_OP_INPLACE_SUBTRACT;

// Comparison operators
pub const COMPARE_LT = constants.COMPARE_LT;
pub const COMPARE_LE = constants.COMPARE_LE;
pub const COMPARE_EQ = constants.COMPARE_EQ;
pub const COMPARE_NE = constants.COMPARE_NE;
pub const COMPARE_GT = constants.COMPARE_GT;
pub const COMPARE_GE = constants.COMPARE_GE;

// ============================================================================
// Re-export Metadata
// ============================================================================

pub const OpcodeInfo = metadata.OpcodeInfo;
pub const OPCODE_TABLE = metadata.OPCODE_TABLE;
pub const opcodeName = metadata.opcodeName;
pub const cacheEntries = metadata.cacheEntries;

// ============================================================================
// Re-export Utilities
// ============================================================================

pub const stackEffect = utilities.stackEffect;
pub const isUnconditionalJump = utilities.isUnconditionalJump;
pub const isConditionalJump = utilities.isConditionalJump;
pub const isBlockTerminator = utilities.isBlockTerminator;
pub const disassembleInstruction = utilities.disassembleInstruction;

// ============================================================================
// Re-export Initialization
// ============================================================================

pub const init = init_module.init;
pub const reset = init_module.reset;

// ============================================================================
// Re-export Tests
// ============================================================================

test {
    @import("std").testing.refAllDecls(@This());
}
