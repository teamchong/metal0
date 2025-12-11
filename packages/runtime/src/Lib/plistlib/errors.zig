//! Error types for plist parsing and serialization

pub const InvalidFileException = error{
    InvalidFormat,
    InvalidHeader,
    CorruptedData,
    UnsupportedVersion,
};
