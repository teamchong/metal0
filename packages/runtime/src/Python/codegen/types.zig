/// types - Core Code Generation Types
/// Mirrors cpython/Python/codegen.c type definitions
///
/// Contains compilation flags, scope types, and code object flags.

const std = @import("std");

// ============================================================================
// Compilation Flags
// ============================================================================

/// Compilation flags
pub const CompileFlags = packed struct {
    /// Optimize for speed
    optimize: bool = false,
    /// Generate code for interactive mode
    interactive: bool = false,
    /// Don't imply 'from __future__ import'
    no_future: bool = false,
    /// Use annotations as strings (PEP 563)
    annotations: bool = false,
    /// Allow top-level await
    allow_top_level_await: bool = false,
    /// In a type parameter scope
    type_params: bool = false,

    _padding: u2 = 0,
};

// ============================================================================
// Scope Types
// ============================================================================

/// Scope type
pub const ScopeType = enum(u8) {
    module,
    class,
    function,
    lambda,
    comprehension,
    annotation,
    type_parameters,
    type_alias,
    type_variable,
};

// ============================================================================
// Code Object Flags
// ============================================================================

/// Code object flags
pub const CodeFlags = packed struct {
    optimized: bool = false,
    newlocals: bool = false,
    varargs: bool = false,
    varkeywords: bool = false,
    nested: bool = false,
    generator: bool = false,
    nofree: bool = false,
    coroutine: bool = false,
    iterable_coroutine: bool = false,
    async_generator: bool = false,

    _padding: u6 = 0,
};

// ============================================================================
// Future Features
// ============================================================================

/// Future feature flags
pub const FutureFeatures = packed struct {
    division: bool = false,
    absolute_import: bool = false,
    with_statement: bool = false,
    print_function: bool = false,
    unicode_literals: bool = false,
    barry_as_FLUFL: bool = false,
    generator_stop: bool = false,
    annotations: bool = false,

    _padding: u8 = 0,
};
