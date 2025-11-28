/// Python symtable module - Symbol table access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Main Functions
// ============================================================================

/// Generate symtable.symtable(code, filename, compile_type)
pub fn genSymtable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"<module>\", .type = \"module\", .lineno = 1, .is_optimized = false, .is_nested = false, .has_children = false, .has_exec = false, .has_import_star = false, .has_varargs = false, .has_varkeywords = false }");
}

// ============================================================================
// SymbolTable class
// ============================================================================

/// Generate symtable.SymbolTable
pub fn genSymbolTable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .type = \"module\", .id = 0 }");
}

/// Generate SymbolTable.get_type()
pub fn genGet_type(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"module\"");
}

/// Generate SymbolTable.get_id()
pub fn genGet_id(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate SymbolTable.get_name()
pub fn genGet_name(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"<module>\"");
}

/// Generate SymbolTable.get_lineno()
pub fn genGet_lineno(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 1)");
}

/// Generate SymbolTable.is_optimized()
pub fn genIs_optimized(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate SymbolTable.is_nested()
pub fn genIs_nested(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate SymbolTable.has_children()
pub fn genHas_children(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate SymbolTable.has_exec()
pub fn genHas_exec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate SymbolTable.get_identifiers()
pub fn genGet_identifiers(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).init()");
}

/// Generate SymbolTable.lookup(name)
pub fn genLookup(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const name = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .name = name, .is_referenced = true, .is_imported = false, .is_parameter = false, .is_global = false, .is_nonlocal = false, .is_declared_global = false, .is_local = true, .is_annotated = false, .is_free = false, .is_assigned = true, .is_namespace = false }; }");
    } else {
        try self.emit(".{ .name = \"\", .is_referenced = false, .is_imported = false, .is_parameter = false, .is_global = false, .is_nonlocal = false, .is_declared_global = false, .is_local = false, .is_annotated = false, .is_free = false, .is_assigned = false, .is_namespace = false }");
    }
}

/// Generate SymbolTable.get_symbols()
pub fn genGet_symbols(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList(@TypeOf(.{ .name = \"\", .is_referenced = false })).init()");
}

/// Generate SymbolTable.get_children()
pub fn genGet_children(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList(@TypeOf(.{ .name = \"\", .type = \"\" })).init()");
}

// ============================================================================
// Symbol class
// ============================================================================

/// Generate symtable.Symbol
pub fn genSymbol(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .is_referenced = false, .is_imported = false, .is_parameter = false, .is_global = false, .is_nonlocal = false, .is_declared_global = false, .is_local = false, .is_annotated = false, .is_free = false, .is_assigned = false, .is_namespace = false }");
}

/// Generate Symbol.get_name()
pub fn genSymbol_get_name(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate Symbol.is_referenced()
pub fn genIs_referenced(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Symbol.is_imported()
pub fn genIs_imported(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Symbol.is_parameter()
pub fn genIs_parameter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Symbol.is_global()
pub fn genIs_global(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Symbol.is_nonlocal()
pub fn genIs_nonlocal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Symbol.is_declared_global()
pub fn genIs_declared_global(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Symbol.is_local()
pub fn genIs_local(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Symbol.is_annotated()
pub fn genIs_annotated(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Symbol.is_free()
pub fn genIs_free(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Symbol.is_assigned()
pub fn genIs_assigned(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Symbol.is_namespace()
pub fn genIs_namespace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Symbol.get_namespaces()
pub fn genGet_namespaces(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList(@TypeOf(.{ .name = \"\" })).init()");
}

// ============================================================================
// Function class
// ============================================================================

/// Generate symtable.Function (subclass of SymbolTable)
pub fn genFunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .type = \"function\", .id = 0 }");
}

/// Generate Function.get_parameters()
pub fn genGet_parameters(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).init()");
}

/// Generate Function.get_locals()
pub fn genGet_locals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).init()");
}

/// Generate Function.get_globals()
pub fn genGet_globals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).init()");
}

/// Generate Function.get_nonlocals()
pub fn genGet_nonlocals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).init()");
}

/// Generate Function.get_frees()
pub fn genGet_frees(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).init()");
}

// ============================================================================
// Class class
// ============================================================================

/// Generate symtable.Class (subclass of SymbolTable)
pub fn genClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .type = \"class\", .id = 0 }");
}

/// Generate Class.get_methods()
pub fn genGet_methods(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).init()");
}
