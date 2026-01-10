//! test.test_tools.test_sundry - Sundry tools testing
//! Tests for miscellaneous Python development tools including
//! indentation fixers, pyclbr, and other utilities.

const std = @import("std");

/// Python indentation analyzer and fixer
pub const IndentationFixer = struct {
    allocator: std.mem.Allocator,
    indent_size: usize = 4,
    use_tabs: bool = false,
    issues: std.ArrayList(IndentIssue),

    pub const IndentIssue = struct {
        line: usize,
        kind: Kind,
        current_indent: usize,
        expected_indent: usize,

        pub const Kind = enum {
            mixed_tabs_spaces,
            wrong_size,
            unexpected_indent,
            missing_indent,
        };
    };

    pub fn init(allocator: std.mem.Allocator) IndentationFixer {
        return .{
            .allocator = allocator,
            .issues = std.ArrayList(IndentIssue).init(allocator),
        };
    }

    pub fn deinit(self: *IndentationFixer) void {
        self.issues.deinit();
    }

    pub fn analyzeIndent(self: IndentationFixer, line: []const u8) IndentInfo {
        var spaces: usize = 0;
        var tabs: usize = 0;

        for (line) |c| {
            if (c == ' ') {
                spaces += 1;
            } else if (c == '\t') {
                tabs += 1;
            } else {
                break;
            }
        }

        return .{
            .spaces = spaces,
            .tabs = tabs,
            .total = spaces + tabs * self.indent_size,
            .is_mixed = spaces > 0 and tabs > 0,
        };
    }

    pub fn checkLine(self: *IndentationFixer, line_num: usize, line: []const u8, expected_level: usize) !void {
        const info = self.analyzeIndent(line);

        if (info.is_mixed) {
            try self.issues.append(.{
                .line = line_num,
                .kind = .mixed_tabs_spaces,
                .current_indent = info.total,
                .expected_indent = expected_level * self.indent_size,
            });
        } else if (info.total != expected_level * self.indent_size) {
            const kind: IndentIssue.Kind = if (info.total > expected_level * self.indent_size)
                .unexpected_indent
            else
                .missing_indent;

            try self.issues.append(.{
                .line = line_num,
                .kind = kind,
                .current_indent = info.total,
                .expected_indent = expected_level * self.indent_size,
            });
        }
    }

    pub fn fixLine(self: IndentationFixer, line: []const u8, new_level: usize) ![]u8 {
        const info = self.analyzeIndent(line);
        const content_start = info.spaces + info.tabs;
        const content = line[content_start..];

        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        const indent_char: u8 = if (self.use_tabs) '\t' else ' ';
        const indent_count = if (self.use_tabs) new_level else new_level * self.indent_size;

        var i: usize = 0;
        while (i < indent_count) : (i += 1) {
            try result.append(indent_char);
        }
        try result.appendSlice(content);

        return result.toOwnedSlice();
    }

    pub const IndentInfo = struct {
        spaces: usize,
        tabs: usize,
        total: usize,
        is_mixed: bool,
    };

    pub fn hasIssues(self: IndentationFixer) bool {
        return self.issues.items.len > 0;
    }
};

/// Python class browser (pyclbr-like functionality)
pub const ClassBrowser = struct {
    allocator: std.mem.Allocator,
    classes: std.StringHashMap(ClassInfo),
    functions: std.StringHashMap(FunctionInfo),

    pub const ClassInfo = struct {
        name: []const u8,
        module: []const u8,
        lineno: usize,
        end_lineno: ?usize = null,
        super_classes: []const []const u8 = &.{},
        methods: []const []const u8 = &.{},
    };

    pub const FunctionInfo = struct {
        name: []const u8,
        module: []const u8,
        lineno: usize,
        end_lineno: ?usize = null,
        is_async: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) ClassBrowser {
        return .{
            .allocator = allocator,
            .classes = std.StringHashMap(ClassInfo).init(allocator),
            .functions = std.StringHashMap(FunctionInfo).init(allocator),
        };
    }

    pub fn deinit(self: *ClassBrowser) void {
        self.classes.deinit();
        self.functions.deinit();
    }

    pub fn addClass(self: *ClassBrowser, info: ClassInfo) !void {
        try self.classes.put(info.name, info);
    }

    pub fn addFunction(self: *ClassBrowser, info: FunctionInfo) !void {
        try self.functions.put(info.name, info);
    }

    pub fn getClass(self: ClassBrowser, name: []const u8) ?ClassInfo {
        return self.classes.get(name);
    }

    pub fn getFunction(self: ClassBrowser, name: []const u8) ?FunctionInfo {
        return self.functions.get(name);
    }

    pub fn classCount(self: ClassBrowser) usize {
        return self.classes.count();
    }

    pub fn functionCount(self: ClassBrowser) usize {
        return self.functions.count();
    }
};

