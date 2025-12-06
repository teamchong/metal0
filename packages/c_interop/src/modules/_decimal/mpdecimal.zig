/// _decimal/mpdecimal - Core decimal types from libmpdec
///
/// Implements types from CPython's Modules/_decimal/libmpdec/mpdecimal.h
/// Provides the mpd_t and mpd_context_t structures
///
/// Reference: cpython/Modules/_decimal/libmpdec/mpdecimal.h
const std = @import("std");
const cpython = @import("../../include/object.zig");

pub const allocator = std.heap.c_allocator;

// ============================================================================
// CONFIGURATION - 64-bit platform
// ============================================================================

pub const MPD_RADIX: u64 = 10000000000000000000; // 10**19
pub const MPD_RDIGITS: c_int = 19;
pub const MPD_MAX_PREC: i64 = 999999999999999999;
pub const MPD_ELIMIT: i64 = 1000000000000000000;
pub const MPD_MAX_EMAX: i64 = 999999999999999999;
pub const MPD_MIN_EMIN: i64 = -999999999999999999;
pub const MPD_MINALLOC_MIN: isize = 2;
pub const MPD_MINALLOC_MAX: isize = 64;

pub const mpd_uint_t = u64;
pub const mpd_ssize_t = i64;
pub const mpd_size_t = usize;

// ============================================================================
// ROUNDING MODES
// ============================================================================

pub const MPD_ROUND_UP: c_int = 0;
pub const MPD_ROUND_DOWN: c_int = 1;
pub const MPD_ROUND_CEILING: c_int = 2;
pub const MPD_ROUND_FLOOR: c_int = 3;
pub const MPD_ROUND_HALF_UP: c_int = 4;
pub const MPD_ROUND_HALF_DOWN: c_int = 5;
pub const MPD_ROUND_HALF_EVEN: c_int = 6;
pub const MPD_ROUND_05UP: c_int = 7;
pub const MPD_ROUND_TRUNC: c_int = 8;
pub const MPD_ROUND_GUARD: c_int = 9;

pub const MPD_CLAMP_DEFAULT: c_int = 0;
pub const MPD_CLAMP_IEEE_754: c_int = 1;
pub const MPD_CLAMP_GUARD: c_int = 2;

// ============================================================================
// STATUS FLAGS
// ============================================================================

pub const MPD_Clamped: u32 = 0x00000001;
pub const MPD_Conversion_syntax: u32 = 0x00000002;
pub const MPD_Division_by_zero: u32 = 0x00000004;
pub const MPD_Division_impossible: u32 = 0x00000008;
pub const MPD_Division_undefined: u32 = 0x00000010;
pub const MPD_Fpu_error: u32 = 0x00000020;
pub const MPD_Inexact: u32 = 0x00000040;
pub const MPD_Invalid_context: u32 = 0x00000080;
pub const MPD_Invalid_operation: u32 = 0x00000100;
pub const MPD_Malloc_error: u32 = 0x00000200;
pub const MPD_Not_implemented: u32 = 0x00000400;
pub const MPD_Overflow: u32 = 0x00000800;
pub const MPD_Rounded: u32 = 0x00001000;
pub const MPD_Subnormal: u32 = 0x00002000;
pub const MPD_Underflow: u32 = 0x00004000;
pub const MPD_Float_operation: u32 = 0x00008000;
pub const MPD_Max_status: u32 = 0x0000FFFF;

pub const MPD_IEEE_Invalid_operation: u32 = MPD_Conversion_syntax |
    MPD_Division_impossible | MPD_Division_undefined | MPD_Fpu_error |
    MPD_Invalid_context | MPD_Invalid_operation | MPD_Malloc_error;

pub const MPD_Errors: u32 = MPD_IEEE_Invalid_operation | MPD_Division_by_zero;
pub const MPD_Traps: u32 = MPD_IEEE_Invalid_operation | MPD_Division_by_zero |
    MPD_Overflow | MPD_Underflow;

// ============================================================================
// MPD_T FLAGS
// ============================================================================

pub const MPD_POS: u8 = 0;
pub const MPD_NEG: u8 = 1;
pub const MPD_INF: u8 = 2;
pub const MPD_NAN: u8 = 4;
pub const MPD_SNAN: u8 = 8;
pub const MPD_SPECIAL: u8 = MPD_INF | MPD_NAN | MPD_SNAN;
pub const MPD_STATIC: u8 = 16;
pub const MPD_STATIC_DATA: u8 = 32;
pub const MPD_SHARED_DATA: u8 = 64;
pub const MPD_CONST_DATA: u8 = 128;
pub const MPD_DATAFLAGS: u8 = MPD_STATIC_DATA | MPD_SHARED_DATA | MPD_CONST_DATA;

