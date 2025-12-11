/// _pydecimal.constants - Decimal module constants
/// Maximum precision, exponent limits, and default values

const std = @import("std");

// ============================================================================
// Precision and Exponent Limits
// ============================================================================

/// Maximum precision (digits)
pub const MAX_PREC: u32 = 425000000;

/// Maximum exponent
pub const MAX_EMAX: i32 = 425000000;

/// Minimum exponent
pub const MIN_EMIN: i32 = -425000000;

/// Default precision (28 digits = IEEE 754 decimal128 equivalent)
pub const DEFAULT_PREC: u32 = 28;
