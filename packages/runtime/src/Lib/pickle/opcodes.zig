//! Pickle opcodes and protocol constants

/// Pickle protocol versions
pub const HIGHEST_PROTOCOL: i64 = 5;
pub const DEFAULT_PROTOCOL: i64 = 4;

/// Pickle opcodes
pub const Opcode = struct {
    // Framing and protocol
    pub const PROTO: u8 = 0x80; // Protocol version
    pub const FRAME: u8 = 0x95; // Frame delimiter (protocol 4+)
    pub const STOP: u8 = 0x2e; // '.' - End of pickle

    // Stack manipulation
    pub const MARK: u8 = 0x28; // '(' - Push mark
    pub const POP: u8 = 0x30; // '0' - Pop top
    pub const POP_MARK: u8 = 0x31; // '1' - Pop to mark
    pub const DUP: u8 = 0x32; // '2' - Duplicate top

    // Memo operations
    pub const PUT: u8 = 0x70; // 'p' - Store in memo (ASCII index)
    pub const BINPUT: u8 = 0x71; // 'q' - Store in memo (1-byte index)
    pub const LONG_BINPUT: u8 = 0x72; // 'r' - Store in memo (4-byte index)
    pub const GET: u8 = 0x67; // 'g' - Get from memo (ASCII index)
    pub const BINGET: u8 = 0x68; // 'h' - Get from memo (1-byte index)
    pub const LONG_BINGET: u8 = 0x6a; // 'j' - Get from memo (4-byte index)
    pub const MEMOIZE: u8 = 0x94; // Store top in memo at current size

    // None/bool
    pub const NONE: u8 = 0x4e; // 'N' - Push None
    pub const NEWTRUE: u8 = 0x88; // Push True (protocol 2+)
    pub const NEWFALSE: u8 = 0x89; // Push False (protocol 2+)

    // Integers
    pub const INT: u8 = 0x49; // 'I' - Push int (ASCII, newline terminated)
    pub const BININT: u8 = 0x4a; // 'J' - Push 4-byte signed int
    pub const BININT1: u8 = 0x4b; // 'K' - Push 1-byte unsigned int
    pub const BININT2: u8 = 0x4d; // 'M' - Push 2-byte unsigned int
    pub const LONG: u8 = 0x4c; // 'L' - Push long (ASCII)
    pub const LONG1: u8 = 0x8a; // Push long < 256 bytes
    pub const LONG4: u8 = 0x8b; // Push very large long

    // Floats
    pub const FLOAT: u8 = 0x47; // 'G' - Push float (ASCII)
    pub const BINFLOAT: u8 = 0x46; // 'F' - Push 8-byte IEEE float

    // Strings
    pub const STRING: u8 = 0x53; // 'S' - Push string (quoted, newline terminated)
    pub const BINSTRING: u8 = 0x54; // 'T' - Push counted string (4-byte length)
    pub const SHORT_BINSTRING: u8 = 0x55; // 'U' - Push string < 256 bytes
    pub const UNICODE: u8 = 0x56; // 'V' - Push unicode (escaped, newline terminated)
    pub const BINUNICODE: u8 = 0x58; // 'X' - Push UTF-8 string (4-byte length)
    pub const SHORT_BINUNICODE: u8 = 0x8c; // Push UTF-8 < 256 bytes
    pub const BINUNICODE8: u8 = 0x8d; // Push very long UTF-8 (8-byte length)

    // Bytes
    pub const BINBYTES: u8 = 0x42; // 'B' - Push bytes (4-byte length)
    pub const SHORT_BINBYTES: u8 = 0x43; // 'C' - Push bytes < 256 bytes
    pub const BINBYTES8: u8 = 0x8e; // Push very long bytes (8-byte length)
    pub const BYTEARRAY8: u8 = 0x96; // Push bytearray (8-byte length)

    // Tuples
    pub const EMPTY_TUPLE: u8 = 0x29; // ')' - Push empty tuple
    pub const TUPLE: u8 = 0x74; // 't' - Build tuple from mark
    pub const TUPLE1: u8 = 0x85; // Build 1-tuple from top
    pub const TUPLE2: u8 = 0x86; // Build 2-tuple from top 2
    pub const TUPLE3: u8 = 0x87; // Build 3-tuple from top 3

    // Lists
    pub const EMPTY_LIST: u8 = 0x5d; // ']' - Push empty list
    pub const LIST: u8 = 0x6c; // 'l' - Build list from mark
    pub const APPEND: u8 = 0x61; // 'a' - Append to list
    pub const APPENDS: u8 = 0x65; // 'e' - Extend list from mark

    // Dicts
    pub const EMPTY_DICT: u8 = 0x7d; // '}' - Push empty dict
    pub const DICT: u8 = 0x64; // 'd' - Build dict from mark
    pub const SETITEM: u8 = 0x73; // 's' - Add key-value to dict
    pub const SETITEMS: u8 = 0x75; // 'u' - Add pairs from mark to dict

    // Sets
    pub const EMPTY_SET: u8 = 0x8f; // Push empty set
    pub const ADDITEMS: u8 = 0x90; // Add items to set from mark
    pub const FROZENSET: u8 = 0x91; // Build frozenset from mark

    // Objects/Classes
    pub const GLOBAL: u8 = 0x63; // 'c' - Push global (module\nname\n)
    pub const STACK_GLOBAL: u8 = 0x93; // Push global from stack
    pub const REDUCE: u8 = 0x52; // 'R' - Apply callable to args tuple
    pub const BUILD: u8 = 0x62; // 'b' - Call __setstate__
    pub const INST: u8 = 0x69; // 'i' - Build class instance
    pub const OBJ: u8 = 0x6f; // 'o' - Build object
    pub const NEWOBJ: u8 = 0x81; // Build via __new__
    pub const NEWOBJ_EX: u8 = 0x92; // Build with keyword args

    // Persistent references
    pub const PERSID: u8 = 0x50; // 'P' - Persistent id (string)
    pub const BINPERSID: u8 = 0x51; // 'Q' - Persistent id (stack)

    // Extensions
    pub const EXT1: u8 = 0x82; // Extension (1-byte code)
    pub const EXT2: u8 = 0x83; // Extension (2-byte code)
    pub const EXT4: u8 = 0x84; // Extension (4-byte code)

    // Protocol 5 out-of-band
    pub const NEXT_BUFFER: u8 = 0x97; // Push next buffer
    pub const READONLY_BUFFER: u8 = 0x98; // Make buffer readonly
};