// ============================================================================
// CONTEXT STRUCTURE
// ============================================================================

/// mpd_context_t - Decimal arithmetic context
/// Matches CPython's mpd_context_t exactly
pub const mpd_context_t = extern struct {
    prec: mpd_ssize_t, // precision
    emax: mpd_ssize_t, // max positive exp
    emin: mpd_ssize_t, // min negative exp
    traps: u32, // status events that should be trapped
    status: u32, // status flags
    newtrap: u32, // set by mpd_addstatus_raise()
    round: c_int, // rounding mode
    clamp: c_int, // clamp mode
    allcr: c_int, // all functions correctly rounded
};

// ============================================================================
// MPD_T STRUCTURE - Decimal number
// ============================================================================

/// mpd_t - Decimal number
/// Matches CPython's mpd_t exactly
pub const mpd_t = extern struct {
    flags: u8,
    exp: mpd_ssize_t,
    digits: mpd_ssize_t,
    len: mpd_ssize_t,
    alloc: mpd_ssize_t,
    data: ?[*]mpd_uint_t,
};

// ============================================================================
// TRIPLE STRUCTURE - For interchange
// ============================================================================

pub const mpd_triple_class = enum(c_int) {
    MPD_TRIPLE_NORMAL = 0,
    MPD_TRIPLE_INF = 1,
    MPD_TRIPLE_QNAN = 2,
    MPD_TRIPLE_SNAN = 3,
    MPD_TRIPLE_ERROR = 4,
};

pub const mpd_uint128_triple_t = extern struct {
    tag: mpd_triple_class,
    sign: u8,
    hi: u64,
    lo: u64,
    exp: i64,
};

// ============================================================================
// FORMAT SPEC
// ============================================================================

pub const mpd_spec_t = extern struct {
    min_width: mpd_ssize_t,
    prec: mpd_ssize_t,
    type_char: u8,
    align_char: u8,
    sign: u8,
    fill: [5]u8,
    dot: ?[*:0]const u8,
    sep: ?[*:0]const u8,
    grouping: ?[*:0]const u8,
};

// ============================================================================
// CONTEXT FUNCTIONS
// ============================================================================

/// Initialize a context with default values
pub export fn mpd_init(ctx: ?*mpd_context_t, prec: mpd_ssize_t) callconv(.c) void {
    if (ctx == null) return;
    ctx.?.* = .{
        .prec = prec,
        .emax = MPD_MAX_EMAX,
        .emin = MPD_MIN_EMIN,
        .traps = MPD_Traps,
        .status = 0,
        .newtrap = 0,
        .round = MPD_ROUND_HALF_EVEN,
        .clamp = MPD_CLAMP_DEFAULT,
        .allcr = 1,
    };
}

/// Set context to maximum values
pub export fn mpd_maxcontext(ctx: ?*mpd_context_t) callconv(.c) void {
    if (ctx == null) return;
    mpd_init(ctx, MPD_MAX_PREC);
    ctx.?.traps = 0;
}

/// Set context to default values
pub export fn mpd_defaultcontext(ctx: ?*mpd_context_t) callconv(.c) void {
    if (ctx == null) return;
    mpd_init(ctx, 28);
    ctx.?.emax = 999999;
    ctx.?.emin = -999999;
}

/// Set context to basic values (for IEEE decimal)
pub export fn mpd_basiccontext(ctx: ?*mpd_context_t) callconv(.c) void {
    if (ctx == null) return;
    mpd_init(ctx, 9);
    ctx.?.traps = MPD_Traps;
    ctx.?.round = MPD_ROUND_HALF_UP;
}

// Getters
pub export fn mpd_getprec(ctx: ?*const mpd_context_t) callconv(.c) mpd_ssize_t {
    return if (ctx) |c| c.prec else 0;
}

pub export fn mpd_getemax(ctx: ?*const mpd_context_t) callconv(.c) mpd_ssize_t {
    return if (ctx) |c| c.emax else 0;
}

pub export fn mpd_getemin(ctx: ?*const mpd_context_t) callconv(.c) mpd_ssize_t {
    return if (ctx) |c| c.emin else 0;
}

pub export fn mpd_getround(ctx: ?*const mpd_context_t) callconv(.c) c_int {
    return if (ctx) |c| c.round else 0;
}

pub export fn mpd_gettraps(ctx: ?*const mpd_context_t) callconv(.c) u32 {
    return if (ctx) |c| c.traps else 0;
}

pub export fn mpd_getstatus(ctx: ?*const mpd_context_t) callconv(.c) u32 {
    return if (ctx) |c| c.status else 0;
}

pub export fn mpd_getclamp(ctx: ?*const mpd_context_t) callconv(.c) c_int {
    return if (ctx) |c| c.clamp else 0;
}

