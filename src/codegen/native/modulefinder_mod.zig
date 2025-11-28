/// Python modulefinder module - Find modules used by a script
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate modulefinder.ModuleFinder(path=None, debug=0, excludes=[], replace_paths=[])
pub fn genModuleFinder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .modules = .{}, .badmodules = .{}, .debug = 0, .indent = 0, .excludes = &[_][]const u8{}, .replace_paths = &[_]struct { []const u8, []const u8 }{} }");
}

/// Generate ModuleFinder.msg(level, s, *args)
pub fn genMsg(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ModuleFinder.msgin(level, *args)
pub fn genMsgin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ModuleFinder.msgout(level, *args)
pub fn genMsgout(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ModuleFinder.run_script(pathname)
pub fn genRunScript(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ModuleFinder.load_file(pathname)
pub fn genLoadFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ModuleFinder.import_hook(name, caller=None, fromlist=None, level=-1)
pub fn genImportHook(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate ModuleFinder.determine_parent(caller, level=-1)
pub fn genDetermineParent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate ModuleFinder.find_head_package(parent, name)
pub fn genFindHeadPackage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ null, \"\" }");
}

/// Generate ModuleFinder.load_tail(q, tail)
pub fn genLoadTail(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate ModuleFinder.ensure_fromlist(m, fromlist, recursive=0)
pub fn genEnsureFromlist(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ModuleFinder.find_all_submodules(m)
pub fn genFindAllSubmodules(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ModuleFinder.import_module(partname, fqname, parent)
pub fn genImportModule(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate ModuleFinder.load_module(fqname, fp, pathname, file_info)
pub fn genLoadModule(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate ModuleFinder.scan_code(co, m)
pub fn genScanCode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ModuleFinder.scan_opcodes(co)
pub fn genScanOpcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate ModuleFinder.any_missing()
pub fn genAnyMissing(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate ModuleFinder.any_missing_maybe()
pub fn genAnyMissingMaybe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ &[_][]const u8{}, .{} }");
}

/// Generate ModuleFinder.replace_paths_in_code(co)
pub fn genReplacePathsInCode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("null");
    }
}

/// Generate ModuleFinder.report()
pub fn genReport(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate modulefinder.Module class
pub fn genModule(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .__name__ = \"\", .__file__ = null, .__path__ = null, .__code__ = null, .globalnames = .{}, .starimports = .{} }");
}

/// Generate modulefinder.ReplacePackage(old, new)
pub fn genReplacePackage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate modulefinder.AddPackagePath(packagename, path)
pub fn genAddPackagePath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}
