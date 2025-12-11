/// types - Symbol Table Types and Constants
/// Block types, scopes, flags, and source location information.

const std = @import("std");

// ============================================================================
// Block Types
// ============================================================================

/// Type of code block
pub const BlockType = enum {
    function, // Function definition
    class, // Class definition
    module, // Module-level code
    annotation, // Annotation block (PEP 649)
    type_alias, // Type alias (PEP 695)
    type_parameters, // Generic type parameters
    type_variable, // TypeVar/TypeVarTuple/ParamSpec
};

/// Comprehension type
pub const ComprehensionType = enum(u8) {
    none = 0,
    list = 1,
    dict = 2,
    set = 3,
    generator = 4,
};

// ============================================================================
// Symbol Flags (DEF_* constants)
// ============================================================================

/// Symbol definition flags
pub const SymbolFlags = packed struct(u32) {
    global: bool = false, // global statement
    local: bool = false, // assignment in code block
    param: bool = false, // formal parameter
    nonlocal: bool = false, // nonlocal statement
    used: bool = false, // name is used
    free_class: bool = false, // free variable from class method
    imported: bool = false, // assignment via import
    annotated: bool = false, // annotated name
    comp_iter: bool = false, // comprehension iteration variable
    type_param: bool = false, // type parameter
    comp_cell: bool = false, // cell in inlined comprehension
    _padding: u21 = 0,

    pub const BOUND_MASK = SymbolFlags{
        .local = true,
        .param = true,
        .imported = true,
    };

    pub fn isBound(self: SymbolFlags) bool {
        return self.local or self.param or self.imported;
    }

    pub fn merge(self: SymbolFlags, other: SymbolFlags) SymbolFlags {
        return @bitCast(@as(u32, @bitCast(self)) | @as(u32, @bitCast(other)));
    }
};

/// Variable scope
pub const Scope = enum(u8) {
    unknown = 0,
    local = 1,
    global_explicit = 2,
    global_implicit = 3,
    free = 4,
    cell = 5,
};

// ============================================================================
// Source Location
// ============================================================================

/// Source location information
pub const SourceLocation = struct {
    lineno: i32 = -1,
    end_lineno: i32 = -1,
    col_offset: i32 = -1,
    end_col_offset: i32 = -1,

    pub const NO_LOCATION = SourceLocation{};
    pub const NEXT_LOCATION = SourceLocation{
        .lineno = -2,
        .end_lineno = -2,
        .col_offset = -2,
        .end_col_offset = -2,
    };

    pub fn isValid(self: SourceLocation) bool {
        return self.lineno >= 0;
    }
};

// ============================================================================
// Future Features
// ============================================================================

/// __future__ flags
pub const FutureFeatures = struct {
    features: u32 = 0,
    location: SourceLocation = SourceLocation.NO_LOCATION,

    // Feature flag constants
    pub const ANNOTATIONS = 1 << 0; // from __future__ import annotations
    pub const BARRY_AS_BDFL = 1 << 1; // Easter egg

    pub fn hasAnnotations(self: FutureFeatures) bool {
        return (self.features & ANNOTATIONS) != 0;
    }
};

// ============================================================================
// Error Messages (matching CPython)
// ============================================================================

pub const ErrorMessages = struct {
    pub const GLOBAL_PARAM = "name '{s}' is parameter and global";
    pub const NONLOCAL_PARAM = "name '{s}' is parameter and nonlocal";
    pub const GLOBAL_AFTER_ASSIGN = "name '{s}' is assigned to before global declaration";
    pub const NONLOCAL_AFTER_ASSIGN = "name '{s}' is assigned to before nonlocal declaration";
    pub const GLOBAL_AFTER_USE = "name '{s}' is used prior to global declaration";
    pub const NONLOCAL_AFTER_USE = "name '{s}' is used prior to nonlocal declaration";
    pub const GLOBAL_ANNOT = "annotated name '{s}' can't be global";
    pub const NONLOCAL_ANNOT = "annotated name '{s}' can't be nonlocal";
    pub const IMPORT_STAR_WARNING = "import * only allowed at module level";
    pub const DUPLICATE_PARAMETER = "duplicate argument '{s}' in function definition";
    pub const ASYNC_WITH_OUTSIDE_ASYNC = "'async with' outside async function";
    pub const ASYNC_FOR_OUTSIDE_ASYNC = "'async for' outside async function";
};

// ============================================================================
// Tests
// ============================================================================

test "symbol flags" {
    var flags = SymbolFlags{};
    flags.local = true;
    try std.testing.expect(flags.isBound());

    var flags2 = SymbolFlags{ .param = true };
    const merged = flags.merge(flags2);
    try std.testing.expect(merged.local);
    try std.testing.expect(merged.param);
}
