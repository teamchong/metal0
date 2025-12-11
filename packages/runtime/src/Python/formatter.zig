/// metal0 Runtime Format Utilities
/// Formatting functions for Python-style printing
const std = @import("std");
const runtime = @import("../runtime.zig");

// Submodule imports
const float_format_mod = @import("formatter/float_format.zig");
const object_format_mod = @import("formatter/object_format.zig");
const format_spec_mod = @import("formatter/format_spec.zig");
const py_format_mod = @import("formatter/py_format.zig");

// ============================================================================
// Re-exports from float_format.zig
// ============================================================================
pub const FloatSignOption = float_format_mod.FloatSignOption;
pub const FloatFormatType = float_format_mod.FloatFormatType;
pub const PyFloatFormatOptions = float_format_mod.PyFloatFormatOptions;
pub const formatPythonFloat = float_format_mod.formatPythonFloat;
pub const formatFloat = float_format_mod.formatFloat;
pub const pyFloatMod = float_format_mod.pyFloatMod;
pub const pyFloatFloorDiv = float_format_mod.pyFloatFloorDiv;

// ============================================================================
// Re-exports from object_format.zig
// ============================================================================
pub const PyObject = object_format_mod.PyObject;
pub const PyString = object_format_mod.PyString;
pub const PyInt = object_format_mod.PyInt;
pub const PyFloat = object_format_mod.PyFloat;
pub const PyBool = object_format_mod.PyBool;
pub const PyDict = object_format_mod.PyDict;
pub const formatAny = object_format_mod.formatAny;
pub const formatUnknown = object_format_mod.formatUnknown;
pub const formatPyObject = object_format_mod.formatPyObject;
pub const PyDict_AsString = object_format_mod.PyDict_AsString;
pub const printValue = object_format_mod.printValue;

// ============================================================================
// Re-exports from format_spec.zig
// ============================================================================
pub const FormatSpec = format_spec_mod.FormatSpec;
pub const parseFormatSpec = format_spec_mod.parseFormatSpec;
pub const applyPadding = format_spec_mod.applyPadding;
pub const applyZeroPaddingWithGrouping = format_spec_mod.applyZeroPaddingWithGrouping;
pub const addThousandsGrouping = format_spec_mod.addThousandsGrouping;
pub const formatSignificantFigures = format_spec_mod.formatSignificantFigures;

// ============================================================================
// Re-exports from py_format.zig
// ============================================================================
pub const pyFormat = py_format_mod.pyFormat;
pub const pyMod = py_format_mod.pyMod;
pub const pyStringFormat = py_format_mod.pyStringFormat;
