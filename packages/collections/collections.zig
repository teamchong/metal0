/// Collections module - Generic comptime implementations
///
/// This module exports all comptime-optimized collection implementations:
/// - dict_impl - Generic hash table
/// - list_impl - Generic dynamic array
/// - tuple_impl - Generic fixed-size array
/// - set_impl - Generic set (reuses dict_impl)
/// - buffer_impl - Generic buffer with multi-dimensional support
/// - iterator_impl - Generic iterator pattern
/// - exception_impl - Generic exception with conditional fields
/// - traceback_impl - Generic traceback
/// - numeric_impl - Generic numeric types (int/float/complex)
///
/// All implementations use comptime for zero-cost abstractions!

// Core collections
pub const dict_impl = @import("dict_impl.zig");
pub const list_impl = @import("list_impl.zig");
pub const tuple_impl = @import("tuple_impl.zig");
pub const set_impl = @import("set_impl.zig");
pub const buffer_impl = @import("buffer_impl.zig");
pub const iterator_impl = @import("iterator_impl.zig");

// Error handling
pub const exception_impl = @import("exception_impl.zig");
pub const traceback_impl = @import("traceback_impl.zig");

// Numeric types
pub const numeric_impl = @import("numeric_impl.zig");

/// Helper types for common use cases
pub const DictImpl = dict_impl.DictImpl;
pub const ListImpl = list_impl.ListImpl;
pub const TupleImpl = tuple_impl.TupleImpl;
pub const SetImpl = set_impl.SetImpl;
pub const BufferImpl = buffer_impl.BufferImpl;
pub const IteratorImpl = iterator_impl.IteratorImpl;
pub const ExceptionImpl = exception_impl.ExceptionImpl;
pub const TracebackImpl = traceback_impl.TracebackImpl;
pub const NumericImpl = numeric_impl.NumericImpl;

/// Re-export common configs from exception_impl
pub const SimpleExceptionConfig = exception_impl.SimpleExceptionConfig;
pub const OSErrorConfig = exception_impl.OSErrorConfig;
pub const SyntaxErrorConfig = exception_impl.SyntaxErrorConfig;
pub const UnicodeErrorConfig = exception_impl.UnicodeErrorConfig;
pub const ImportErrorConfig = exception_impl.ImportErrorConfig;