/// AST dumper for debugging
pub const AstDumper = struct {
    allocator: std.mem.Allocator,
    indent_level: usize = 0,
    include_attributes: bool = true,
    output: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) AstDumper {
        return .{
            .allocator = allocator,
            .output = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *AstDumper) void {
        self.output.deinit();
    }

    pub fn dumpNode(self: *AstDumper, node_type: []const u8, fields: []const Field) !void {
        try self.writeIndent();
        try self.output.appendSlice(node_type);
        try self.output.append('(');

        if (fields.len > 0) {
            try self.output.append('\n');
            self.indent_level += 1;

            for (fields, 0..) |field, i| {
                try self.writeIndent();
                try self.output.appendSlice(field.name);
                try self.output.append('=');
                try self.output.appendSlice(field.value);
                if (i < fields.len - 1) {
                    try self.output.append(',');
                }
                try self.output.append('\n');
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }

        try self.output.append(')');
    }

    fn writeIndent(self: *AstDumper) !void {
        var i: usize = 0;
        while (i < self.indent_level * 2) : (i += 1) {
            try self.output.append(' ');
        }
    }

    pub fn getOutput(self: *AstDumper) ![]u8 {
        return self.output.toOwnedSlice();
    }

    pub const Field = struct {
        name: []const u8,
        value: []const u8,
    };
};

/// Symbol table analyzer
pub const SymbolTable = struct {
    allocator: std.mem.Allocator,
    symbols: std.StringHashMap(Symbol),
    parent: ?*SymbolTable = null,
    children: std.ArrayList(*SymbolTable),
    scope_type: ScopeType,
    name: []const u8,

    pub const Symbol = struct {
        name: []const u8,
        kind: Kind,
        scope: Scope,
        lineno: usize,
        is_referenced: bool = false,
        is_assigned: bool = false,

        pub const Kind = enum {
            variable,
            function,
            class,
            parameter,
            imported,
            free,
            cell,
        };

        pub const Scope = enum {
            local,
            global_explicit,
            global_implicit,
            free,
            cell,
        };
    };

    pub const ScopeType = enum {
        module,
        class,
        function,
        lambda,
        comprehension,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8, scope_type: ScopeType) SymbolTable {
        return .{
            .allocator = allocator,
            .symbols = std.StringHashMap(Symbol).init(allocator),
            .children = std.ArrayList(*SymbolTable).init(allocator),
            .scope_type = scope_type,
            .name = name,
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();
        self.symbols.deinit();
    }

    pub fn addSymbol(self: *SymbolTable, symbol: Symbol) !void {
        try self.symbols.put(symbol.name, symbol);
    }

    pub fn lookup(self: SymbolTable, name: []const u8) ?Symbol {
        if (self.symbols.get(name)) |sym| {
            return sym;
        }
        if (self.parent) |p| {
            return p.lookup(name);
        }
        return null;
    }

    pub fn lookupLocal(self: SymbolTable, name: []const u8) ?Symbol {
        return self.symbols.get(name);
    }

    pub fn createChild(self: *SymbolTable, name: []const u8, scope_type: ScopeType) !*SymbolTable {
        const child = try self.allocator.create(SymbolTable);
        child.* = SymbolTable.init(self.allocator, name, scope_type);
        child.parent = self;
        try self.children.append(child);
        return child;
    }

    pub fn getGlobals(self: SymbolTable) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        errdefer result.deinit();

        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.scope == .global_explicit) {
                try result.append(entry.key_ptr.*);
            }
        }

        return result.toOwnedSlice();
    }

    pub fn getLocals(self: SymbolTable) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        errdefer result.deinit();

        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.scope == .local) {
                try result.append(entry.key_ptr.*);
            }
        }

        return result.toOwnedSlice();
    }
};

