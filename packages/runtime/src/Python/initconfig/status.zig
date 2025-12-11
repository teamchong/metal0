/// Configuration Status
/// Mirrors cpython/Python/initconfig.c - configuration read status
///
/// This module defines the status codes returned by configuration operations.

/// Configuration read status
pub const ConfigStatus = enum {
    ok,
    error_init,
    error_read,
    error_validate,
    exit,
};
