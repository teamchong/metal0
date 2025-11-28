/// Python _csv module - C accelerator for csv (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _csv.reader(csvfile, dialect='excel', **fmtparams)
pub fn genReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const csvfile = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .file = csvfile, .dialect = \"excel\" }; }");
    } else {
        try self.emit(".{ .file = null, .dialect = \"excel\" }");
    }
}

/// Generate _csv.writer(csvfile, dialect='excel', **fmtparams)
pub fn genWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const csvfile = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .file = csvfile, .dialect = \"excel\" }; }");
    } else {
        try self.emit(".{ .file = null, .dialect = \"excel\" }");
    }
}

/// Generate _csv.register_dialect(name, dialect=None, **fmtparams)
pub fn genRegisterDialect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _csv.unregister_dialect(name)
pub fn genUnregisterDialect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _csv.get_dialect(name)
pub fn genGetDialect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .delimiter = ',', .quotechar = '\"', .escapechar = null, .doublequote = true, .skipinitialspace = false, .lineterminator = \"\\r\\n\", .quoting = 0, .strict = false }");
}

/// Generate _csv.list_dialects()
pub fn genListDialects(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"excel\", \"excel-tab\", \"unix\" }");
}

/// Generate _csv.field_size_limit(new_limit=None)
pub fn genFieldSizeLimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(i64, 131072)");
    }
}

// Constants
pub fn genQUOTE_ALL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genQUOTE_MINIMAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genQUOTE_NONNUMERIC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genQUOTE_NONE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

// Exceptions
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.CsvError");
}