/// Import analyzer
pub const ImportAnalyzer = struct {
    allocator: std.mem.Allocator,
    imports: std.ArrayList(ImportInfo),
    from_imports: std.ArrayList(FromImportInfo),

    pub const ImportInfo = struct {
        module: []const u8,
        alias: ?[]const u8 = null,
        lineno: usize,
    };

    pub const FromImportInfo = struct {
        module: []const u8,
        names: []const NameAlias,
        level: usize = 0, // for relative imports
        lineno: usize,

        pub const NameAlias = struct {
            name: []const u8,
            alias: ?[]const u8 = null,
        };
    };

    pub fn init(allocator: std.mem.Allocator) ImportAnalyzer {
        return .{
            .allocator = allocator,
            .imports = std.ArrayList(ImportInfo).init(allocator),
            .from_imports = std.ArrayList(FromImportInfo).init(allocator),
        };
    }

    pub fn deinit(self: *ImportAnalyzer) void {
        self.imports.deinit();
        self.from_imports.deinit();
    }

    pub fn addImport(self: *ImportAnalyzer, info: ImportInfo) !void {
        try self.imports.append(info);
    }

    pub fn addFromImport(self: *ImportAnalyzer, info: FromImportInfo) !void {
        try self.from_imports.append(info);
    }

    pub fn getAllModules(self: ImportAnalyzer) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        errdefer result.deinit();

        for (self.imports.items) |imp| {
            try result.append(imp.module);
        }
        for (self.from_imports.items) |from_imp| {
            try result.append(from_imp.module);
        }

        return result.toOwnedSlice();
    }

    pub fn isStdlibImport(self: ImportAnalyzer, module: []const u8) bool {
        _ = self;
        const stdlib_modules = [_][]const u8{
            "os",        "sys",     "re",      "json",    "collections",
            "itertools", "functools", "typing", "pathlib", "datetime",
            "math",      "random",  "string",  "io",      "time",
        };

        for (stdlib_modules) |stdlib| {
            if (std.mem.eql(u8, module, stdlib)) return true;
            if (std.mem.startsWith(u8, module, stdlib) and
                module.len > stdlib.len and
                module[stdlib.len] == '.')
            {
                return true;
            }
        }
        return false;
    }
};

/// Code metrics calculator
pub const CodeMetrics = struct {
    lines_of_code: usize = 0,
    lines_of_comments: usize = 0,
    blank_lines: usize = 0,
    functions: usize = 0,
    classes: usize = 0,
    cyclomatic_complexity: usize = 1,
    max_nesting_depth: usize = 0,

    pub fn addLine(self: *CodeMetrics, line: []const u8) void {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        if (trimmed.len == 0) {
            self.blank_lines += 1;
        } else if (std.mem.startsWith(u8, trimmed, "#")) {
            self.lines_of_comments += 1;
        } else {
            self.lines_of_code += 1;

            // Count complexity contributors
            if (std.mem.indexOf(u8, trimmed, "if ") != null or
                std.mem.indexOf(u8, trimmed, "elif ") != null or
                std.mem.indexOf(u8, trimmed, "for ") != null or
                std.mem.indexOf(u8, trimmed, "while ") != null or
                std.mem.indexOf(u8, trimmed, "except") != null or
                std.mem.indexOf(u8, trimmed, " and ") != null or
                std.mem.indexOf(u8, trimmed, " or ") != null)
            {
                self.cyclomatic_complexity += 1;
            }

            if (std.mem.startsWith(u8, trimmed, "def ")) {
                self.functions += 1;
            }
            if (std.mem.startsWith(u8, trimmed, "class ")) {
                self.classes += 1;
            }
        }
    }

    pub fn totalLines(self: CodeMetrics) usize {
        return self.lines_of_code + self.lines_of_comments + self.blank_lines;
    }

    pub fn commentRatio(self: CodeMetrics) f64 {
        const total = self.lines_of_code + self.lines_of_comments;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.lines_of_comments)) / @as(f64, @floatFromInt(total));
    }
};

/// Deprecation warning tracker
pub const DeprecationTracker = struct {
    allocator: std.mem.Allocator,
    warnings: std.ArrayList(Deprecation),

    pub const Deprecation = struct {
        name: []const u8,
        since_version: []const u8,
        removal_version: ?[]const u8 = null,
        replacement: ?[]const u8 = null,
        message: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) DeprecationTracker {
        return .{
            .allocator = allocator,
            .warnings = std.ArrayList(Deprecation).init(allocator),
        };
    }

    pub fn deinit(self: *DeprecationTracker) void {
        self.warnings.deinit();
    }

    pub fn add(self: *DeprecationTracker, deprecation: Deprecation) !void {
        try self.warnings.append(deprecation);
    }

    pub fn getForVersion(self: DeprecationTracker, version: []const u8) ![]Deprecation {
        var result = std.ArrayList(Deprecation).init(self.allocator);
        errdefer result.deinit();

        for (self.warnings.items) |warning| {
            if (warning.removal_version) |removal| {
                if (std.mem.eql(u8, removal, version)) {
                    try result.append(warning);
                }
            }
        }

        return result.toOwnedSlice();
    }

    pub fn count(self: DeprecationTracker) usize {
        return self.warnings.items.len;
    }
};

// Tests
test "indentation_analyzer" {
    const fixer = IndentationFixer.init(std.testing.allocator);

    const info1 = fixer.analyzeIndent("    code");
    try std.testing.expectEqual(@as(usize, 4), info1.spaces);
    try std.testing.expectEqual(@as(usize, 0), info1.tabs);
    try std.testing.expect(!info1.is_mixed);

    const info2 = fixer.analyzeIndent("\t code");
    try std.testing.expect(info2.is_mixed);
}

