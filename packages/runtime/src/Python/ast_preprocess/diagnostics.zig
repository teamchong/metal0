/// Warnings and Errors
/// Diagnostic message types for AST preprocessing

/// Warning kinds
pub const WarningKind = enum {
    return_in_finally,
    break_in_finally,
    continue_in_finally,
    deprecated_syntax,
    other,
};

/// Warning message
pub const Warning = struct {
    kind: WarningKind,
    lineno: u32,
    col_offset: u32,
    filename: []const u8,

    pub fn getMessage(self: *const Warning) []const u8 {
        return switch (self.kind) {
            .return_in_finally => "'return' in a 'finally' block",
            .break_in_finally => "'break' in a 'finally' block",
            .continue_in_finally => "'continue' in a 'finally' block",
            .deprecated_syntax => "deprecated syntax",
            .other => "warning",
        };
    }
};

/// Error kinds
pub const ErrorKind = enum {
    syntax_error,
    indentation_error,
    tab_error,
    invalid_escape,
    optimization_failed,
};

/// Preprocessing error
pub const PreprocessError = struct {
    kind: ErrorKind,
    message: []const u8,
    lineno: u32,
    col_offset: u32,
    filename: []const u8,
};
