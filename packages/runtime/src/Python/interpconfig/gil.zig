/// gil - GIL Configuration
/// Mirrors cpython/Python/interpconfig.c (GIL section)
///
/// Defines GIL (Global Interpreter Lock) modes for interpreters:
/// - shared: Use the main interpreter's GIL
/// - own: Use a per-interpreter GIL
/// - default: Automatically choose based on interpreter type

/// GIL sharing mode
pub const GILMode = enum(i32) {
    /// Use shared GIL (default for main interpreter)
    shared = 0,
    /// Use own GIL (for sub-interpreters)
    own = 1,
    /// Default behavior (shared for main, own for sub)
    default = -1,

    pub fn isOwn(self: GILMode) bool {
        return self == .own;
    }

    pub fn isShared(self: GILMode) bool {
        return self == .shared;
    }
};

/// How to handle extensions that don't support multiple interpreters
pub const CheckMultiInterpExtensions = enum(i32) {
    /// Default behavior
    default = -1,
    /// Allow single-phase init extensions
    low = 0,
    /// Require multi-phase init
    high = 1,
};