test "indentation_fixer" {
    var fixer = IndentationFixer.init(std.testing.allocator);
    defer fixer.deinit();

    const fixed = try fixer.fixLine("  code", 2);
    defer std.testing.allocator.free(fixed);
    try std.testing.expectEqualStrings("        code", fixed);
}

test "class_browser" {
    var browser = ClassBrowser.init(std.testing.allocator);
    defer browser.deinit();

    try browser.addClass(.{
        .name = "MyClass",
        .module = "mymodule",
        .lineno = 10,
        .super_classes = &[_][]const u8{"BaseClass"},
    });

    try browser.addFunction(.{
        .name = "my_function",
        .module = "mymodule",
        .lineno = 50,
    });

    try std.testing.expectEqual(@as(usize, 1), browser.classCount());
    try std.testing.expectEqual(@as(usize, 1), browser.functionCount());

    const cls = browser.getClass("MyClass");
    try std.testing.expect(cls != null);
    try std.testing.expectEqual(@as(usize, 10), cls.?.lineno);
}

test "ast_dumper" {
    var dumper = AstDumper.init(std.testing.allocator);
    defer dumper.deinit();

    try dumper.dumpNode("Module", &[_]AstDumper.Field{
        .{ .name = "body", .value = "[...]" },
    });

    const output = try dumper.getOutput();
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "Module") != null);
}

test "symbol_table" {
    var table = SymbolTable.init(std.testing.allocator, "module", .module);
    defer table.deinit();

    try table.addSymbol(.{
        .name = "x",
        .kind = .variable,
        .scope = .local,
        .lineno = 1,
    });

    try table.addSymbol(.{
        .name = "y",
        .kind = .variable,
        .scope = .global_explicit,
        .lineno = 2,
    });

    const x = table.lookup("x");
    try std.testing.expect(x != null);
    try std.testing.expectEqual(SymbolTable.Symbol.Kind.variable, x.?.kind);

    const globals = try table.getGlobals();
    defer std.testing.allocator.free(globals);
    try std.testing.expectEqual(@as(usize, 1), globals.len);
}

test "symbol_table_child" {
    var table = SymbolTable.init(std.testing.allocator, "module", .module);
    defer table.deinit();

    try table.addSymbol(.{
        .name = "outer",
        .kind = .variable,
        .scope = .local,
        .lineno = 1,
    });

    const child = try table.createChild("function", .function);
    try child.addSymbol(.{
        .name = "inner",
        .kind = .variable,
        .scope = .local,
        .lineno = 5,
    });

    // Child can see parent's symbols
    try std.testing.expect(child.lookup("outer") != null);
    try std.testing.expect(child.lookup("inner") != null);

    // Parent cannot see child's symbols
    try std.testing.expect(table.lookup("inner") == null);
}

test "import_analyzer" {
    var analyzer = ImportAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();

    try analyzer.addImport(.{ .module = "os", .lineno = 1 });
    try analyzer.addImport(.{ .module = "sys", .alias = "system", .lineno = 2 });
    try analyzer.addFromImport(.{
        .module = "collections",
        .names = &[_]ImportAnalyzer.FromImportInfo.NameAlias{
            .{ .name = "OrderedDict" },
        },
        .lineno = 3,
    });

    const modules = try analyzer.getAllModules();
    defer std.testing.allocator.free(modules);
    try std.testing.expectEqual(@as(usize, 3), modules.len);

    try std.testing.expect(analyzer.isStdlibImport("os"));
    try std.testing.expect(analyzer.isStdlibImport("collections"));
    try std.testing.expect(!analyzer.isStdlibImport("mypackage"));
}

test "code_metrics" {
    var metrics = CodeMetrics{};

    metrics.addLine("def foo():");
    metrics.addLine("    # comment");
    metrics.addLine("    if x:");
    metrics.addLine("        return True");
    metrics.addLine("");
    metrics.addLine("class Bar:");

    try std.testing.expectEqual(@as(usize, 4), metrics.lines_of_code);
    try std.testing.expectEqual(@as(usize, 1), metrics.lines_of_comments);
    try std.testing.expectEqual(@as(usize, 1), metrics.blank_lines);
    try std.testing.expectEqual(@as(usize, 1), metrics.functions);
    try std.testing.expectEqual(@as(usize, 1), metrics.classes);
    try std.testing.expectEqual(@as(usize, 6), metrics.totalLines());
}

test "deprecation_tracker" {
    var tracker = DeprecationTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try tracker.add(.{
        .name = "old_function",
        .since_version = "3.10",
        .removal_version = "3.12",
        .replacement = "new_function",
        .message = "Use new_function instead",
    });

    try std.testing.expectEqual(@as(usize, 1), tracker.count());

    const removals = try tracker.getForVersion("3.12");
    defer std.testing.allocator.free(removals);
    try std.testing.expectEqual(@as(usize, 1), removals.len);
}
