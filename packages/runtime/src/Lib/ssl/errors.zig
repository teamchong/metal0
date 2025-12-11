//! SSL/TLS error types
//!
//! Error types for SSL operations.
//! Mirrors: CPython Lib/ssl.py exceptions

pub const SSLError = error{
    SSLError,
    SSLZeroReturnError,
    SSLWantReadError,
    SSLWantWriteError,
    SSLSyscallError,
    SSLEOFError,
    CertificateError,
    NotConnected,
};

pub const CertificateError = error{
    InvalidCertificate,
    CertificateExpired,
    CertificateRevoked,
    HostnameMismatch,
    SelfSignedCertificate,
    UnknownCA,
};
