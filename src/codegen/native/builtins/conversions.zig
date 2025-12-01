/// Type conversion builtins: len(), str(), int(), float(), bool()
/// This module re-exports conversion functions from submodules
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

// Import submodules
const int_conv = @import("conversions/int_conv.zig");
const float_conv = @import("conversions/float_conv.zig");
const str_conv = @import("conversions/str_conv.zig");
const type_checks = @import("conversions/type_checks.zig");
const collections = @import("conversions/collections.zig");
const misc = @import("conversions/misc.zig");

// Re-export from int_conv.zig
pub const genLen = int_conv.genLen;
pub const genInt = int_conv.genInt;
pub const genBool = int_conv.genBool;

// Re-export from float_conv.zig
pub const genFloat = float_conv.genFloat;

// Re-export from str_conv.zig
pub const genStr = str_conv.genStr;
pub const genBytes = str_conv.genBytes;
pub const genBytearray = str_conv.genBytearray;
pub const genMemoryview = str_conv.genMemoryview;
pub const genRepr = str_conv.genRepr;
pub const genAscii = str_conv.genAscii;
pub const genFormat = str_conv.genFormat;

// Re-export from type_checks.zig
pub const genType = type_checks.genType;
pub const genIsinstance = type_checks.genIsinstance;
pub const genCallable = type_checks.genCallable;
pub const genIssubclass = type_checks.genIssubclass;
pub const genId = type_checks.genId;
pub const genDelattr = type_checks.genDelattr;

// Re-export from collections.zig
pub const genList = collections.genList;
pub const genTuple = collections.genTuple;
pub const genDict = collections.genDict;
pub const genSet = collections.genSet;
pub const genFrozenset = collections.genFrozenset;

// Re-export from misc.zig
pub const genComplex = misc.genComplex;
pub const genObject = misc.genObject;
