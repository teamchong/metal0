/// Python pydoc module - Documentation generation and display
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "help", genHelp },
    .{ "doc", genDoc },
    .{ "writedoc", genWritedoc },
    .{ "writedocs", genWritedocs },
    .{ "render_doc", genRenderDoc },
    .{ "plain", genPlain },
    .{ "describe", genDescribe },
    .{ "locate", genLocate },
    .{ "resolve", genResolve },
    .{ "getdoc", genGetdoc },
    .{ "splitdoc", genSplitdoc },
    .{ "classname", genClassname },
    .{ "isdata", genIsdata },
    .{ "ispackage", genIspackage },
    .{ "source_synopsis", genSourceSynopsis },
    .{ "synopsis", genSynopsis },
    .{ "allmethods", genAllmethods },
    .{ "apropos", genApropos },
    .{ "serve", genServe },
    .{ "browse", genBrowse },
});

/// Generate pydoc.help(request)
pub fn genHelp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pydoc.doc(thing, title='Python Library Documentation: %s', forceload=0, output=None)
pub fn genDoc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pydoc.writedoc(thing, forceload=0)
pub fn genWritedoc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pydoc.writedocs(dir, pkgpath='', done=None)
pub fn genWritedocs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pydoc.render_doc(thing, title='Python Library Documentation: %s', forceload=0)
pub fn genRenderDoc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate pydoc.plain(text)
pub fn genPlain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate pydoc.describe(thing)
pub fn genDescribe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"object\"");
}

/// Generate pydoc.locate(path, forceload=0)
pub fn genLocate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate pydoc.resolve(thing, forceload=0)
pub fn genResolve(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ null, \"\" }");
}

/// Generate pydoc.getdoc(object)
pub fn genGetdoc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate pydoc.splitdoc(doc)
pub fn genSplitdoc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", \"\" }");
}

/// Generate pydoc.classname(object, modname)
pub fn genClassname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"object\"");
}

/// Generate pydoc.isdata(object)
pub fn genIsdata(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate pydoc.ispackage(path)
pub fn genIspackage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate pydoc.source_synopsis(file)
pub fn genSourceSynopsis(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate pydoc.synopsis(filename, cache={})
pub fn genSynopsis(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate pydoc.allmethods(cl)
pub fn genAllmethods(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate pydoc.apropos(key)
pub fn genApropos(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pydoc.serve(port, callback=None, completer=None)
pub fn genServe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pydoc.browse(port=0, *, open_browser=True)
pub fn genBrowse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}
