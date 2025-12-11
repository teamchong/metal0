/// AST Unparse Operators
/// Operator definitions and precedence rules

const types = @import("types.zig");
const Precedence = types.Precedence;

// ============================================================================
// Operator Types
// ============================================================================

/// Binary operators
pub const BinaryOp = enum {
    add,
    sub,
    mult,
    mat_mult,
    div,
    mod,
    lshift,
    rshift,
    bit_or,
    bit_xor,
    bit_and,
    floor_div,
    pow,

    pub fn getString(self: BinaryOp) []const u8 {
        return switch (self) {
            .add => " + ",
            .sub => " - ",
            .mult => " * ",
            .mat_mult => " @ ",
            .div => " / ",
            .mod => " % ",
            .lshift => " << ",
            .rshift => " >> ",
            .bit_or => " | ",
            .bit_xor => " ^ ",
            .bit_and => " & ",
            .floor_div => " // ",
            .pow => " ** ",
        };
    }

    pub fn getPrecedence(self: BinaryOp) Precedence {
        return switch (self) {
            .add, .sub => .PR_ARITH,
            .mult, .mat_mult, .div, .mod, .floor_div => .PR_TERM,
            .lshift, .rshift => .PR_SHIFT,
            .bit_or => .PR_BOR,
            .bit_xor => .PR_BXOR,
            .bit_and => .PR_BAND,
            .pow => .PR_POWER,
        };
    }

    pub fn isRightAssoc(self: BinaryOp) bool {
        return self == .pow;
    }
};

/// Unary operators
pub const UnaryOp = enum {
    invert,
    not_op,
    uadd,
    usub,

    pub fn getString(self: UnaryOp) []const u8 {
        return switch (self) {
            .invert => "~",
            .not_op => "not ",
            .uadd => "+",
            .usub => "-",
        };
    }
};

/// Comparison operators
pub const CmpOp = enum {
    eq,
    not_eq,
    lt,
    lt_e,
    gt,
    gt_e,
    is,
    is_not,
    in_op,
    not_in,

    pub fn getString(self: CmpOp) []const u8 {
        return switch (self) {
            .eq => " == ",
            .not_eq => " != ",
            .lt => " < ",
            .lt_e => " <= ",
            .gt => " > ",
            .gt_e => " >= ",
            .is => " is ",
            .is_not => " is not ",
            .in_op => " in ",
            .not_in => " not in ",
        };
    }
};

/// Boolean operators
pub const BoolOp = enum {
    and_op,
    or_op,

    pub fn getString(self: BoolOp) []const u8 {
        return switch (self) {
            .and_op => " and ",
            .or_op => " or ",
        };
    }

    pub fn getPrecedence(self: BoolOp) Precedence {
        return switch (self) {
            .and_op => .PR_AND,
            .or_op => .PR_OR,
        };
    }
};
