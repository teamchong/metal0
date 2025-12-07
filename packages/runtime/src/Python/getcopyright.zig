/// getcopyright - Copyright Notice
/// Mirrors cpython/Python/getcopyright.c
///
/// Returns the copyright notice for Python

const std = @import("std");

// ============================================================================
// Copyright Text
// ============================================================================

/// Python copyright notice (matches CPython format)
pub const COPYRIGHT: []const u8 =
    \\Copyright (c) 2001-2024 Python Software Foundation.
    \\All Rights Reserved.
    \\
    \\Copyright (c) 2000 BeOpen.com.
    \\All Rights Reserved.
    \\
    \\Copyright (c) 1995-2001 Corporation for National Research Initiatives.
    \\All Rights Reserved.
    \\
    \\Copyright (c) 1991-1995 Stichting Mathematisch Centrum, Amsterdam.
    \\All Rights Reserved.
;

/// Metal0 copyright notice
pub const METAL0_COPYRIGHT: []const u8 =
    \\Copyright (c) 2024 Metal0 Contributors.
    \\All Rights Reserved.
    \\
    \\Python compatibility layer based on CPython.
;

/// Combined copyright
pub const FULL_COPYRIGHT: []const u8 = METAL0_COPYRIGHT ++ "\n\n" ++ COPYRIGHT;

// ============================================================================
// Main Functions
// ============================================================================

/// Get the Python copyright string
/// This is what sys.copyright returns
pub fn getCopyright() []const u8 {
    return COPYRIGHT;
}

/// Get short copyright (first line only)
pub fn getShortCopyright() []const u8 {
    return "Copyright (c) 2001-2024 Python Software Foundation.";
}

/// Get copyright for Metal0
pub fn getMetal0Copyright() []const u8 {
    return METAL0_COPYRIGHT;
}

/// Get full combined copyright
pub fn getFullCopyright() []const u8 {
    return FULL_COPYRIGHT;
}

// ============================================================================
// License Text
// ============================================================================

/// PSF License summary
pub const PSF_LICENSE: []const u8 =
    \\PSF LICENSE AGREEMENT FOR PYTHON
    \\
    \\1. This LICENSE AGREEMENT is between the Python Software Foundation
    \\("PSF"), and the Individual or Organization ("Licensee") accessing and
    \\otherwise using Python software in source or binary form and its
    \\associated documentation.
    \\
    \\2. Subject to the terms and conditions of this License Agreement, PSF
    \\hereby grants Licensee a nonexclusive, royalty-free, world-wide license
    \\to reproduce, analyze, test, perform and/or display publicly, prepare
    \\derivative works, distribute, and otherwise use Python alone or in any
    \\derivative version, provided, however, that PSF's License Agreement and
    \\PSF's notice of copyright are retained in Python alone or in any
    \\derivative version prepared by Licensee.
;

/// Get PSF license text
pub fn getLicense() []const u8 {
    return PSF_LICENSE;
}

// ============================================================================
// Credits
// ============================================================================

/// Python credits
pub const CREDITS: []const u8 =
    \\Thanks to CWI, CNRI, BeOpen.com, Zope Corporation and a cast of thousands
    \\for supporting Python development. See www.python.org for more information.
;

/// Get credits text
pub fn getCredits() []const u8 {
    return CREDITS;
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "copyright not empty" {
    const copyright = getCopyright();
    try std.testing.expect(copyright.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, copyright, "Python Software Foundation") != null);
}

test "short copyright" {
    const short = getShortCopyright();
    try std.testing.expect(short.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, short, "Copyright") != null);
}

test "license not empty" {
    const license = getLicense();
    try std.testing.expect(license.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, license, "PSF") != null);
}

test "credits not empty" {
    const credits = getCredits();
    try std.testing.expect(credits.len > 0);
}

test "full copyright includes both" {
    const full = getFullCopyright();
    try std.testing.expect(std.mem.indexOf(u8, full, "Metal0") != null);
    try std.testing.expect(std.mem.indexOf(u8, full, "Python Software Foundation") != null);
}
