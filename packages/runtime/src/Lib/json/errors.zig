/// JSON error types

/// JSONDecodeError - raised when JSON decoding fails
pub const JSONDecodeError = error{
    InvalidFormat,
    UnexpectedToken,
    InvalidEscape,
    InvalidNumber,
    InvalidString,
    UnterminatedString,
    TrailingComma,
    DuplicateKey,
    MaxDepthExceeded,
    OutOfMemory,
};
