/// Warning Categories
/// Mirrors cpython/Python/_warnings.c - warning category definitions

const std = @import("std");

/// Built-in warning categories
pub const WarningCategory = enum {
    Warning,
    UserWarning,
    DeprecationWarning,
    PendingDeprecationWarning,
    SyntaxWarning,
    RuntimeWarning,
    FutureWarning,
    ImportWarning,
    UnicodeWarning,
    BytesWarning,
    EncodingWarning,
    ResourceWarning,

    pub fn name(self: WarningCategory) []const u8 {
        return switch (self) {
            .Warning => "Warning",
            .UserWarning => "UserWarning",
            .DeprecationWarning => "DeprecationWarning",
            .PendingDeprecationWarning => "PendingDeprecationWarning",
            .SyntaxWarning => "SyntaxWarning",
            .RuntimeWarning => "RuntimeWarning",
            .FutureWarning => "FutureWarning",
            .ImportWarning => "ImportWarning",
            .UnicodeWarning => "UnicodeWarning",
            .BytesWarning => "BytesWarning",
            .EncodingWarning => "EncodingWarning",
            .ResourceWarning => "ResourceWarning",
        };
    }

    pub fn fromString(s: []const u8) ?WarningCategory {
        const categories = [_]WarningCategory{
            .Warning,            .UserWarning,
            .DeprecationWarning, .PendingDeprecationWarning,
            .SyntaxWarning,      .RuntimeWarning,
            .FutureWarning,      .ImportWarning,
            .UnicodeWarning,     .BytesWarning,
            .EncodingWarning,    .ResourceWarning,
        };
        for (categories) |cat| {
            if (std.mem.eql(u8, s, cat.name())) {
                return cat;
            }
        }
        return null;
    }
};
