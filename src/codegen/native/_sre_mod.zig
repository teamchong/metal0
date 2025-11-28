/// Python _sre module - Internal SRE support (C accelerator for regex)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _sre.compile(pattern, flags, code, groups, groupindex, indexgroup)
pub fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const pat = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = pat; break :blk .{ .pattern = pat, .flags = 0, .groups = 0 }; }");
    } else {
        try self.emit(".{ .pattern = \"\", .flags = 0, .groups = 0 }");
    }
}

/// Generate _sre.CODESIZE constant
pub fn genCODESIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

/// Generate _sre.MAGIC constant
pub fn genMAGIC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 20171005)");
}

/// Generate _sre.getlower(character, flags)
pub fn genGetlower(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(i32, 0)");
    }
}

/// Generate _sre.getcodesize()
pub fn genGetcodesize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

/// Generate SRE_Pattern.match(string, pos=0, endpos=sys.maxsize)
pub fn genMatch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate SRE_Pattern.fullmatch(string, pos=0, endpos=sys.maxsize)
pub fn genFullmatch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate SRE_Pattern.search(string, pos=0, endpos=sys.maxsize)
pub fn genSearch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate SRE_Pattern.findall(string, pos=0, endpos=sys.maxsize)
pub fn genFindall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate SRE_Pattern.finditer(string, pos=0, endpos=sys.maxsize)
pub fn genFinditer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(null){}");
}

/// Generate SRE_Pattern.sub(repl, string, count=0)
pub fn genSub(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate SRE_Pattern.subn(repl, string, count=0)
pub fn genSubn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit(".{ ");
        try self.genExpr(args[1]);
        try self.emit(", @as(i64, 0) }");
    } else {
        try self.emit(".{ \"\", @as(i64, 0) }");
    }
}

/// Generate SRE_Pattern.split(string, maxsplit=0)
pub fn genSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate SRE_Match.group(*args)
pub fn genGroup(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate SRE_Match.groups(default=None)
pub fn genGroups(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate SRE_Match.groupdict(default=None)
pub fn genGroupdict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate SRE_Match.start(group=0)
pub fn genStart(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate SRE_Match.end(group=0)
pub fn genEnd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate SRE_Match.span(group=0)
pub fn genSpan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i64, 0), @as(i64, 0) }");
}

/// Generate SRE_Match.expand(template)
pub fn genExpand(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}