// Setters (return 0 on success, 1 on error)
pub export fn mpd_qsetprec(ctx: ?*mpd_context_t, prec: mpd_ssize_t) callconv(.c) c_int {
    if (ctx == null) return 1;
    if (prec <= 0 or prec > MPD_MAX_PREC) return 1;
    ctx.?.prec = prec;
    return 0;
}

pub export fn mpd_qsetemax(ctx: ?*mpd_context_t, emax: mpd_ssize_t) callconv(.c) c_int {
    if (ctx == null) return 1;
    if (emax < 0 or emax > MPD_MAX_EMAX) return 1;
    ctx.?.emax = emax;
    return 0;
}

pub export fn mpd_qsetemin(ctx: ?*mpd_context_t, emin: mpd_ssize_t) callconv(.c) c_int {
    if (ctx == null) return 1;
    if (emin > 0 or emin < MPD_MIN_EMIN) return 1;
    ctx.?.emin = emin;
    return 0;
}

pub export fn mpd_qsetround(ctx: ?*mpd_context_t, newround: c_int) callconv(.c) c_int {
    if (ctx == null) return 1;
    if (newround < 0 or newround >= MPD_ROUND_GUARD) return 1;
    ctx.?.round = newround;
    return 0;
}

pub export fn mpd_qsettraps(ctx: ?*mpd_context_t, flags: u32) callconv(.c) c_int {
    if (ctx == null) return 1;
    ctx.?.traps = flags;
    return 0;
}

pub export fn mpd_qsetstatus(ctx: ?*mpd_context_t, flags: u32) callconv(.c) c_int {
    if (ctx == null) return 1;
    ctx.?.status = flags;
    return 0;
}

// ============================================================================
// MPD_T FUNCTIONS
// ============================================================================

/// Check if mpd_t is negative
pub export fn mpd_isnegative(dec: ?*const mpd_t) callconv(.c) c_int {
    if (dec == null) return 0;
    return if ((dec.?.flags & MPD_NEG) != 0) 1 else 0;
}

/// Check if mpd_t is positive
pub export fn mpd_ispositive(dec: ?*const mpd_t) callconv(.c) c_int {
    if (dec == null) return 0;
    return if ((dec.?.flags & MPD_NEG) == 0) 1 else 0;
}

/// Check if mpd_t is infinite
pub export fn mpd_isinfinite(dec: ?*const mpd_t) callconv(.c) c_int {
    if (dec == null) return 0;
    return if ((dec.?.flags & MPD_INF) != 0) 1 else 0;
}

/// Check if mpd_t is NaN
pub export fn mpd_isnan(dec: ?*const mpd_t) callconv(.c) c_int {
    if (dec == null) return 0;
    return if ((dec.?.flags & (MPD_NAN | MPD_SNAN)) != 0) 1 else 0;
}

/// Check if mpd_t is quiet NaN
pub export fn mpd_isqnan(dec: ?*const mpd_t) callconv(.c) c_int {
    if (dec == null) return 0;
    return if ((dec.?.flags & MPD_NAN) != 0) 1 else 0;
}

/// Check if mpd_t is signaling NaN
pub export fn mpd_issnan(dec: ?*const mpd_t) callconv(.c) c_int {
    if (dec == null) return 0;
    return if ((dec.?.flags & MPD_SNAN) != 0) 1 else 0;
}

/// Check if mpd_t is special (Inf or NaN)
pub export fn mpd_isspecial(dec: ?*const mpd_t) callconv(.c) c_int {
    if (dec == null) return 0;
    return if ((dec.?.flags & MPD_SPECIAL) != 0) 1 else 0;
}

/// Check if mpd_t is zero
pub export fn mpd_iszero(dec: ?*const mpd_t) callconv(.c) c_int {
    if (dec == null) return 0;
    if ((dec.?.flags & MPD_SPECIAL) != 0) return 0;
    return if (dec.?.digits == 1 and dec.?.data != null and dec.?.data.?[0] == 0) 1 else 0;
}

/// Set special value
pub export fn mpd_setspecial(result: ?*mpd_t, sign: u8, type_flag: u8) callconv(.c) void {
    if (result == null) return;
    result.?.flags = (result.?.flags & ~@as(u8, MPD_NEG | MPD_SPECIAL)) | (sign | type_flag);
    result.?.exp = 0;
    result.?.digits = 0;
    result.?.len = 0;
}

/// Zero the coefficient
pub export fn mpd_zerocoeff(result: ?*mpd_t) callconv(.c) void {
    if (result == null) return;
    if (result.?.data) |data| {
        data[0] = 0;
    }
    result.?.digits = 1;
    result.?.len = 1;
}
