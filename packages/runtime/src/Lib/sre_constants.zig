/// Secret Labs' Regular Expression Engine constants
/// Various symbols used by the regular expression engine
/// Ported from CPython Lib/re/_constants.py

pub const MAGIC: u32 = 20230612;

// From _sre module (would be imported from C extension)
pub const MAXREPEAT: u32 = 4294967295; // 2^32 - 1
pub const MAXGROUPS: u32 = 2147483647; // 2^31 - 1

// Opcodes - using enum for type safety and DCE
pub const Opcode = enum(u8) {
    // failure=0 success=1
    FAILURE = 0,
    SUCCESS = 1,

    ANY = 2,
    ANY_ALL = 3,
    ASSERT = 4,
    ASSERT_NOT = 5,
    AT = 6,
    BRANCH = 7,
    CATEGORY = 8,
    CHARSET = 9,
    BIGCHARSET = 10,
    GROUPREF = 11,
    GROUPREF_EXISTS = 12,
    IN = 13,
    INFO = 14,
    JUMP = 15,
    LITERAL = 16,
    MARK = 17,
    MAX_UNTIL = 18,
    MIN_UNTIL = 19,
    NOT_LITERAL = 20,
    NEGATE = 21,
    RANGE = 22,
    REPEAT = 23,
    REPEAT_ONE = 24,
    SUBPATTERN = 25,
    MIN_REPEAT_ONE = 26,
    ATOMIC_GROUP = 27,
    POSSESSIVE_REPEAT = 28,
    POSSESSIVE_REPEAT_ONE = 29,

    GROUPREF_IGNORE = 30,
    IN_IGNORE = 31,
    LITERAL_IGNORE = 32,
    NOT_LITERAL_IGNORE = 33,

    GROUPREF_LOC_IGNORE = 34,
    IN_LOC_IGNORE = 35,
    LITERAL_LOC_IGNORE = 36,
    NOT_LITERAL_LOC_IGNORE = 37,

    GROUPREF_UNI_IGNORE = 38,
    IN_UNI_IGNORE = 39,
    LITERAL_UNI_IGNORE = 40,
    NOT_LITERAL_UNI_IGNORE = 41,
    RANGE_UNI_IGNORE = 42,
};

// Position codes
pub const AtCode = enum(u8) {
    AT_BEGINNING = 0,
    AT_BEGINNING_LINE = 1,
    AT_BEGINNING_STRING = 2,
    AT_BOUNDARY = 3,
    AT_NON_BOUNDARY = 4,
    AT_END = 5,
    AT_END_LINE = 6,
    AT_END_STRING = 7,

    AT_LOC_BOUNDARY = 8,
    AT_LOC_NON_BOUNDARY = 9,

    AT_UNI_BOUNDARY = 10,
    AT_UNI_NON_BOUNDARY = 11,
};

// Category codes
pub const ChCode = enum(u8) {
    CATEGORY_DIGIT = 0,
    CATEGORY_NOT_DIGIT = 1,
    CATEGORY_SPACE = 2,
    CATEGORY_NOT_SPACE = 3,
    CATEGORY_WORD = 4,
    CATEGORY_NOT_WORD = 5,
    CATEGORY_LINEBREAK = 6,
    CATEGORY_NOT_LINEBREAK = 7,

    CATEGORY_LOC_WORD = 8,
    CATEGORY_LOC_NOT_WORD = 9,

    CATEGORY_UNI_DIGIT = 10,
    CATEGORY_UNI_NOT_DIGIT = 11,
    CATEGORY_UNI_SPACE = 12,
    CATEGORY_UNI_NOT_SPACE = 13,
    CATEGORY_UNI_WORD = 14,
    CATEGORY_UNI_NOT_WORD = 15,
    CATEGORY_UNI_LINEBREAK = 16,
    CATEGORY_UNI_NOT_LINEBREAK = 17,
};

// Flags
pub const SRE_FLAG_IGNORECASE: u32 = 2; // case insensitive
pub const SRE_FLAG_LOCALE: u32 = 4; // honour system locale
pub const SRE_FLAG_MULTILINE: u32 = 8; // treat target as multiline string
pub const SRE_FLAG_DOTALL: u32 = 16; // treat target as a single string
pub const SRE_FLAG_UNICODE: u32 = 32; // use unicode "locale"
pub const SRE_FLAG_VERBOSE: u32 = 64; // ignore whitespace and comments
pub const SRE_FLAG_DEBUG: u32 = 128; // debugging
pub const SRE_FLAG_ASCII: u32 = 256; // use ascii "locale"

// Flags for INFO primitive
pub const SRE_INFO_PREFIX: u32 = 1; // has prefix
pub const SRE_INFO_LITERAL: u32 = 2; // entire pattern is literal
pub const SRE_INFO_CHARSET: u32 = 4; // pattern starts with character from given set

// DCE-friendly: All constants are compile-time known, unused ones will be eliminated
// Enums provide type safety and better codegen than raw integers
