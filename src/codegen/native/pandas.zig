// ============================================================================
// DEPRECATED: Library-Specific Codegen (To Be Removed)
// ============================================================================
//
// This file generates pandas-specific code as a workaround.
//
// WHY DEPRECATED:
// - Wrong approach: Special codegen for each library doesn't scale
// - Correct approach: Fix Python compiler to handle classes/magic methods
// - Once compiler supports __getitem__, df['col'] works automatically
//
// KEEPING FOR NOW:
// - Reference while implementing core Python features
// - Will be removed after magic methods, properties, etc. work
//
// RELATED ISSUE: Need generic subscript handling, not pandas-specific
// ============================================================================

/// Pandas DataFrame code generation
/// Generates calls to c_interop/pandas.zig for DataFrame operations backed by BLAS
const std = @import("std");
const ast = @import("../../ast.zig");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

/// Generate pd.DataFrame() call
/// Creates DataFrame from dict literal: pd.DataFrame({'A': [1,2,3], 'B': [4,5,6]})
pub fn genDataFrame(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    const arg = args[0];

    // Check if it's a dict literal
    if (arg == .dict) {
        const dict = arg.dict;

        // Generate struct for fromDict
        try self.emit("try pandas.DataFrame.fromDict(.{");

        // Generate each key-value pair
        for (dict.keys, dict.values, 0..) |key_node, value_node, i| {
            if (i > 0) try self.emit(", ");

            // Extract column name from key (should be constant string)
            if (key_node == .constant and key_node.constant.value == .string) {
                const raw_name = key_node.constant.value.string;
                // Strip Python quotes from string literal
                const col_name = if (raw_name.len >= 2) raw_name[1 .. raw_name.len - 1] else raw_name;
                // Use @"name" syntax for Zig field names
                try self.emit(".@\"");
                try self.emit(col_name);
                try self.emit("\" = ");

                // Generate array literal for values
                if (value_node == .list) {
                    const elements = value_node.list.elts;

                    // Determine type from first element
                    const elem_type = if (elements.len > 0)
                        try self.type_inferrer.inferExpr(elements[0])
                    else
                        .int;

                    if (elem_type == .float) {
                        try self.emit("[_]f64{");
                    } else {
                        try self.emit("[_]i64{");
                    }

                    for (elements, 0..) |elem, j| {
                        if (j > 0) try self.emit(", ");
                        try self.genExpr(elem);
                    }

                    try self.emit("}");
                }
            }
        }

        try self.emit("}, allocator)");
    }
}

/// Generate column access: df['column_name']
/// This is handled by genSubscript in expressions/subscript.zig
/// We mark DataFrame subscripts specially for proper handling
pub fn genColumnAccess(self: *NativeCodegen, obj: ast.Node, index: ast.Node) CodegenError!void {
    // Generate: df.getColumn("column_name").?
    try self.genExpr(obj);
    try self.emit(".getColumn(");

    if (index == .string) {
        try self.emit("\"");
        try self.emit(index.string.s);
        try self.emit("\"");
    } else {
        try self.genExpr(index);
    }

    try self.emit(").?");
}

/// Generate column.sum() method call
pub fn genColumnSum(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    try self.genExpr(obj);
    try self.emit(".sum()");
}

/// Generate column.mean() method call
pub fn genColumnMean(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    try self.genExpr(obj);
    try self.emit(".mean()");
}

/// Generate column.describe() method call
/// Returns DescribeStats struct
pub fn genColumnDescribe(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    try self.emit("pandas.describe(");
    try self.genExpr(obj);
    try self.emit(")");
}

/// Generate column.min() method call
pub fn genColumnMin(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    try self.genExpr(obj);
    try self.emit(".min()");
}

/// Generate column.max() method call
pub fn genColumnMax(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    try self.genExpr(obj);
    try self.emit(".max()");
}

/// Generate column.std() method call
pub fn genColumnStd(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    try self.genExpr(obj);
    try self.emit(".stdDev()");
}
