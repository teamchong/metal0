//! SSL/TLS constants
//!
//! Protocol versions, verification modes, SSL options, and alert descriptions.
//! Mirrors: CPython Lib/ssl.py constants

// ============================================================================
// Protocol Constants
// ============================================================================

/// SSL/TLS protocol versions
pub const PROTOCOL_TLS = 2;
pub const PROTOCOL_TLS_CLIENT = 16;
pub const PROTOCOL_TLS_SERVER = 17;

/// Deprecated protocols (kept for compatibility)
pub const PROTOCOL_SSLv23 = PROTOCOL_TLS;

// ============================================================================
// Verification Mode Constants
// ============================================================================

/// Certificate verification modes
pub const CERT_NONE = 0;
pub const CERT_OPTIONAL = 1;
pub const CERT_REQUIRED = 2;

// ============================================================================
// SSL Options
// ============================================================================

/// SSL options (bitflags)
pub const OP_NO_SSLv2: u32 = 0x01000000;
pub const OP_NO_SSLv3: u32 = 0x02000000;
pub const OP_NO_TLSv1: u32 = 0x04000000;
pub const OP_NO_TLSv1_1: u32 = 0x10000000;
pub const OP_NO_TLSv1_2: u32 = 0x08000000;
pub const OP_NO_TLSv1_3: u32 = 0x20000000;
pub const OP_ALL: u32 = 0x80000000;

// ============================================================================
// Alert Description
// ============================================================================

pub const AlertDescription = enum(u8) {
    CLOSE_NOTIFY = 0,
    UNEXPECTED_MESSAGE = 10,
    BAD_RECORD_MAC = 20,
    RECORD_OVERFLOW = 22,
    HANDSHAKE_FAILURE = 40,
    BAD_CERTIFICATE = 42,
    UNSUPPORTED_CERTIFICATE = 43,
    CERTIFICATE_REVOKED = 44,
    CERTIFICATE_EXPIRED = 45,
    CERTIFICATE_UNKNOWN = 46,
    ILLEGAL_PARAMETER = 47,
    UNKNOWN_CA = 48,
    ACCESS_DENIED = 49,
    DECODE_ERROR = 50,
    DECRYPT_ERROR = 51,
    PROTOCOL_VERSION = 70,
    INSUFFICIENT_SECURITY = 71,
    INTERNAL_ERROR = 80,
    USER_CANCELED = 90,
    NO_RENEGOTIATION = 100,
    UNSUPPORTED_EXTENSION = 110,
    CERTIFICATE_REQUIRED = 116,
};

// ============================================================================
// Purpose - Verification purpose
// ============================================================================

/// Purpose for certificate verification
pub const Purpose = struct {
    pub const SERVER_AUTH = "1.3.6.1.5.5.7.3.1";
    pub const CLIENT_AUTH = "1.3.6.1.5.5.7.3.2";
};
